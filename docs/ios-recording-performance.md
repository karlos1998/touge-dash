# iOS recording investigation — 2026-09-10

## Reproduced bottleneck

`TelemetryHistoryRecorder.record` assigned `sample.session` before inserting each
sample. SwiftData maintained the inverse `DriveSession.samples` relationship for
all existing samples on every assignment. Sampling the simulator process during
sustained recording located the dominant main-thread work in
`TelemetryHistorySample.session.setter`, inside the sample initializer.

A disk-backed XCTest recorded 6,000 samples in one session. Each iteration uses
an autorelease pool; each 1,000-sample block explicitly flushes pending data.
Both measurements used Debug builds on the same iPhone 17 Pro / iOS 26.2
simulator. These are accelerated persistence benchmarks, not real-time thermal
measurements or Bluetooth throughput measurements.

| Samples | Before (seconds) | After (seconds) |
| --- | ---: | ---: |
| 1–1,000 | 2.334 | 0.518 |
| 1,001–2,000 | 4.592 | 0.230 |
| 2,001–3,000 | 8.986 | 0.264 |
| 3,001–4,000 | 13.314 | 0.307 |
| 4,001–5,000 | 17.498 | 0.326 |
| 5,001–6,000 | 21.816 | 0.391 |
| Total | 68.540 | 2.036 |

The original tight-loop test without autorelease pools also accumulated gigabytes
of temporary allocations. Its memory peak must not be presented as a measurement
of the iPhone during an actual drive.

## Changes

- Insert samples without the relationship and attach them to the active session
  in one batch when saving. Preserve the existing schema and cascade deletion.
- Disable automatic context saves so incomplete relationship batches cannot be
  committed. Flush every five seconds and before a segment boundary, vehicle
  switch, manual split, acceleration save, retention cleanup, backgrounding or
  Bluetooth disconnect. All original telemetry fields and sampling rules remain.
- Keep ownership of services in `@State`, with subscriptions at the consuming
  views. The application/root tabs no longer subscribe to all controller,
  dashboard-buffer and video-recorder changes. Root history controls subscribe
  only to connection state and active session ID.

This follows Apple's guidance to narrow dependencies of frequently updated
views: [Understanding and improving SwiftUI performance](https://developer.apple.com/documentation/Xcode/understanding-and-improving-swiftui-performance).

The recorder still uses the main actor. Batching removes the measured hot path;
this change does not claim background database execution or zero frame stalls.

## Validation and reproduction

109 unit/integration tests passed on the simulator, including complete sample
counts, non-nil session relationships, automatic/manual session boundaries,
vehicle isolation, alert debounce and old-rule decoding. Maestro verified the
separate archive tabs and the fuel-pressure series in drive history. A further
UI pass enabled fuel-pressure monitoring, changed OR to AND, and saved the rules.
A signed Release build was installed on the paired iPhone 14 Pro. Automatic
launch was refused because the phone was locked; physical BLE/thermal validation
was not performed.

The real-time replay persisted 1,033 samples spanning 130.98 seconds, with no
orphaned sample relationships. A three-second process sample during replay
reported a 60.7 MB physical footprint (73.1 MB peak at that point). A camera
permission dialog from earlier simulator test settings initially covered the UI;
it was dismissed before testing tab navigation. These simulator memory figures
do not predict memory use on the physical phone.

```sh
xcodebuild -project ios/TougeDash.xcodeproj -scheme TougeDash \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO test
```

For a two-minute real-time input replay in a Debug simulator build:

```sh
SIMCTL_CHILD_TOUGE_DASH_REPLAY_TELEMETRY=1 xcrun simctl launch \
  --terminate-running-process booted it.letscode.touge-dash -TougeDash.video.autoRecord NO
```

The replay feeds encoded EMU frames through the production parser and processing
pipeline at 40 deliveries/s, using the isolated simulator vehicle. It suppresses
live cloud uploads and Live Activity for repeatable local profiling. It does not
simulate the CoreBluetooth radio. iPhone heat and battery improvement require a
real logger session after installing the Release build.
