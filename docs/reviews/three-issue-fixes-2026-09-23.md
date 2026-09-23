# Three reproduced transition defects — fixes

Local fixes, September 23, 2026. No deployment or production data edits.

- Cache fallback checks its write revision again after awaited persistence before
  removing the mirror. The ordered-storage regression preserves the newer mirror
  even when its best-effort IndexedDB backup fails, including on reopen.
- Paged bookings watches recover failed discovery/listeners with one exponential
  backoff timer (1 second to 60 seconds). Successful direct reads re-arm failed
  watches immediately through the existing coalesced rebuild path. Offline state
  pauses attempts; permission/configuration errors wait for a read/network state
  change. Cancellation removes callbacks, subscriptions and timers. Partial page
  results still never replace the complete cache.
- Diagnostic outbox index mutations and receipt pruning hold a browser Web Lock
  for the origin. Independent tabs therefore cannot overwrite each other's shard
  registration. Native tests use a process-wide serialized tail. Browser locks
  release on exceptions or context closure; no lock-polling timer is introduced.
  Existing v2 keys and reports remain compatible. Browsers without Web Locks fail
  explicitly rather than performing an unsafe unlocked index mutation; this
  requires a supported secure browser context (production HTTPS or localhost).

Validation: 29 targeted Dart tests and 8 Chrome tests passed, including the three
original injected failures with corrected expectations, automatic recovery without
network events, cancelled-watch cleanup, same-shard concurrent writers, and an
independent iframe holding the origin-wide lock. Analyzer clean. These are local
fault-injection/browser tests, not authenticated production end-to-end tests.

Scope: prevents the reproduced index race for cooperating updated clients. Old
open tabs running the previous code do not acquire the new lock; reload them on
rollout. This change does not reconstruct diagnostic index entries already lost
before the fix, and is not a redesign of same-fingerprint occurrence aggregation
across tabs. Business queue contents and original action timestamps are unchanged.
