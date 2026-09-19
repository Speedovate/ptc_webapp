# Disposed Flutter Web view crash

The user's log contained 1,012 repetitions of the window.dart:99:12 assertion
followed by Target crashed. The installed web SDK identifies that line as
`Trying to render a disposed EngineFlutterView.`

## Reproduction

An isolated, signed-out Chrome session was started on port 3011 using:

```
flutter run -d chrome --web-port=3011 --web-browser-flag=--headless=new --web-browser-flag=--disable-gpu
```

Two hot restarts reproduced the exact assertion through
RenderView.compositeFrame -> RenderingBinding.drawFrame -> FrameService.
The test session recovered after each restart; the user's sustained 1,012-error
crash was not reproduced in its entirety. No production account was used.

## Fix

AppWidgetsBinding checks each RenderView's FlutterView against the engine's
public view registry before allowing frame submission. Removed views and stale
objects with reused IDs are excluded. Normal framework builds/layout continue,
and a valid replacement immediately passes the guard. The superclass first-frame
condition and native behavior are preserved. There are no timers, page reloads,
exception filters, SDK changes or database writes in this fix.

A restart that first loaded the new binding still reported the old generation's
assertion during teardown, as expected. Five subsequent hot restarts using the
new binding produced no disposed-view assertions. A CDP screenshot confirmed the
login page rendered after restart. Headless Chrome reported CPU-only rendering;
hardware GPU and authenticated background/resume stress remain unverified.

200 native tests pass, including removal/replacement/secondary-view cases. Eight focused Chrome lifecycle tests also pass.

## Offline Support typing after hot restart

The later user log also contains repeated shader compilation failures and
`TypeError: rawData[$forEach] is not a function` through documentData in Support
and Chassis. The user confirmed this occurs after hot restart, not a fresh run.
That identifies the trigger but does not prove a GPU driver or Firestore SDK root
cause. Do not rewrite document payloads, clear offline storage, or swallow these
errors as a supposed repair.

Support's composer now observes its content state locally so typing/clearing does
not rebuild the message history. Its outer PlatformShell opts into square top
corners; previously the parent's clipping rounded the already-square panels.
These UI changes are not a verified shader/runtime fix. Use a fresh debug session
for comparison; an optional CPU-only CanvasKit run can isolate the WebGL path:
`flutter run -d chrome --web-port=3000 --dart-define=FLUTTER_WEB_CANVASKIT_FORCE_CPU_ONLY=true`.
This diagnostic may render more slowly and does not change release defaults.
