# Phase 2 — One private connection

Requires accepted [Phase 1](phase-1.md). Implement the connection state, a local Keychain adapter and the bounded provider stream. Leave the product shortcuts for Phase 4. Seed tests from the measured wire shapes at `.local/assess-explain/cloud/matrix.py:35` and `:54`. Reconcile each fixture against current primary API documentation and the exact qualified model. The assessment probe used a permissive parser and retries.

## Work

- Put eligibility, immutable request context, wire-event decoding and typed failures in independently testable code. Use Security.framework for one app-owned generic-password item with a fixed service/account. Keep the provider tag, key and revision together in a secure item, with device-only unlocked access and synchronization disabled. Replace the record atomically after local validation of the nonempty key and the selected, eligible provider. Keep the saved credential out of display models, defaults, command lines, environment and installer. Mask editing, clear the edit buffer on save/cancel/dismiss, and load the key only when needed. Saving locally makes it available for the first deliberate Explain. Say “Key saved” until a real request succeeds.
- Serialize save/replace/disconnect with dispatch. Invalidate the old generation and cancel in-flight work before returning success to the panel. Disable dispatch and durably record a nonsecret pending-removal marker before attempting Keychain deletion. If recording that intent fails, surface a failed disconnect immediately. Resume pending removal at launch before enabling dispatch. On delete failure keep the marker, offer Unlock/Retry, and clear it only after verified absence. “Not found” already satisfies delete. Never restore a removed key from defaults. For interrupted replacement, reconcile the single durable item at launch. Require eligibility recheck for the new account/key.
- Send exactly one foreground HTTPS POST per eligible user gesture using a memory-only session with no disk cache, cookies, stored credentials, background tasks or redirect following. Configure a fixed endpoint per qualified adapter. Exclude arbitrary hosts, tools, attachments, screen images, app/bundle IDs, history and request chaining. No connection on launch, save, eligibility check, help-link display or status refresh. Help opens official docs in the default browser only on an explicit click.
- OpenAI uses `api.openai.com/v1/responses`, a Bearer header, `store: false`, streaming and the qualified reasoning setting. Anthropic, if qualified, uses `api.anthropic.com/v1/messages`, the version header, `x-api-key`, one user message and the qualified output/thinking settings. Set explicit connect/idle/total deadlines and bounded event/output bytes, using synthetic 3,000-word cases to prove headroom. Start with 15 seconds to first data, 15 seconds idle, 90 seconds total, 256 KiB per SSE event and 1 MiB of text output. Map overruns to an incomplete result. Never silently retry a chargeable request.
- Decode incremental UTF-8 and SSE frames, including CRLF, split code points, multiline data and heartbeat/comment lines. Accept only output text deltas. Ignore documented non-text metadata. Reject malformed frames and unsupported content that prevents confirming a complete explanation. OpenAI completion needs a completed response with valid text and no refusal/error/incomplete status. Anthropic needs a natural end-turn reason and final message stop. A socket close, length ceiling, refusal or error after HTTP 200 cannot complete an answer. Consumer cancellation must close the task promptly.

```
@ dispatch(context, capturedText) -> providerEvents
ctx: qualified configuration, credential store, fixed HTTPS transport
pre: deliberate Explain and current eligible connection generation
do:
  1. validate current request, credential binding and source limits
  2. emit one request to the configured host
  3. parse bounded events until natural completion or failure
br: explicit cancellation -> close transport and invalidate delivery
fail: redirect, timeout, refusal or premature end -> typed failure
```

## Acceptance

**Automated.** Use a recording transport and disposable, uniquely named test Keychain items on an authorized local machine. Assert the complete request by provider, exact destination, request count, no secret in body, redirection to same/different host yields zero follow-ups, and no provider-switch retry. Test invalid key, billing/quota, 429, server errors, refusal, malformed and incomplete streams, split UTF-8 and cancellation at each await. Exercise relaunch, locked store, delete failure/retry, crashes just before and after Keychain mutation and marker clearance, replace failure, stale callbacks, key/provider changes and successful disconnect. Demonstrate a fresh request after each recoverable condition and no use of the old credential. Local deterministic tests use synthetic keys. An authorized synthetic contract probe against each supported provider corroborates wire fixtures. Live calls stay out of ordinary verification.

**Manual.** On the signed candidate in Phase 5, verify Keychain unlock/deny behavior and non-developer setup. Phase 2 admits the adapter on deterministic evidence and records any native verification still due. Compare copy to current model-specific retention and billing information before exposing it.

**Work units.** Given the Phase 1 configuration and agreed event interface, the Keychain adapter and wire decoder/transport are [batch-eligible] in separate files with separate tests. The integration owner owns dispatch, local verification entries, redaction checks and the combined race tests.
