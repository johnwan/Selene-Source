# Selene local control v1

Transport: pinned HTTPS, discovered as `_selene-tv._tcp`. Initial approval is
physical TV Allow/Decline, then a private bearer token reconnects without prompts.
Discovery TXT: `id`, `name`, `version=1`; never credentials. A changed TLS identity
requires forgetting and explicitly pairing again.

All requests are JSON, maximum 256 KiB. Public `/v1/info` returns
`version,tvId,name,capabilities`. `/v1/pair` takes `clientId,name,requestSecret`,
returns `pairId,state,expiresIn=60`. `/v1/pair/result` takes `pairId,requestSecret`;
only its originating secret can obtain an approved `token,tvId`.

Authenticated endpoints use `Authorization: Bearer <token>`:
- `POST /v1/connect`: status only; never starts/replays media.
- `GET /v1/status`: current player snapshot.
- `POST /v1/play`: `requestId,mediaId,takeOver,media`; see shared fixture.
- `POST /v1/command`: `requestId,sessionId,mediaId,action,positionMs?,rate?`.

Errors are `{code,message}`. One current owner; explicit `takeOver` allows a
trusted phone to take control. Stale session/media/owner commands fail. Duplicate
requests with the same payload are idempotent; changed reuse fails. Cache bound
128 requests. Millisecond positions are nonnegative safe integers. Rates .5–2.
Live media does not advertise seek. Media is bounded to 2000 episodes and 16
allowed origin-scoped HTTP headers. Only reachable HTTP(S) media is supported;
file/content/loopback URLs are rejected. Phones never send backend passwords.

TV reports idle/loading/playing/paused/ended/failed using actual player state.
Stopping phone polling or disconnecting does not stop TV media. TV is the sole
history/progress writer. See `test/fixtures/tv_protocol` (TV `src/test/resources`)
for identical Dart/Kotlin JSON examples. UI selection is not part of this API.
