/**
 * The shared answer service for Puck: a Cloudflare Worker that holds one Groq
 * key as a secret so no phone has to.
 *
 * This file is a reference implementation, and it is deliberately the smallest
 * thing that can hold a key honestly:
 *
 *   - the key never leaves the Worker (`env.GROQ_API_KEY` secret),
 *   - the app sends no identity except `X-Puck-Device`, a random UUID that
 *     exists only so one phone cannot spend everyone's quota,
 *   - the request shape is validated, and the *sampling parameters are set
 *     here* rather than trusted from the client, so a modified client cannot
 *     turn this into a free general-purpose LLM writing essays on the owner's
 *     bill,
 *   - there is a kill switch and a global daily ceiling,
 *   - nothing is logged except counters. No prompt, no answer, no device id
 *     in the logs.
 *
 * Read FINDINGS.md §4.1 before deploying it: running this spends money, and
 * the ceiling is the owner's decision, not the author's.
 *
 * Deploy (once you have decided):
 *
 *   cd worker
 *   npx wrangler kv namespace create PUCK_KV        # paste the id below
 *   npx wrangler secret put GROQ_API_KEY            # paste the key
 *   npx wrangler deploy
 *
 * Then build the app with the URL it prints:
 *
 *   flutter build apk --dart-define=PUCK_PROXY_URL=https://puck-answers.<account>.workers.dev
 */

const GROQ_URL = 'https://api.groq.com/openai/v1/chat/completions';
const MODEL = 'openai/gpt-oss-20b';

/** Mirrors PuckPrompt: a prompt that says "be brief" is a request, a token cap
 * is a guarantee. See lib/src/data/llm/prompt.dart. */
const MODES = {
  context: { temperature: 0.2, max_completion_tokens: 54, stop: ['\n'] },
  intent: { temperature: 0.3, max_completion_tokens: 69, stop: ['\n\n'] },
};

const MAX_BODY_BYTES = 8 * 1024;
const MAX_MESSAGE_CHARS = 2000;
/** Must appear in the system turn: it is how a request is recognisably a Puck
 * request rather than someone else's prompt. */
const PROMPT_MARKER = 'You are the intelligence engine inside Puck';

export default {
  /**
   * @param {Request} request
   * @param {{GROQ_API_KEY: string, KILL_SWITCH?: string, DAILY_CEILING?: string,
   *          DEVICE_HOURLY_LIMIT?: string, PUCK_KV: KVNamespace}} env
   * @param {{waitUntil: (p: Promise<unknown>) => void}} ctx
   */
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    if (request.method !== 'POST' || url.pathname !== '/v1/answer') {
      return json({ error: 'not_found' }, 404);
    }

    // -- Kill switch ---------------------------------------------------------
    // One environment variable turns every phone back to the offline resolver.
    // It is checked before anything else, including the body.
    if (env.KILL_SWITCH === 'true' || env.KILL_SWITCH === '1') {
      return json({ error: 'off' }, 503);
    }
    if (!env.GROQ_API_KEY) {
      // Misconfigured, not off. The app treats both the same way.
      return json({ error: 'not_configured' }, 503);
    }

    // -- Who, and how often --------------------------------------------------
    const device = request.headers.get('X-Puck-Device') || '';
    if (!/^[0-9a-f-]{8,64}$/i.test(device)) {
      return json({ error: 'bad_device' }, 400);
    }

    const size = Number(request.headers.get('Content-Length') || '0');
    if (size > MAX_BODY_BYTES) return json({ error: 'too_large' }, 413);

    const now = new Date();
    const day = now.toISOString().slice(0, 10);
    const hour = now.toISOString().slice(0, 13);

    const ceiling = Number(env.DAILY_CEILING || '0');
    if (ceiling > 0) {
      const used = Number((await env.PUCK_KV.get(`global:${day}`)) || '0');
      if (used >= ceiling) return json({ error: 'ceiling' }, 429);
      ctx.waitUntil(
        env.PUCK_KV.put(`global:${day}`, String(used + 1), {
          expirationTtl: 172800,
        }),
      );
    }

    const perDevice = Number(env.DEVICE_HOURLY_LIMIT || '60');
    const deviceKey = `dev:${device}:${hour}`;
    const deviceUsed = Number((await env.PUCK_KV.get(deviceKey)) || '0');
    if (deviceUsed >= perDevice) {
      return new Response(JSON.stringify({ error: 'rate_limited' }), {
        status: 429,
        headers: { 'Content-Type': 'application/json', 'Retry-After': '600' },
      });
    }
    ctx.waitUntil(
      env.PUCK_KV.put(deviceKey, String(deviceUsed + 1), {
        expirationTtl: 7200,
      }),
    );

    // -- Shape ---------------------------------------------------------------
    let body;
    try {
      body = await request.json();
    } catch (_) {
      return json({ error: 'bad_json' }, 400);
    }

    const mode = body && body.mode;
    if (mode !== 'intent' && mode !== 'context') {
      return json({ error: 'bad_mode' }, 400);
    }

    const messages = body.messages;
    if (!Array.isArray(messages) || messages.length !== 2) {
      return json({ error: 'bad_messages' }, 400);
    }
    for (const message of messages) {
      if (
        !message ||
        typeof message.content !== 'string' ||
        message.content.length > MAX_MESSAGE_CHARS ||
        (message.role !== 'system' && message.role !== 'user')
      ) {
        return json({ error: 'bad_messages' }, 400);
      }
    }
    if (!messages[0].content.includes(PROMPT_MARKER)) {
      // Not a Puck request. This is the line that keeps a free endpoint from
      // being someone's general-purpose model.
      return json({ error: 'not_puck' }, 403);
    }

    // -- Upstream ------------------------------------------------------------
    const upstream = await fetch(GROQ_URL, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${env.GROQ_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: MODEL,
        stream: true,
        messages: messages,
        reasoning_effort: 'low',
        // Set here, not taken from the client.
        temperature: MODES[mode].temperature,
        max_completion_tokens: MODES[mode].max_completion_tokens,
        stop: MODES[mode].stop,
      }),
    });

    if (!upstream.ok) {
      // The upstream body may name the account's plan or limits; the client
      // does not need it and the logs must not keep it.
      return json({ error: 'upstream', status: upstream.status }, 502);
    }

    // Pass the stream straight through: buffering it would destroy the
    // property the app is built around -- the first words appear while the
    // model is still writing.
    return new Response(upstream.body, {
      status: 200,
      headers: {
        'Content-Type': 'text/event-stream',
        'Cache-Control': 'no-store',
      },
    });
  },
};

function json(payload, status) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}
