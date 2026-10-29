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

- Phone: `flutter test --no-pub`, **31 passed**. Focused analysis of `lib/tv`,
  `test/tv`, and the isolated device harness: **no issues**.
- TV: `gradlew.bat testDebugUnitTest`, **202 passed**, including **16 new remote
  tests**. ARM64/ARMv7 debug builds and the x86_64 debug receiver build succeeded.
- Regression coverage includes revoked credentials at command dispatch, delayed
  status after a newer selection, TV episode identity and local handoff, scoped
  pairing recovery, ownership/takeover, request deduplication, real TLS pinning,
  and removal of sensitive stream headers across cross-origin redirects.
- The phone replay regression confirms that Play after Stop starts a new remote
  session instead of sending a command to the released player. Android places
  the TV picker in the top bar and the dark-mode switch in the user menu.
- TV `lintDebug` reports **11 existing errors** in `MainActivity.kt` back-event
  handling and `SoftwareCodec.kt` opt-in declarations. Those declarations are
  present in the TV base commit; the feature adds no lint errors. Flutter also
  reports existing plugin migration warnings for built-in Kotlin.

## Device evidence and limits

Initial receiver checks used an API 37 Android emulator at TV resolution (a
phone system image). Subsequent checks used the real Samsung SM-S936U phone
and an authorized SHIELD Android TV running API 30, over the user's Wi-Fi.
The phone harness used an isolated `.tvqa` installation and fake account data;
its production movie/live screens used the real TV connection service.

Verified on the physical devices:

- The phone automatically discovered the SHIELD. The user approved the native TV
  dialog. Pinned HTTPS connected directly over Wi-Fi, without ADB port forwarding.
- The TV test app signed into the requested server. The installed release uses
  a different signing key, so its data-preserving update was rejected. A separate
  `org.moontechlab.selenetv.tvqa` test app preserved the original TV app and data.
- Movie and live paths played on the TV with no phone media session or phone
  history writes. The live-path fixture was an MP4, not a broadcast/HLS provider.
- TV D-pad selection advanced to episode 2 and changed status title/media ID.
  **Play here** stopped the TV and resumed episode 2 on the phone at the TV's
  position. Phone progress logs confirmed episode 2 and media requests then came
  from the phone rather than the TV.
- Killing and reopening the phone test process retained the same TV playback
  session and did not show another approval dialog or replay the stream.
- While the phone was locked/dozing, TV position advanced from 55.744 to 63.744
  seconds. Back on the phone returned to its home screen while the same TV
  session continued playing.
- A physical-TV regression exposed swallowed Back events in the live Dialog.
  The device check failed before the fix and passed afterward: native TV Back
  exits playback and releases the session. Existing layered Back behavior
  (hide controls, then confirm exit) is retained.
- A second physical-TV regression exposed an inset live window:
  `[0,60][1920,1019]` instead of `[0,0][1920,1080]` on the logical display.
  Forcing the remote Dialog to match both display dimensions passed the same
  bounds check, and a new screenshot plus user confirmation verified no home
  content showing around the video. TV Back still passed after this fix.

Earlier emulator checks also covered first decline, requested 42-second movie
resume, pause, seek, resume, Stop, and persisted TLS/trust across receiver restart.
Provider-specific authenticated HLS/DRM, network changes during playback, and
physical-device two-phone takeover remain manual checks.

The final regular phone APK remains `org.moontechlab.selene`, version 1.6.9
(4159), installed using a data-preserving update. The temporary phone test app
was removed after the checks and its original 30-second screen timeout restored.
The SHIELD test app remains signed in and the sample stream was restarted after
the exit checks. Only the sample movie history entry was removed from the server,
after explicit user approval. No credentials or account screenshots are committed.

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
build it with the explicit Flutter argument
`--android-project-arg=seleneApplicationIdSuffix=.tvqa`; verify the APK package ID
before installation. Never install the fake-account entry over the regular app.
`--dart-define=TV_QA_MEDIA_URL=<reachable-LAN-URL>` supplies a sample reachable by
both physical devices. The emulator default is `10.0.2.2:8765`.

TV `-PseleneTestApplicationIdSuffix=.tvqa` creates the separately named debug
test app; normal and release builds retain their application ID and name.
TV `tools/qa/remote-live-back.ps1` and `remote-player-fullscreen.ps1` are reusable
physical-device regressions. Pass an authenticated status-reader script block
and the target ADB serial; credentials are deliberately outside those scripts.
Local QA keys, logs and test media are ignored and must not be attached to PRs.
