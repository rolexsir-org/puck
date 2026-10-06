# The shared answer service

A Cloudflare Worker that holds one Groq key so no phone has to. It is the only
thing in this repository that can spend money, and **it is not deployed**, and
the app does not know its URL unless someone compiles one in. See
`FINDINGS.md` §4.1 for the decision this file is waiting on.

## What it is for

Puck's first principle is no setup: a useful app within one second of first
launch. Open-ended questions are the one thing that cannot be answered on the
device, and the alternative to this Worker is asking every new user to find,
paste and pay for an API key. One key behind one proxy is what makes "ask
anything" work on a fresh install, and it is the only design in which the key
never lives on a phone.

## What it refuses to do

* It does not accept a general prompt. The system turn must contain Puck's
  preamble (`PROMPT_MARKER`), the shape must be `{mode, messages[2]}` with the
  roles in order, and the body is capped at 8 KB. Without that, the endpoint is
  a free LLM for anyone who finds the URL.
* It does not trust the client with sampling parameters. Temperature, the
  token cap and the stop sequences are set in `MODES`, mirroring
  `lib/src/data/llm/prompt.dart`. A modified app cannot ask for a 4096-token
  essay on the owner's bill.
* It does not keep data. Counters live in KV with a TTL (one hour per device,
  two days global); the logs carry no prompt, no answer and no device id.
* It does not need to know who anyone is. `X-Puck-Device` is a random UUID
  generated on the phone, resettable from the privacy screen; the Worker uses
  it as a rate-limit bucket key and nothing else. There is no way to ask this
  service "how many requests did *that* person make", because there is no
  "that person" here.

## Cost, and what happens at the ceiling

Groq's `openai/gpt-oss-20b` is cheap per request, but "cheap" times an unknown
number of strangers is still an unknown number. So:

* `DEVICE_HOURLY_LIMIT` (default 60) bounds one phone with a habit. The app
  makes at most one polish per 20 seconds and skips polish entirely for short
  lines (see `IntentRouter`), so a normal person uses a fraction of this.
* `DAILY_CEILING` (default 20000) bounds the bill absolutely. When it is
  reached, the service returns 429 and the app shows its offline line: the
  gestures keep working, the answers that must be correct still are, and nobody
  sees an error dialog in the middle of a question.
* `KILL_SWITCH` turns everything off with one `wrangler deploy`, without a code
  change and without waiting for a store review.

**The 50/90/100% response is the owner's call**, and the recommendation is:
at 50% raise `DEVICE_HOURLY_LIMIT` only if the traffic is human; at 90% lower
`DAILY_CEILING` rather than raising it, because that is the only number that
cannot surprise anyone; at 100% flip `KILL_SWITCH` and post the offline line
as the expected behaviour. What must not happen at 100% is a paywall in the
middle of a question after the user has already typed it.

## Deploying it (when that decision is made)

```bash
cd worker
npx wrangler kv namespace create PUCK_KV   # paste the id into wrangler.toml
npx wrangler secret put GROQ_API_KEY       # never a variable, never in the repo
npx wrangler deploy                        # prints the URL
cd ..
flutter build apk --dart-define=PUCK_PROXY_URL=https://<the-url-it-printed>
```

Then update the privacy screen's wording if the hostname changes anything a
user would want to know, and add the host to the store's Data Safety answers
(next to Open-Meteo and Groq).

## What has not been done

**This Worker has never been deployed or executed** -- no Cloudflare account
here, and deploying someone else's service with their key is not a thing an
agent should do unasked. It is a reference implementation, reviewed by reading,
not by running. Expect the first `wrangler dev` session to shake out
configuration details; the request handling itself follows the Workers
`fetch` signature and uses only `KVNamespace` and `fetch`, both of which are
documented as used here.
