> September 23 follow-up: the full logical collection is now fetched in bounded
> ID pages with bounded live ranges, cooperative cache processing and reused
> hydrated models. See `performance-followup-2026-09-23.md`. The historical
> description below predates this change; it remains correct that UI paging alone
> does not limit the full dataset needed by global consumers.

# Booking data performance follow-up

## Findings from the current code

BookingRequest.watchBookings previously created a cache-processing worker per
subscriber. Each retained booking/dashboard/profile/role consumer separately
read the durable cache, merged queued records, inflated relationships, sorted
records and computed an emission fingerprint. The Firestore subscription was
already shared, but its downstream processing was not.

Both admin booking filter methods also rescanned their complete input on every
call. Disabled diagnostic methods still received eagerly constructed strings,
including joined lists of booking IDs and statuses.

## Applied changes

- One reference-counted booking stream processes cache events for all active
  consumers. New consumers receive its latest immutable list; the last observer
  cancelling releases the source worker subscription and replay value. A fresh
  session starts from the existing authoritative/offline cache rules.
- Admin booking/dashboard filter results are reused until the view model notifies
  a data or criteria change. Disabled diagnostics receive lazy callbacks.
- Bookings and Dashboard initially pass 15 matching records to their table/card
  renderer, with a pull up near the end adding 15. Filtering happens over the full dataset;
  export methods still receive the full results. The display window survives
  opening details and resets when filter criteria change.

This is display pagination, not Firestore query pagination. The booking listener
still reads the complete collection. Its authoritative snapshot participates in
cache replacement, offline reconciliation, global search and export. Adding a
query limit there would make a partial result look like the full collection.
Server pagination needs a separate page repository/cache, compatible global
search, explicit complete exports, and migration/coverage for legacy ordering
fields before replacing that listener.

## Verification and limits

Tests exercise one source transformation for several concurrent consumers,
late-subscriber replay, cancellation/restart, errors, cached filter invalidation,
1,000-record display batches, access to a search match outside the initial batch,
and retained page state. These are behavioral checks, not production timing
measurements. No staging accounts are available; authenticated release profiling
is still required to quantify remaining lag and choose further query changes.

Pull-up paging observes the mounted viewport only. One gesture adds at most one
batch; idle layout and restored scroll offsets do not request batches. A bounded
mouse-wheel fallback supports tall windows where the first batch fits completely.
There are no polling timers; observers are removed when the widget is disposed.

Profile booking history (including both admin user-detail hosts) also uses the
15-item pull-up display window. Filters and status options are cached until their
inputs change, and still inspect the full user history. Status labels load
independently of bookings. A live snapshot takes precedence over a delayed
initial read; generation guards prevent previous-profile or disposed loads from
updating state or installing subscriptions. Widget tests cover all four roles,
both responsive widths, delayed reads/labels, user switching and disposal.
