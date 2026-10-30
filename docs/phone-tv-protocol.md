# Selene local control v1

Transport: pinned HTTPS, discovered as `_selene-tv._tcp`. Initial approval is
physical TV Allow/Decline, then a private bearer token reconnects without prompts.
Discovery TXT: `id`, `name`, `version=1`; never credentials. A changed TLS identity
requires forgetting and explicitly pairing again.

Phone startup always selects local playback. Saved trust allows prompt-free
connections only after the user explicitly selects a TV in that app session;
discovery alone never restores the previous destination. The player's Cast menu
prioritizes the native Selene TV option above generic DLNA devices. Selecting it
during local movie playback hands off the current episode and position.

All requests are JSON, maximum 256 KiB. Public `/v1/info` returns
`version,tvId,name,capabilities`. `/v1/pair` takes `clientId,name,requestSecret`,
returns `pairId,state,expiresIn=60`. `/v1/pair/result` takes `pairId,requestSecret`;
only its originating secret can obtain an approved `token,tvId`. Before requesting,
the phone persists a separate recovery secret and certificate pin for that TV.
The TV stores its hash with the trusted phone. Repeating `/v1/pair` with the same
client ID and secret returns `state=allowed,token,tvId`, including after restart,
so an interrupted first approval does not require another dialog. A client ID or
display name alone never restores trust; revocation deletes this recovery grant.

Receivers that support movie cover metadata advertise `coverMetadata` in
`/v1/info.capabilities`. Only for those receivers, the phone can add optional
`coverUrl` to a movie descriptor. It omits this field for older v1 receivers,
which reject unknown JSON fields. A missing or invalid cover never blocks
playback; the TV preserves the existing watch-record cover if it cannot replace
it with a valid image URL.

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
Snapshots include `episodeIndex` (zero-based) and `title`. Changing episodes with
the TV remote changes `mediaId`; commands for the old episode are rejected.
“Play here” first obtains an acknowledged Stop, then resumes that episode and
position locally. Status polls that predate a newer media selection are ignored.
Authorization is checked again after reading a control body, at dispatch, so a
revoked phone cannot finish an already-open slow request.
Stopping phone polling or disconnecting does not stop TV media. TV is the sole
history/progress writer. See `test/fixtures/tv_protocol` (TV `src/test/resources`)
for identical Dart/Kotlin JSON examples. UI selection is not part of this API.
