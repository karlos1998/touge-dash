# iOS responsiveness investigation — 2026-10-22

## Changes in 1.4.5 (27)

- Both streaming parsers now scan a delivery with an offset and compact the
  buffer once. Previously each discarded byte/frame shifted the remaining
  array, making large coalesced/backlogged BLE deliveries quadratic. Fragmented
  frames, checksum recovery, decoded values and statistics are preserved.
- Startup/session retention runs on a SwiftData ModelActor constructed in a
  detached utility task. Its private context performs deletion/cascade work
  without occupying the main actor. Recording still uses its existing context
  and five-second relationship batches; this release does not claim all database
  work or BLE callbacks run in the background.
- Release diagnostics record slow telemetry processing, sample recording,
  persistence, incident processing, shared-store writes and retention (50 ms
  threshold). A coalesced 250 ms heartbeat records UI dispatch delays of at
  least 500 ms, ignoring background/suspension intervals. Explicit ECU requests,
  confirmations and failures are logged; no controls are sent automatically.
- Engine notifications check the current Critical Alerts permission before
  selecting that interruption level. This release retains Time Sensitive
  alerts because Apple has not granted the managed entitlement.

## Validation

116 simulator tests passed, including large/noisy BLE backlog tests with split
frame tails, the background-retention cascade test and 6,000 disk-backed samples
without missing relationships. The signed Release archive succeeded and
1.4.5 (27) was installed over 1.4.3 (25) on the connected iPhone 14 Pro, preserving
its app data. The existing App Store version was already 1.4.4 (26).

An optimized Swift benchmark on this Mac fed 100,000 noise bytes followed by
20,000 valid telemetry frames, and separately 200,000 non-status bytes followed
by a status frame. Before/after results from the same compiler and inputs:

| Parser | Before | After |
| --- | ---: | ---: |
| Telemetry | 256.2 ms | 0.216 ms |
| Control status | 309.7 ms | 0.119 ms |

These are deliberately large synthetic deliveries, not measured normal BLE
packet sizes or proof of the reported ten-second freeze's cause.

25-second before and 30-second after Time Profiler recordings were taken on the
physical phone. Neither reported a potential hang at the profiler's 250 ms
threshold. The Release log recorded startup and foreground activity with no
500 ms heartbeat stall. **The real EMULOGGER was unavailable**, so connected
startup, radio throughput and real ECU switch confirmation remain unverified.
The owner will test at the car on October 23. A separate simulator replay on a
copy of the phone archive kept telemetry running while navigating the dashboard,
history and settings. The replay persisted 1,025 samples with 1,025 valid parent
relationships. Its first frame incurred a 624 ms heartbeat delay; two
five-second history saves took 80 and 89 ms. These remaining costs are logged explicitly
and should not be described as a guarantee of zero UI stalls. A local copy of the phone archive
contained 44,117 telemetry samples in ten sessions; personal data and profiler
artifacts are excluded from Git under `build/investigation/`.

## Collecting the next real-device run

Diagnostic files persist across launches in the app's Documents directory:
`tougedash-performance.log` and `tougedash-performance.previous.log`. Each is
bounded to approximately 512 KiB. File I/O runs on a utility queue. They contain
operation labels, app/build identifiers and timings; no GPS, account credentials
or raw telemetry values. There is no remote upload.

```sh
xcrun devicectl device copy from \
  --device BFB5B7B5-8F06-52DF-9B1A-186B1DABDA35 \
  --domain-type appDataContainer \
  --domain-identifier it.letscode.touge-dash \
  --source Documents/tougedash-performance.log \
  --destination build/investigation/iphone-performance.log
```

Reproduce a cold launch with the real logger already available, scroll the
dashboard, visit history/settings, then test one configured switch. Correlate
`main-thread-delay` with `slow operation=...`, `bluetooth connected=...` and
`ecu-control` entries. If a stall has no slow operation, capture a Time Profiler
trace with the phone unlocked to inspect UI/layout/framework work. A missing
confirmation is distinct from a blocked UI; the switch timeout remains async.
