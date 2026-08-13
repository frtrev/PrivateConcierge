# Open Issues

## Place search and place details

- Enrich installed Overture areas with business opening hours from a cacheable,
  legally compatible source. The preferred local-first design is to match
  OpenStreetMap `opening_hours` records to Overture POIs during area installation
  and retain source, update date, and match-confidence metadata.
- Review ODbL attribution and share-alike requirements before distributing a
  merged Overture and OpenStreetMap area database.
- Replace the limited weekly-hours parser with an implementation that safely
  handles the broader OpenStreetMap syntax, including split schedules, overnight
  hours, holidays, exceptions, and unknown/appointment-only hours.
- Show opening-hours coverage during area installation so the user knows how
  many installed places can support “open now” queries.
- Add freshness handling for enriched details and a way to refresh hours without
  replacing private visit data.
- Continue expanding the centralized category, synonym, and brand vocabulary.
  Unknown business names should eventually use confident generic name matching
  without requiring every regional brand to be added manually.
- Add broader natural-language regression tests as real voice-query failures are
  found, especially pluralization, filler words, ordering language, and combined
  brand/category/modifier requests.

## Notifications and driving behavior

- Present driving, parking, and nearby-place notifications consistently on the
  CarPlay and Android Auto interfaces, subject to each platform’s template and
  driver-distraction restrictions.
- Define notification cooldown, deduplication, priority, and expiry rules so the
  same event is not repeatedly announced during one trip.
- Measure and tune driving/parking detection latency and false positives using
  local diagnostics.
- Validate gas-station proximity notifications at the requested two-mile radius,
  including behavior when several stations overlap.
- Add per-notification preferences and a master in-vehicle notification switch.

## Location history and diagnostics

- Clarify the UI distinction between aggregate visit history, individual visit
  sessions, and tracking diagnostics.
- “Most visited places” currently shows every aggregate POI row and has no query
  or display cap. Repeated stays at the same POI update that row and increment its
  count only when at least four hours have elapsed; they do not create duplicate
  rows.
- Completed visit sessions are retained without an automatic limit but do not yet
  have a dedicated chronological history screen.
- Tracking diagnostics intentionally retain only the newest 500 events and the UI
  currently loads the newest 200. Add pagination or an explicit “load more” flow,
  and label both limits in the interface.
- Consider configurable diagnostic retention by age or count, separate from visit
  history retention.
- Add a chronological visit-session screen so parking arrivals/departures can be
  audited without relying on low-level diagnostic events.
- Ensure privacy deletion controls clearly state whether they remove aggregate
  visits, sessions, diagnostics, or all three. The current “Delete location
  history” action removes aggregate visited places only.

## Vehicle testing

- Repeat the place-search, open-hours fallback, navigation, voice-follow-up, and
  background-resume test matrix on both physical CarPlay and Android Auto units.
- Add native adapter tests for result pagination/caps and vehicle summary wording
  where platform test infrastructure permits it.
