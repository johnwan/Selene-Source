# Phone-controlled Selene-TV playback

Status: design for user review; product implementation has not started.

## Intent and agreed behavior

Searching with a TV remote is inconvenient. Users should search and browse in
the Android Selene phone app, select a video or live channel, and have Selene-TV
play it directly. The phone becomes the controller, and the TV downloads and
decodes the media. Locking or disconnecting the phone must not stop the TV.

The user chose direct integration between the Selene apps rather than generic
DLNA. Discovery uses the local network. A previously unknown phone triggers an
Allow/Decline dialog on the TV, operated with the TV remote. No code entry or QR
scan is needed. Allow persists trust; later connections reconnect without a
confirmation dialog and show only a brief connection message. TV settings can
remove trusted phones. Reinstalling/resetting either app can require approval
again. Updates preserving app data must preserve trust.

## Scope and implementation choices

This is a coordinated feature across two codebases, not a change to just the
phone player. The following defaults are the designer's calls, not additional
requirements supplied by the user:

- First release: Android phone plus Android TV. Other phone/desktop platforms
  keep existing behavior; cross-platform discovery can follow later.
- Discover TVs automatically while the phone app is foregrounded. Connect only
  after the user selects a TV the first time, then reconnect to the last selected
  trusted TV when it is reachable. Never choose an arbitrary new TV.
- TV app must be running and its UI available for initial approval and remote
  playback. Waking a powered-off TV or opening Selene-TV over other apps is out
  of scope. Wired TVs on the same reachable LAN are also supported.
- A visible destination selector offers This phone and discovered TVs. Connected
  playback shows the TV name. Choosing This phone disconnects remote routing;
  it does not automatically start another copy of the media.
- Losing the connection leaves TV playback running. The phone shows disconnected
  and offers Retry or Play on this phone; it never silently starts local audio.
- A remembered connection is not a queued playback instruction. Reconnecting
  must not replace, resume, or restart whatever is on the TV.
- One TV playback session and one controlling phone at a time. Another trusted
  phone can connect for status, but taking control requires a deliberate action
  on that phone. Trust approval on the TV is not repeated for that takeover.

## Approaches

1. **Direct Selene connection (selected).** Extend the TV's existing local Ktor
   server with device discovery, trust, playback commands, and player status.
   Uses the TV's real player and supports movies, episode changes, and live TV.
   Both apps must be updated.
2. **Extend DLNA (not selected).** The phone already has a DLNA sender for
   on-demand playback. This offers wider receiver compatibility, but depends on
   each receiver's media/header support and does not give Selene-TV-specific
   trust, navigation, or consistent status/control behavior.
3. Cloud-mediated linking was considered unnecessary: the requested use is local,
   and it would require an additional server, account assumptions, and lifecycle
   management. Neither backend account changes nor a new cloud service are needed.

## Current code and repository boundaries

Phone repository: `MoonTechLab/Selene-Source`, local checkout at
`C:/Users/jiaol/AndroidStudioProjects/Selene`, currently based on `e0874cf`.
Existing background-audio PR #6 must remain independent; branch new phone work
from the tested source and keep its new commits out of that PR.

- `lib/screens/player_screen.dart` resolves on-demand media and owns the local
  and DLNA playback branches, episode/source selection, and progress reporting.
- `lib/screens/live_player_screen.dart` has a separate live playback path and
  must receive the same destination routing behavior.
- `lib/widgets/video_player_widget.dart` owns the actual phone player and the
  background-audio session. TV routing must avoid starting that player.
- Existing DLNA widgets and selection continue to function independently.

TV source repository: `MoonTechLab/Selene-TV-source`, branch `master`, inspected
at `36acbad9734b407b23f7f33835caa730387060f2`. `MoonTechLab/Selene-TV` is its
distribution/documentation repository.

- `server/RemoteControlServer.kt` currently exposes `/api/ping`, `/api/key`, and
  `/api/text` plus the browser remote. It has no play-media endpoint or trust
  protocol. Its selected port is not guaranteed to be constant.
- `SeleneApplication.kt` starts that server; `MainActivity.kt` attaches UI input
  callbacks. New network callbacks must not retain a destroyed Activity.
- `screen/AppNavHost.kt` provides a global overlay/toast host suitable for trust
  prompts and connection messages.
- `HomeScreen.kt`, detail/player overlays, `PlayerLaunch`, and `LiveLaunch` own
  existing TV navigation and playback. Extend these real entry points instead of
  creating a second playback engine. Some old PlayerLaunch comments describe a
  placeholder player and must not be taken as current runtime behavior.

## Local discovery and lifecycle

Use Android NSD/DNS-SD with a dedicated `_selene-tv._tcp` service. The TV advertises
the actual control endpoint port, stable random installation ID, display name,
protocol version, and supported capabilities. Do not advertise tokens or media.
Use Kotlin NSD on both Android sides, bridging discovery events into Flutter via
a small platform interface rather than scanning IP addresses or port ranges.

Stable identity is independent of IP address or service display name. Resolve
addresses again after Wi-Fi changes, support IPv4/IPv6, deduplicate by TV ID,
and remove unavailable devices promptly. Register only when the receiver is
ready, and unregister on deliberate shutdown. Disable control when TV UI is not
available; report a retryable error rather than accepting playback silently.

The phone stops discovery/status polling when backgrounded and reconnects on
return. It does not need a foreground service for remote control. Requests are
cancelled on disposal or network changes. TV playback proceeds independently.

Handle network permission denial explicitly without repeated dialogs. Respect
the apps' actual target SDK: current SDK 36 targets use INTERNET permission for
LAN access; do not add/request ACCESS_LOCAL_NETWORK unless targeting SDK 37+.
If a later toolchain raises the target, implement that runtime permission and
test both grant and denial before enabling discovery. Router client isolation or
blocked multicast can prevent discovery; expose Retry and an optional manual
address fallback, retaining the same trust flow.

References checked during design:
- https://developer.android.com/develop/connectivity/wifi/use-nsd
- https://developer.android.com/privacy-and-security/local-network-permission

## Trust and connection protocol

Add a versioned native-app control API, distinct from the existing browser
remote. Use a TLS endpoint with a persisted installation certificate/key, pinned
by the phone after first approval; do not use an app-wide accept-all trust
manager. Trust-on-first-use is a home-LAN model, not verified identity against
an actively impersonating network. A changed TV certificate/identity requires
explicit re-approval rather than silently replacing an existing pin.

Each phone installation has a random client ID and friendly name. Identity is
proved by an unpredictable credential, not by a name or ID alone. Store private
credentials in app-private protected storage excluded from backup/device
transfer; do not use an Android advertising/hardware identifier.

Suggested v1 lifecycle (exact DTO names are left to the builder):

1. Public `info` returns version, TV ID/name, and capabilities, no user/media
   information. The phone validates compatibility before asking to connect.
2. An unknown phone explicitly starts a pairing request containing its ID/name
   over a newly established TLS connection. The request is bound to a random
   phone-generated request secret and expires after 60 seconds.
3. TV displays one Allow/Decline dialog. It sanitizes and bounds the name, allows
   a single pending prompt, rate-limits requests, and treats dismissal/timeout as
   decline. Network input must not be able to press Allow through the pre-existing
   `/api/key` or `/api/text` browser endpoints; gate those endpoints while a trust
   or trust-management dialog is present.
4. On Allow, TV persists the trusted phone and issues a random per-phone token.
   Only the originating pairing request can retrieve it over TLS. Decline never
   creates a trusted entry or returns a usable token.
5. Reconnect authenticates with that token and pinned TV identity. Successful
   foreground reconnection shows one short TV message, not one per heartbeat.
   Do not open another approval dialog for an already trusted phone.
6. TV settings list trusted names and allow individual/all revocation. Revocation
   immediately invalidates tokens and outstanding commands/status access. Phone
   Forget TV clears its local token/pin and destination. Re-pair requires an
   explicit new connection attempt.

All new playback/control/status endpoints require authorization. Reject unknown,
expired, or revoked tokens; validate content type and payload size. Never log
tokens, credential headers, or complete signed media URLs. Discovery, connect,
and pair must not send account passwords or silently alter TV login settings.

## Playback routing and command behavior

Keep searching, details, speed tests, and source resolution on the phone. Before
opening any local player, consult the selected destination. When a TV is selected,
send the resolved media plus a bounded typed playback descriptor to the TV:

- Common: request ID, media/session ID, kind, title, selected stream URL, cover
  metadata, playback rate, and necessary stream request headers.
- On-demand: source/video identifiers, selected episode/index, available episode
  URLs/titles for that source, and requested start position. Resume uses the
  phone-selected position rather than silently overriding it with TV history.
- Live: current channel/source metadata and selected channel stream/header data.
  Live seek is disabled unless the receiver explicitly reports support.

The TV uses the received descriptor without needing identical subscription or
backend configuration. Map it into the current TV playback controllers/overlays;
add a small remote-session adapter where current launch models do not carry
resolved URLs or headers. Preserve the existing standalone TV playback behavior.
Receiving a command dispatches onto the main thread and waits for the active
player to acknowledge it. A successful HTTP response alone is not proof of
playback: publish loading/playing/failed state tied to the same request/session.

The TV fetches HTTP(S) media itself. Allow media-specific User-Agent, Referer,
Origin, Cookie, and Authorization only when actually required by that stream;
scope sensitive headers to the intended origin across redirects and segment
requests. Do not forward the user's generic backend login session or passwords.
Reject local file/content URLs and phone-loopback/proxy-only addresses; report
that the stream is unavailable to the TV rather than starting local playback.
Phone-hosted relaying/transcoding and DRM license negotiation are out of scope.

Pause/Play/Seek/Stop, episode selection, and live channel changes operate on the
existing active TV session. Include request IDs and target media/session IDs:
retries must not open duplicate players, and stale commands must not affect a
replacement session. Serialize playback replacements; latest accepted user
selection wins. Return defined errors for unsupported commands, absent player,
unreachable media, expired authorization, and TV not ready.

If another trusted phone takes control, old control requests fail as no longer
owner, its UI updates, and it must deliberately take control again. No automatic
takeover or TV approval prompt occurs during routine reconnection. A new Play
from a non-owner asks for takeover on that phone before replacing TV content.

## Status, progress, and phone presentation

Use authenticated status polling while the phone controller is visible (about
one update/second), including controller ownership, session/media/request IDs,
player state, position/duration, rate, supported commands, and a safe error.
Start with REST polling instead of adding a persistent socket protocol.

The phone controller shows the active TV, media title, loading/error state,
Play/Pause, Stop, on-demand seek and episode controls, and live channel selection.
TV playback stays on TV if the phone app is backgrounded, killed, or its screen
locks. Phone hardware media controls/background-audio notification must not claim
a separate local playback session for remotely playing media.

TV is the sole progress/history writer for remote sessions, using its existing
configured repository. Phone polling may update displayed progress but must not
write competing records. Account-wide history merging between separately
configured phone and TV accounts is outside this release.

Switching an already-playing phone video to TV includes the current position.
Keep the local player paused until TV acknowledges playing; on success dispose
it and release its audio service. On failure leave it paused and offer Retry or
Play here. Starting new remote media should never create a phone decoder first.
Switching from TV to phone requires an explicit Play here action, uses the last
known position, and stops the TV only after that action is acknowledged; surface
failures so both devices do not silently play at once.

## Compatibility and delivery

The phone detects receiver capabilities. Older Selene-TV builds without the new
API show Update Selene-TV to connect, rather than being treated as paired. Old
phones and standalone TV remote use should remain functional. The existing
browser remote is not migrated into the new trusted native protocol in this
release, but cannot approve or revoke native trust via synthetic remote input.

Use separate feature branches and separate PRs for phone and TV source, with
matching protocol documentation/fixtures in both. Keep the prior Android
background-audio PR independent. Refresh repository-specific instructions and
toolchain baselines when checking out TV source; do not assume the phone's
Gradle upgrades belong in the TV repository. Normal signed upgrades preserve app
data; do not replace installed TV release signing or delete its data without
explicit user permission.

## Validation and completion criteria

Automated tests must cover discovery updates/cleanup, trust persistence and
revocation, decline/timeout, token and certificate mismatch, version mismatch,
invalid/oversized descriptors, idempotent starts, stale commands, control takeover,
phone routing before decoder creation, media header propagation, live controls,
and progress-write ownership. Shared JSON fixtures verify Dart/Kotlin agreement.

Run the existing phone suite and focused analysis; run TV unit tests and relevant
Android build checks. Build both actual apps, not only a demo entry point.

Exercise phone + TV/emulator end-to-end: first approval and decline; restart both
apps and reconnect without a dialog; network/IP change; movie and live playback;
seek/pause/episode/channel changes; phone screen off and killed; TV Back/exit;
revocation; failed playback; disconnect/reconnect without replay; and two phones
competing deliberately. Verify the phone stays silent and the TV keeps playing
when connection is lost. Capture first-approval, phone controller, and TV playback
evidence with test media/accounts. Physical-TV validation must be stated as
pending until a reachable test TV is available; emulator results do not imply
all TV hardware/routers were tested.

## Left to the builder

Choose internal class names, platform channel plumbing, storage library, TLS
certificate generation mechanism compatible with the TV's actual minimum API,
and layout details consistent with each app. Confirm these dependency choices
against current official documentation while planning. Pin one protocol version
and fixture set before parallel implementation; implement the TV receiver and
phone sender as coordinated slices with an end-to-end smoke path early.
