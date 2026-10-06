/**
 * The shared answer service's rules, tested by running them.
 *
 * `node --test worker/test/*.test.mjs` from the repository root. No Cloudflare account,
 * no wrangler, no network: the upstream `fetch` is replaced by a stub, and KV
 * by the three-method object below. Node 20+ is enough because the handler
 * uses nothing but `fetch`, `Request`, `Response` and `KVNamespace.get/put`,
 * all of which are standard.
 *
 * This is the one part of the Puck tree that can be executed in the
 * environment this repository was authored in, which makes it the one part
 * where "it passes" is an honest sentence. See FINDINGS.md §1.
 */

import assert from 'node:assert/strict';
import test from 'node:test';

import worker from '../src/index.js';

/** A KVNamespace's worth of behaviour: get, put, and forget. */
function fakeKv() {
  const store = new Map();
  return {
    async get(key) {
      return store.has(key) ? store.get(key) : null;
    },
    async put(key, value) {
      store.set(key, value);
    },
    _store: store,
  };
}

function env(overrides = {}) {
  return {
    GROQ_API_KEY: 'test-key-not-real',
    KILL_SWITCH: 'false',
    DAILY_CEILING: '1000',
    DEVICE_HOURLY_LIMIT: '60',
    PUCK_KV: fakeKv(),
    ...overrides,
  };
}

const ctx = { waitUntil: () => {} };

const SYSTEM = 'You are the intelligence engine inside Puck, a zero-friction…';

function body(overrides = {}) {
  return JSON.stringify({
    mode: 'intent',
    messages: [
      { role: 'system', content: SYSTEM },
      { role: 'user', content: 'why is the sky blue' },
    ],
    ...overrides,
  });
}

function request({ method = 'POST', path = '/v1/answer', device = 'a1b2c3d4-0000-4000-8000-000000000000', payload = body(), headers = {} } = {}) {
  return new Request(`https://answers.example.org${path}`, {
    method,
    headers: {
      'Content-Type': 'application/json',
      'X-Puck-Device': device,
      ...headers,
    },
    body: method === 'POST' ? payload : undefined,
  });
}

/** Replaces global fetch for the duration of `fn`. */
async function withUpstream(response, fn) {
  const original = globalThis.fetch;
  let seen = null;
  globalThis.fetch = async (url, init) => {
    seen = { url, init };
    return response();
  };
  try {
    return await fn(() => seen);
  } finally {
    globalThis.fetch = original;
  }
}

const sseOk = () =>
  new Response('data: {"choices":[{"delta":{"content":"Blue."}}]}\n\ndata: [DONE]\n\n', {
    status: 200,
    headers: { 'Content-Type': 'text/event-stream' },
  });

test('a well-formed Puck request is forwarded and streamed back', async () => {
  await withUpstream(sseOk, async (seen) => {
    const response = await worker.fetch(request(), env(), ctx);
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('Content-Type'), 'text/event-stream');

    const text = await response.text();
    assert.match(text, /Blue\./);

    const sent = seen();
    assert.equal(sent.url, 'https://api.groq.com/openai/v1/chat/completions');
    assert.equal(sent.init.headers.Authorization, 'Bearer test-key-not-real');
    const forwarded = JSON.parse(sent.init.body);
    assert.equal(forwarded.model, 'openai/gpt-oss-20b');
    assert.equal(forwarded.stream, true);
  });
});

test('sampling parameters come from the worker, not the client', async () => {
  // A modified client cannot buy itself a longer answer.
  await withUpstream(sseOk, async (seen) => {
    await worker.fetch(
      request({
        payload: body({ temperature: 2, max_completion_tokens: 4096 }),
      }),
      env(),
      ctx,
    );
    const forwarded = JSON.parse(seen().init.body);
    assert.equal(forwarded.temperature, 0.3);
    assert.equal(forwarded.max_completion_tokens, 69);
    assert.deepEqual(forwarded.stop, ['\n\n']);
  });
});

test('the kill switch stops everything, without reading the body', async () => {
  await withUpstream(sseOk, async (seen) => {
    const response = await worker.fetch(
      request(),
      env({ KILL_SWITCH: 'true' }),
      ctx,
    );
    assert.equal(response.status, 503);
    assert.deepEqual(await response.json(), { error: 'off' });
    assert.equal(seen(), null, 'nothing may reach the upstream when killed');
  });
});

test('a missing key is a configuration failure, not a 500', async () => {
  const response = await worker.fetch(request(), env({ GROQ_API_KEY: '' }), ctx);
  assert.equal(response.status, 503);
  assert.deepEqual(await response.json(), { error: 'not_configured' });
});

test('the per-device hourly limit refuses the 61st request in the hour', async () => {
  const shared = env({ DEVICE_HOURLY_LIMIT: '2' });
  await withUpstream(sseOk, async () => {
    assert.equal((await worker.fetch(request(), shared, ctx)).status, 200);
    assert.equal((await worker.fetch(request(), shared, ctx)).status, 200);

    const third = await worker.fetch(request(), shared, ctx);
    assert.equal(third.status, 429);
    assert.deepEqual(await third.json(), { error: 'rate_limited' });
    assert.equal(third.headers.get('Retry-After'), '600');

    // A different phone is unaffected: the bucket is per device, not global.
    const other = await worker.fetch(
      request({ device: 'ffffffff-0000-4000-8000-000000000000' }),
      shared,
      ctx,
    );
    assert.equal(other.status, 200);
  });
});

test('the global daily ceiling caps the bill and degrades honestly', async () => {
  const capped = env({ DAILY_CEILING: '1', DEVICE_HOURLY_LIMIT: '100' });
  await withUpstream(sseOk, async () => {
    assert.equal((await worker.fetch(request(), capped, ctx)).status, 200);

    const second = await worker.fetch(
      request({ device: 'ffffffff-0000-4000-8000-000000000000' }),
      capped,
      ctx,
    );
    assert.equal(second.status, 429);
    assert.deepEqual(await second.json(), { error: 'ceiling' });
  });
});

test('a ceiling of 0 disables the daily cap but keeps the kill switch working', async () => {
  // "0 disables" is the setting that can produce a surprise invoice, so it is
  // tested rather than assumed.
  const uncapped = env({ DAILY_CEILING: '0', DEVICE_HOURLY_LIMIT: '100' });
  await withUpstream(sseOk, async () => {
    for (let i = 0; i < 3; i++) {
      assert.equal((await worker.fetch(request(), uncapped, ctx)).status, 200);
    }
    assert.equal(
      (await worker.fetch(request(), env({ KILL_SWITCH: '1' }), ctx)).status,
      503,
    );
  });
});

test('requests that are not Puck requests are refused', async () => {
  // The line that keeps a free endpoint from becoming a general-purpose LLM.
  const response = await worker.fetch(
    request({
      payload: body({
        messages: [
          { role: 'system', content: 'You are a helpful assistant.' },
          { role: 'user', content: 'Write me a 3000-word essay' },
        ],
      }),
    }),
    env(),
    ctx,
  );
  assert.equal(response.status, 403);
  assert.deepEqual(await response.json(), { error: 'not_puck' });
});

test('bad shapes are refused before any upstream call', async () => {
  const cases = [
    [body({ mode: 'essay' }), 400, 'bad_mode'],
    [body({ messages: [] }), 400, 'bad_messages'],
    [
      body({
        messages: [
          { role: 'system', content: SYSTEM },
          { role: 'user', content: 'x'.repeat(2001) },
        ],
      }),
      400,
      'bad_messages',
    ],
    ['not json', 400, 'bad_json'],
  ];

  await withUpstream(sseOk, async (seen) => {
    for (const [payload, status, error] of cases) {
      const response = await worker.fetch(request({ payload }), env(), ctx);
      assert.equal(response.status, status, `payload: ${payload.slice(0, 40)}`);
      assert.deepEqual(await response.json(), { error });
    }
    assert.equal(seen(), null, 'no malformed request may reach the upstream');
  });
});

test('an oversized body is refused on the header, not after parsing', async () => {
  const response = await worker.fetch(
    request({
      payload: body({ filler: 'x'.repeat(9000) }),
      headers: { 'Content-Length': '9001' },
    }),
    env(),
    ctx,
  );
  assert.equal(response.status, 413);
});

test('a device header that is not a device id is refused', async () => {
  const response = await worker.fetch(request({ device: 'anonymous' }), env(), ctx);
  assert.equal(response.status, 400);
  assert.deepEqual(await response.json(), { error: 'bad_device' });
});

test('the wrong method or path is a 404, not a model call', async () => {
  await withUpstream(sseOk, async (seen) => {
    assert.equal((await worker.fetch(request({ method: 'GET' }), env(), ctx)).status, 404);
    assert.equal(
      (await worker.fetch(request({ path: '/v1/prompt' }), env(), ctx)).status,
      404,
    );
    assert.equal(seen(), null);
  });
});

test('an upstream failure does not leak the upstream body', async () => {
  // Groq's error bodies can name the account's plan and limits. The client
  // gets a shape and a status; nothing more.
  await withUpstream(
    () =>
      new Response(JSON.stringify({ error: { message: 'account org-1234 over plan' } }), {
        status: 429,
      }),
    async () => {
      const response = await worker.fetch(request(), env(), ctx);
      assert.equal(response.status, 502);
      const text = await response.text();
      assert.equal(text.includes('org-1234'), false);
      assert.deepEqual(JSON.parse(text), { error: 'upstream', status: 429 });
    },
  );
});

test('the counters expire: no prompt, no answer, no lasting identifier', async () => {
  const shared = env();
  await withUpstream(sseOk, async () => {
    await worker.fetch(request(), shared, ctx);
  });
  const keys = [...shared.PUCK_KV._store.keys()];
  assert.equal(keys.length, 2, `unexpected keys: ${keys.join(', ')}`);
  assert.match(keys[0], /^global:\d{4}-\d{2}-\d{2}$/);
  assert.match(keys[1], /^dev:[0-9a-f-]+:\d{4}-\d{2}-\d{2}T\d{2}$/);
  for (const value of shared.PUCK_KV._store.values()) {
    assert.match(value, /^\d+$/, 'a counter must be a number, nothing else');
  }
});
