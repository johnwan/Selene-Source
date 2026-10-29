# Phone-to-TV Playback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Search in Android Selene, approve a phone once on Selene-TV, then play and control movies/live streams on that TV without starting phone playback.

**Architecture:** A versioned local HTTPS API extends Selene-TV's existing Ktor receiver and drives its existing video controllers. Android NSD discovers receivers; a Flutter connection service owns trust, routing, and status. Replaceable picker/controller widgets consume that service rather than implementing networking.

**Tech Stack:** Flutter/Dart, Kotlin, Android NSD, Ktor Netty 2.3.12, existing Media3/mpv TV backends; app-private trust storage, pinned local TLS, JSON contract fixtures, Flutter tests and JUnit.

**Spec:** `docs/superpowers/specs/2026-10-29-phone-tv-playback-design.md`

## Global Constraints

- Android phone plus Android TV first; other platforms retain existing playback.
- No code entry: unknown phone gets TV Allow/Decline once; remembered phones reconnect with one connection message.
- Phone source root is this repository, branch `codex/phone-tv-playback`, based on `e0874cf`; do not add commits to background-audio PR #6.
- TV source root is `.local/Selene-TV-source`, its own Git repository based on `36acbad9734b407b23f7f33835caa730387060f2`; create a separate feature branch there. The outer repo ignores `.local/` locally.
- TV Gradle/AGP/Kotlin versions remain those of TV source; do not copy phone toolchain upgrades. Read TV CLAUDE.md and any scoped instructions before editing. Approved pinned TLS overrides that document's generic accept-all-network-client advice for this new control API.
- NSD service `_selene-tv._tcp`; protocol version `1`; stable random installation IDs; pairing expiry 60 seconds; one prompt at a time; one controlling phone at a time.
- TV UI must be available; no waking TVs or background activity launch. TV owns fetching/decoding and progress writing. Phone disconnect does not stop TV or trigger local fallback.
- Existing DLNA and browser remote remain separate. Browser remote must not press trust-dialog buttons or revoke trusted phones.
- No cloud linking, credential/password sync, transcoding, phone media relay, DRM negotiation, or iOS/desktop discovery in this release.
- Preserve data and signing; no physical-TV installation requiring release-app deletion without explicit user authorization.
- Keep discovery/selection UI replaceable; state/networking must have no BuildContext/widget dependencies.

## Review Focus

1. A resolved IP/name changes or is reused: reconnect only to the stored TV identity and certificate (Tasks 2, 4).
2. A source URL needs headers, redirects, or HLS segments: carry required headers without leaking credentials to another origin (Tasks 3, 5).
3. A delayed/retried request arrives after another episode/controller selection: reject stale commands and avoid duplicate players (Tasks 1, 3, 4).
4. Phone is killed, a TV goes offline, or polling fails: TV continues; phone never starts local audio implicitly (Tasks 4, 5).
5. A hostile/accidental LAN request tries to approve itself through the old browser remote: only physical TV input can grant/revoke native trust (Task 2).

## File and interface map

Phone additions:
- `lib/tv/tv_models.dart`: typed public device, media, command, and status models.
- `lib/tv/tv_platform.dart`: abstract discovery/private storage API and Android Method/EventChannel adapter.
- `lib/tv/tv_transport.dart`: HTTPS requests, bounded JSON, certificate pinning, pairing and authenticated calls.
- `lib/tv/tv_connection_service.dart`: ChangeNotifier state machine with injected platform/transport, lifecycle and destination routing.
- `lib/tv/tv_device_picker.dart`: replaceable device/manual-address UI only.
- `lib/tv/tv_remote_player.dart`: replaceable status/control widget only.
- `android/app/src/main/kotlin/com/example/selene/TvDiscovery.kt` and `TvPrivateStore.kt`: NSD bridge and no-backup app-private identity/token storage.
- `docs/phone-tv-protocol.md`, `test/fixtures/tv_protocol/*.json`, `test/tv/*_test.dart`: shared contract and tests.

Phone modifications: existing `MainActivity.kt` (at `com/example/selene`, despite its `org.moontechlab.selene` package), `lib/main.dart`, `lib/widgets/user_menu.dart`, `lib/screens/player_screen.dart`, `lib/screens/live_player_screen.dart`, and relevant manifest/backup configuration. Do not refactor unrelated player logic.

TV additions under `app/src/main/java/org/moontechlab/selenetv/remote/`:
- `RemoteModels.kt`, `RemoteSession.kt`: JSON DTOs, validation, idempotency and ownership.
- `RemoteTrustStore.kt`, `RemoteTls.kt`: persisted trust/TLS identity, no-backup private storage.
- `RemoteDiscovery.kt`, `RemoteReceiver.kt`: NSD and HTTPS receiver lifecycle.
- `RemotePlayback.kt`: adapter into the existing real player, commands and snapshots.
- `RemoteHost.kt`, `TrustedPhonesPanel.kt`: global pairing/playback host and trust management UI.

TV modifications: `SeleneApplication.kt`, `MainActivity.kt`, `screen/AppNavHost.kt`, `screen/tab/SettingsTab.kt`, `server/RemoteControlServer.kt`, `screen/player/PlayerLaunch.kt`, `PlayerScreen.kt`, `LiveLaunch.kt`, `LivePlayerScreen.kt`, `PlayerFactory.kt`, `service/MediaHttp.kt`, and engine header plumbing where needed. Prefer extending existing playback overlays with remote-session parameters; do not introduce another decoder/player stack.

TV tests under `app/src/test/java/org/moontechlab/selenetv/remote/`; copy protocol docs/JSON fixtures to the TV repo. Build configuration changes are limited to dependencies/tests needed by this feature and debug emulator ABI support if needed.

## Shared v1 contract

All native endpoints use the separate TLS listener and `/v1` prefix. `Authorization: Bearer <token>` authenticates trusted calls. JSON errors contain `code` and safe `message`. Never log tokens or full media URLs.

- `GET /v1/info`: `{version:1,tvId,name,capabilities:[...]}`; public, no user/media data.
- `POST /v1/pair`: `{clientId,name,requestSecret}` -> `{pairId,state:"pending",expiresIn:60}`. Bounds: name 64 characters, IDs/secrets 128, one active request, burst/rate limited.
- `POST /v1/pair/result`: `{pairId,requestSecret}` -> pending/declined/expired or `{state:"allowed",token,tvId}`. Only the original secret retrieves a token; results expire, tokens are never broadcast.
- `POST /v1/connect`: authenticated, creates no playback; returns identity, owner and session snapshot, notifies TV once for a real reconnection.
- `GET /v1/status`: authenticated snapshot, no takeover or replay.
- `POST /v1/play`: `{requestId,mediaId,takeOver:false,media:{kind,title,url,headers,sourceId,videoId,episodes:[{title,url}],episodeIndex,startPositionMs,rate,liveChannelId}}`. A non-owner gets `controller_busy` until its phone explicitly retries with `takeOver:true` and a new request ID.
- `POST /v1/command`: `{requestId,sessionId,mediaId,action,positionMs?,rate?}`. Actions play/pause/stop/seek/rate; live seek omitted from capabilities. Episode/channel changes send a new media selection via `/play`.
- Snapshot: `{tvId,ownerClientId,sessionId,mediaId,requestId,state,positionMs,durationMs,rate,capabilities,error?}` with states idle/loading/playing/paused/ended/failed.

Maximum body 256 KiB, maximum 2,000 episodes, maximum 16 allowed stream headers, no negative/out-of-range positions or invalid rates (allowed 0.5–2.0). Accept HTTP(S) only; reject file/content/loopback and disallowed headers. Identical request IDs with identical payload return original acceptance; mismatched reuse fails. Keep a bounded 128-entry request cache and reject stale session/media/owner commands. Pair/control requests dispatch through main-thread adapters; player state acknowledges actual playback independently of HTTP acceptance.

### Task 1: Contract and pure session state

**Files:** protocol doc/fixtures in both repos; phone `tv_models.dart`; TV `RemoteModels.kt`, `RemoteSession.kt`; `test/tv/tv_models_test.dart`, TV `RemoteSessionTest.kt`.

**Interfaces:** Kotlin `RemoteSession.acceptPlay(clientId: String, request: PlayRequest): Acceptance`, `acceptCommand(clientId: String, request: CommandRequest): Acceptance`, `snapshot(): RemoteStatus`; Dart immutable `TvDevice`, `TvMedia`, `TvStatus`, `TvCommand`, `TvConnectionState` with JSON serializers. Milliseconds are integer fields; IDs are opaque strings.

- [ ] Write fixture assertions: Dart/Kotlin decode the same movie/live/status JSON; version is exactly 1; movie starts at 42,000 ms; live has no seek capability; URL/position/rate limits reject invalid inputs.
- [x] Write session assertions: repeated request `r1` opens once; reuse with altered media fails; second client cannot control without takeover; a command for replaced `mediaId` fails; 129 requests leave at most 128 cached entries.
- [x] Run focused Flutter/JUnit tests and record expected failures before implementation.
- [x] Implement DTOs, validation, and thread-safe pure session acceptance. State is not marked playing until the player reports it. Publish protocol docs and fixtures to both repos.
- [x] Rerun focused tests; require all assertions passing and no mismatch between fixture schemas.
- [x] Commit the contract independently in both repositories.

### Task 2: TV trust, TLS, discovery, and first-time approval

**Files:** TV `RemoteTrustStore.kt`, `RemoteTls.kt`, `RemoteDiscovery.kt`, `RemoteReceiver.kt`, `RemoteHost.kt`, `TrustedPhonesPanel.kt`; receiver/application/activity/global-overlay/settings/backup integration; TV `RemoteTrustTest.kt`, `RemoteReceiverTest.kt`.

**Interfaces:** `RemoteReceiver.start(context)`, `stop()`, `setUiAvailable(Boolean)`; StateFlow of pending pairing request; `approve(pairId)`, `decline(pairId)`, `revoke(clientId)`; `RemoteTrustStore.authenticate(token): TrustedPhone?`; `RemoteDiscovery.register(tvId,name,port)` / `close()`. Pairing clock and secure randomness are injectable for tests.

- [ ] Write tests proving decline/dismiss/60-second expiry creates no trust, only matching requestSecret retrieves approval, approved tokens persist across store reopen, revoked tokens immediately fail, and renamed phones do not gain trust by ID/name alone.
- [ ] Write tests for one pending request, pair flood rejection, oversized JSON rejection before parsing, unauthorized control/status, TLS identity persistence and changed-identity handling. Add browser-key/text guard assertions while trust or revocation UI is open.
- [ ] Run tests to demonstrate failures before implementing receiver behavior.
- [x] Implement TLS with a persisted self-signed RSA >=2048/SHA-256 identity, app-private no-backup keystore/credentials, and the existing Ktor Netty engine on a separate HTTPS listener. Verify the chosen certificate-generation utility/dependency against official APIs; do not use the TV's existing accept-all HTTP client for native control.
- [x] Implement versioned routes and Android NSD using actual bound port. Register only after listening succeeds; drop pending requests when TV UI is unavailable. Keep trust state out of media/account settings backups.
- [x] Add the global physical-remote-operated Allow/Decline dialog and trusted-phone revocation UI using existing TV focus/theme conventions. Disable old browser remote key/text injection throughout these dialogs. Show one reconnection toast per connect lifecycle, not each poll.
- [ ] Run tests plus TV debug compilation; verify receiver closes callbacks/advertisement cleanly and no Activity is retained.
- [x] Commit TV receiver/trust slice.

### Task 3: TV playback adapter and status through existing players

**Files:** TV `RemotePlayback.kt`, `RemoteHost.kt`; existing player launch/screen/factory/media HTTP and relevant mpv header handling; TV `RemotePlaybackTest.kt`, `RemoteMediaHeadersTest.kt`.

**Interfaces:** `RemotePlayback.start(request, sessionId)`, `command(request)`, `snapshot(): RemoteStatus`, `close()`; main-thread adapter backed by existing `VideoPlayer`, current TV overlays, and TV progress reporter. New optional remote launch parameters default to standalone behavior.

- [ ] Write fake-player assertions: media starts once at requested position/rate, explicit pause/play are idempotent, Stop releases the session, replacing media disposes the old player, stale callbacks cannot replace newer status, and absent UI returns `tv_not_ready`.
- [ ] Write media-header tests: required UA/Referer survive HLS segment loading, credentials remain origin-scoped across redirects, rejected schemes/phone-loopback do not load; live seek is refused and live channel replacement works.
- [x] Run focused tests and confirm red results.
- [x] Connect accepted requests to the existing on-demand/live playback overlays and PlayerFactory, retaining decoder settings. Supply resolved URLs/headers through per-session data sources. Do not create a second engine or rely on identical backend/subscription configuration.
- [x] Export snapshots from actual player state; report loading/failed distinctly. Keep local TV controls/status synchronized, route physical Back through existing behavior, and report stopped when TV user exits. TV remains sole progress writer; no phone-side writeback.
- [ ] Rerun tests and build the real TV app. Test stop, navigation exit, player disposal and one-owner takeover with fake and device playback.
- [x] Commit TV playback slice.

### Task 4: Phone connection service, native discovery/storage, and transport

**Files:** phone `tv_platform.dart`, `tv_transport.dart`, `tv_connection_service.dart`, native `TvDiscovery.kt`, `TvPrivateStore.kt`, existing MainActivity/main wiring; `test/tv/tv_connection_service_test.dart`, `tv_transport_test.dart`.

**Interfaces:** `TvPlatform.devices: Stream<List<TvDevice>>`, `startDiscovery()`, `stopDiscovery()`, `readCredentials()/writeCredentials()/forget(tvId)`; `TvTransport.info/pair/pairResult/connect/status/play/command`; `TvConnectionService.select(device)`, `selectLocal()`, `retry()`, `forget(tvId)`, `startMedia(media,{takeOver=false})`, `send(command)`, `setForeground(bool)`. Service exposes devices/destination/status/error via ChangeNotifier and has injected clock/transport/platform for tests; no UI or BuildContext.

- [x] Write service assertions: first selection enters pending; allowed stores token/pin; later reconnect does not pair; decline does not store trust; selecting This phone clears routing; discovering another TV never selects it; reconnect never calls Play.
- [ ] Write tests for same-ID changed IP, different-ID reused address, certificate mismatch, auth revocation, incompatible version, network change during pairing, late polling after destination switch, background stop of polling/discovery, and foreground recovery without playback replay.
- [ ] Write HTTPS tests with a local test server verifying mismatched certificates are rejected, pairing uses only a scoped initial trust-on-first-use client, tokens never go to arbitrary hosts/redirects, safe errors omit credentials, and body/time limits apply.
- [x] Run tests and confirm missing implementation fails.
- [x] Implement Android NSD EventChannel and app-private no-backup credential bridge, lifecycle-aware service, and pinned Dio/HttpClient transport. Use bounded timeouts and no automatic mutation retries without request IDs. Check actual target SDK and apply LAN runtime permission only where required by SDK 37+.
- [x] Wire service lifecycle at the app root, preserving non-Android behavior. Do not enable discovery outside foreground use or request unrelated location permissions for NSD.
- [x] Rerun focused Flutter tests and analysis, compile Android bridge; commit.

### Task 5: Replaceable picker/controller and phone playback routing

**Files:** phone `tv_device_picker.dart`, `tv_remote_player.dart`, user-menu entry point; existing player and live-player screens; `test/tv/tv_routing_test.dart`, `tv_device_picker_test.dart`, `tv_remote_player_test.dart`.

**Interfaces:** `showTvDevicePicker(context, service)` and `TvRemotePlayer(service, onPlayHere, onSelectEpisode/channel)`. Screens consult `service.remoteSelected` before constructing a decoder, turn resolved source/channel into TvMedia, and keep their existing metadata/source/episode browsing. Widget callbacks call service methods only.

- [ ] Write widget tests for This phone/device list, pending approval text, denied/offline/update-required errors, and manual address fallback. Verify choosing a device invokes selection without containing HTTP/NSD logic in the widget.
- [ ] Write routing tests: remote movie and live requests never instantiate VideoPlayerWidget, never publish a local audio-service item, and never write phone progress; starting after a TV disconnect stays remote/error until explicit Play here.
- [ ] Write handoff tests: pause current local media, send current position, dispose only after TV reports playing; failure leaves local paused. Reverse handoff uses last position, requires acknowledged TV stop, and fails visibly if unreachable.
- [x] Run focused tests to establish red behavior.
- [x] Add a modest Android-only TV destination entry in the existing menu and a controller panel in existing player space. Reuse the service in both on-demand and live screens; pass live UA, source/episode selection, and appropriate resume position. Maintain existing DLNA behavior and standalone playback paths.
- [x] Ensure source changes/rapid episode taps use generation/request IDs; ignore stale acknowledgements and status; controller takeover is an explicit phone action. On app background/disposal, stop only phone polling, not TV media.
- [x] Rerun tests plus existing suite and focused analysis; commit.

### Task 6: Integration, real builds, device evidence, and delivery

**Files:** protocol/build notes in both repos; device QA entry/fixtures where needed; screenshots/test evidence without account data. No version/signing changes unless necessary and specifically documented.

- [x] Run full phone `flutter test --no-pub`, focused `flutter analyze --no-pub`, and ARM64 debug build. Run TV `gradlew.bat testDebugUnitTest`, debug build and focused lint; fix any failures introduced by this feature.
- [ ] Use an Android TV emulator for repeatable first-approval/decline, reconnection, revocation, movie/live and failure tests. Use an Android test sender or phone emulator when no physical phone is connected. Configure debug x86_64 APK support only if the existing TV ABI split prevents emulator installation.
- [ ] Test real app-to-app TLS and NSD where network permits; emulator forwarded-port tests alone do not count as NSD evidence. Report physical-TV or LAN-router cases as pending until available.
- [ ] Verify phone screen-off/kill, TV physical controls/Back, stream failure, IP/network change, two clients/takeover and delayed commands; confirm TV playback survives disconnect and reconnect does not replay.
- [x] Review both final diffs, shared fixtures and credential/log handling. Commit fixes, rerun only affected checks, and document limitations accurately.
- [x] Build normal APKs preserving application IDs/signing; install to already-authorized phone when reachable. Obtain explicit approval before any TV replacement requiring data loss.
- [ ] Deliver both repository branches/commit IDs and build locations. If creating PRs, keep them separate from PR #6, cross-link matching protocol versions, attach each created PR to this chat, and do not merge without user instruction.

## Execution status (2026-10-29)

Tasks 1–5 are implemented and committed in both feature branches. Automated
checks pass, normal APKs are built, and the phone update is installed. Some
original checklist items combine several device/provider scenarios; those remain
unchecked where the entire matrix was not exercised. See
[validation evidence and pending manual checks](../../phone-tv-validation.md).
Physical TV access remains unavailable because ADB authorization is pending.
No integration or merge has been performed.

## Plan self-review

Every spec section maps to the contract (Task 1), trust/discovery (Task 2/4), TV
playback/history (Task 3), phone routing/UI (Task 5), or integration/delivery
(Task 6). Review Focus cases are each named in the owning tasks' test steps.
DTO names and service methods above are the shared vocabulary. The plan leaves
internal dependency/API choices to verification during implementation, with the
approved protocol and user behavior fixed. No UI layout is part of the protocol.
