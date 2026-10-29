# Phone-to-TV playback: build and validation

Both repositories use branch `codex/phone-tv-playback`. The phone branch is based
on `e0874cf`; the TV branch is based on `36acbad`. Background-audio PR #6 is
unchanged. Install matching phone and TV builds; this protocol is version 1.

## Using the feature

Open Selene-TV and keep it in the foreground. On Android Selene, open the user
menu and choose **播放到电视**, then select the TV. The TV remote must approve
the first connection with **允许**; subsequent connections reuse stored trust.
Search and select a movie, episode or live channel normally. Playback runs on
the TV; the phone displays its controls. **在手机播放** stops the remote session
before starting local playback. TV settings can remove one or all trusted phones.

If the router blocks discovery, **输入电视地址** accepts `IP:port`; the port is
shown in the TV's **已信任的手机** panel. Both devices still need to reach each
other. Selecting a destination does not wake or launch the TV app.

## Automated checks (2026-10-29)

- Phone: `flutter test --no-pub`, **30 passed**. Focused analysis of `lib/tv`,
  `test/tv`, and the isolated device harness: **no issues**.
- TV: `gradlew.bat testDebugUnitTest`, **202 passed**, including **16 new remote
  tests**. ARM64/ARMv7 debug builds and the x86_64 debug receiver build succeeded.
- Regression coverage includes revoked credentials at command dispatch, delayed
  status after a newer selection, TV episode identity and local handoff, scoped
  pairing recovery, ownership/takeover, request deduplication, real TLS pinning,
  and removal of sensitive stream headers across cross-origin redirects.
- TV `lintDebug` reports **11 existing errors** in `MainActivity.kt` back-event
  handling and `SoftwareCodec.kt` opt-in declarations. Those declarations are
  present in the TV base commit; the feature adds no lint errors. Flutter also
  reports existing plugin migration warnings for built-in Kotlin.

## Device evidence and limits

The real Samsung SM-S936U phone used an isolated `.tvqa` installation with fake
account data. The receiver was the real Selene-TV APK running on an API 37
Android emulator at TV resolution (a phone system image, not Android TV firmware).
Pinned HTTPS traffic used an ADB-forwarded port; no account credentials were
copied. The normal Selene installation was preserved.

Verified: first decline/Allow with TV D-pad input, stored trust after receiver
restart, actual phone movie and live screens routing without a local media
session or phone progress writes, requested movie resume position, pause, seek,
resume and Stop. Playback continued while the phone's screen was off and after
its test process was killed. Reconnection did not replay media. TV D-pad episode
selection changed the reported episode/title/media identity, and physical Back
released the session. The live-path check used an MP4 test stream; it does not
establish compatibility with every live provider or codec.

NSD registration and the actual advertised port were verified on the receiver.
End-to-end discovery across the user's Wi-Fi/router, physical Android TV behavior,
network changes during playback, provider-specific authenticated HLS/DRM, and
physical-device two-phone takeover remain manual checks. The network ADB target
`192.168.1.192:5555` was unauthorized and was not modified.

The final regular phone APK was installed successfully as
`org.moontechlab.selene`, version 1.6.9 (4159), using a data-preserving update.
The temporary `.tvqa` app was removed. The final phone UI handoff check was
limited by the phone locking again; the episode/position handoff regression
passes in the service tests, and the rebuilt TV's native episode change was
verified on-device.

## Implementation decisions and independent review

- Reused the approved feature branches and companion checkout, without another
  linked worktree. Cost: concurrent edits in these checkouts need coordination.
- Used native PowerShell records instead of shell-only plan helper scripts.
  Cost: those helpers cannot automatically audit this execution record; test
  results, protocol fixtures and this record provide the evidence instead.
- Remote streams with custom headers use the existing Media3 backend to enforce
  credential scoping across redirects and segments. Header-free streams retain
  the selected backend. Cost: a header-protected stream requiring an mpv-only
  codec may not play until mpv gains the same scoped transport support.

An independent reviewer found three important issues and no critical issues:
revocation during a slow request, stale status overwriting a new selection, and
TV-side episode changes during reverse handoff. Each received a failing
regression test before its fix, followed by green suites. The missing episode
metadata and remove-all-trust action were also addressed. No review findings
were deferred.

## Building and test artifacts

Phone production entry: `flutter build apk --debug --no-pub --target-platform
android-arm64 -t lib/main.dart`. TV: `gradlew.bat assembleDebug`; an optional
`-PseleneEmulatorAbi=x86_64` applies only to debug builds. Release ABI settings,
application IDs, versions and signing configuration are unchanged.

Local final APK copies are under the phone workspace's ignored `build/qa/final/`:
`Selene-phone-arm64-debug.apk` and `Selene-TV-arm64-debug.apk`. The TV source
checkout is `.local/Selene-TV-source`. Protocol details and shared JSON fixtures
are committed separately in both repositories.

The fake-account phone harness is `test/device/tv_playback_smoke.dart`. Always
build it with Gradle property `seleneApplicationIdSuffix=.tvqa`; never install it
over the regular app. Its forwarded-port setup is for controlled QA only. Local
QA keys, logs and test media are ignored and must not be attached to PRs.
