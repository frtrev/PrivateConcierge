# Charon Tracking and Visit Questions Catalog

This is the proposed natural-language coverage for questions about the user's private tracking, visits, routines, and parking history. It is a review checklist, not a statement that every question is implemented yet.

## Coverage legend

- `[CURRENT DATA]` Answerable from data already stored locally: place, category, coordinates, address, visit count, first/last visit, arrival, departure, and completed visit sessions.
- `[DERIVED]` Answerable by calculating over current visit sessions, but requires a tracking-query capability.
- `[NEW DATA]` Requires information that is not currently persisted or reliably inferred.
- `[PRIVACY/ACTION]` Reads, explains, exports, corrects, or deletes private tracking data.

The parser should accept normal variations of place names, custom places, POIs, categories, dates, weekdays, relative dates, and time ranges. Examples include “home,” “work,” “Walmart,” “the pharmacy,” “last Friday,” “yesterday,” “this month,” “between 2 and 5,” and “the last time.”

## 1. Recent location and visit recall

- [ ] `[CURRENT DATA]` Where was I last?
- [ ] `[CURRENT DATA]` What was the last place I visited?
- [ ] `[CURRENT DATA]` Where did I go most recently?
- [ ] `[CURRENT DATA]` When was my last recorded stop?
- [ ] `[CURRENT DATA]` What places did I visit today?
- [ ] `[CURRENT DATA]` Where have I been today?
- [ ] `[CURRENT DATA]` Where did I go yesterday?
- [ ] `[CURRENT DATA]` Where did I go last Friday?
- [ ] `[CURRENT DATA]` Show my visits from this morning/afternoon/evening.
- [ ] `[CURRENT DATA]` What was the first place I visited today?
- [ ] `[CURRENT DATA]` What was the last place I visited yesterday?
- [ ] `[CURRENT DATA]` Did I make any stops today?
- [ ] `[CURRENT DATA]` How many places did I visit today?
- [ ] `[CURRENT DATA]` Show my last five visits.
- [ ] `[CURRENT DATA]` What are my ten most recent visits?
- [ ] `[DERIVED]` Give me a summary of my day/weekend/week.

## 2. Arrival questions

- [x] `[CURRENT DATA]` What time did I arrive at `<place>` last Friday?
- [x] `[CURRENT DATA]` When did I get to `<place>`?
- [x] `[CURRENT DATA]` What time did I get home yesterday?
- [ ] `[CURRENT DATA]` When did I arrive at work today?
- [ ] `[CURRENT DATA]` When was the last time I arrived at `<place>`?
- [ ] `[CURRENT DATA]` What was my first arrival at `<place>` this week?
- [ ] `[CURRENT DATA]` List my arrival times at `<place>` this month.
- [ ] `[CURRENT DATA]` Did I arrive at `<place>` before 9 AM?
- [ ] `[CURRENT DATA]` Which days did I arrive at work late?
- [ ] `[DERIVED]` What time do I usually arrive at `<place>`?
- [ ] `[DERIVED]` What is my average arrival time at `<place>`?
- [ ] `[DERIVED]` What was my earliest/latest arrival at `<place>`?
- [ ] `[DERIVED]` Was today’s arrival earlier or later than usual?
- [ ] `[DERIVED]` How much later did I arrive today than last Friday?

## 3. Departure questions

- [ ] `[CURRENT DATA]` What time did I leave `<place>` last Friday?
- [ ] `[CURRENT DATA]` When did I leave home this morning?
- [ ] `[CURRENT DATA]` When did I leave work yesterday?
- [ ] `[CURRENT DATA]` When was the last time I left `<place>`?
- [ ] `[CURRENT DATA]` List my departure times from `<place>` this week.
- [ ] `[CURRENT DATA]` Did I leave `<place>` before/after 5 PM?
- [ ] `[CURRENT DATA]` Where did I leave most recently?
- [ ] `[DERIVED]` What time do I usually leave `<place>`?
- [ ] `[DERIVED]` What is my average departure time from `<place>`?
- [ ] `[DERIVED]` What was my earliest/latest departure from `<place>`?
- [ ] `[DERIVED]` Did I leave earlier than usual today?

## 4. Time spent and visit duration

- [ ] `[DERIVED]` How long was I at `<place>` last Friday?
- [ ] `[DERIVED]` How long did I stay at `<place>` today?
- [ ] `[DERIVED]` How much time did I spend at work yesterday?
- [ ] `[DERIVED]` How long was I away from home today?
- [ ] `[DERIVED]` What was my longest/shortest visit to `<place>`?
- [ ] `[DERIVED]` What is my average visit length at `<place>`?
- [ ] `[DERIVED]` How much total time did I spend at `<place>` this week/month?
- [ ] `[DERIVED]` Where did I spend the most time today/this week?
- [ ] `[DERIVED]` Which stops lasted more than an hour?
- [ ] `[DERIVED]` Which visits lasted less than 15 minutes?
- [ ] `[DERIVED]` Did I stay longer at `<place A>` or `<place B>`?
- [ ] `[DERIVED]` How much time have I spent at restaurants this month?
- [ ] `[DERIVED]` How much time did I spend away from home this week?

## 5. Whether and when a place was visited

- [ ] `[CURRENT DATA]` Did I go to `<place>` today/yesterday/last Friday?
- [ ] `[CURRENT DATA]` Have I ever been to `<place>`?
- [ ] `[CURRENT DATA]` When did I last visit `<place>`?
- [ ] `[CURRENT DATA]` When did I first visit `<place>`?
- [ ] `[CURRENT DATA]` Which days did I visit `<place>` this month?
- [ ] `[CURRENT DATA]` Was I at `<place>` between `<time A>` and `<time B>`?
- [ ] `[CURRENT DATA]` Where was I around 3 PM yesterday?
- [ ] `[CURRENT DATA]` Where was I on `<date>` at `<time>`?
- [ ] `[CURRENT DATA]` Was I home at 8 PM?
- [ ] `[CURRENT DATA]` Did I stop anywhere between home and work?
- [ ] `[CURRENT DATA]` Did I visit a pharmacy/gas station/restaurant this week?
- [ ] `[CURRENT DATA]` What was the last restaurant/store/church I visited?
- [ ] `[CURRENT DATA]` When was the last time I went grocery shopping?
- [ ] `[CURRENT DATA]` Which `<category>` places have I visited?

## 6. Frequency, counts, and rankings

- [ ] `[CURRENT DATA]` How many times have I visited `<place>`?
- [ ] `[CURRENT DATA]` How many times did I visit `<place>` this week/month/year?
- [ ] `[CURRENT DATA]` What place do I visit most often?
- [ ] `[CURRENT DATA]` Show my most visited places.
- [ ] `[CURRENT DATA]` What are my top five most visited restaurants/stores?
- [ ] `[CURRENT DATA]` Which gas station do I visit most?
- [ ] `[CURRENT DATA]` How often do I go to `<place>`?
- [ ] `[DERIVED]` How many unique places did I visit this week?
- [ ] `[DERIVED]` How many visits did I make today/this week/month?
- [ ] `[DERIVED]` Did I visit `<place>` more often this month than last month?
- [ ] `[DERIVED]` Which places have I not visited recently?
- [ ] `[DERIVED]` Which place did I start visiting most recently?
- [ ] `[DERIVED]` Which weekday do I visit `<place>` most often?
- [ ] `[DERIVED]` How many days has it been since I visited `<place>`?

## 7. Sequences, before/after, and trip reconstruction

- [ ] `[CURRENT DATA]` Where did I go after `<place>`?
- [ ] `[CURRENT DATA]` Where was I before `<place>`?
- [ ] `[CURRENT DATA]` What did I visit between `<place A>` and `<place B>`?
- [ ] `[CURRENT DATA]` What was my second/third stop yesterday?
- [ ] `[CURRENT DATA]` Show yesterday’s visits in order.
- [ ] `[CURRENT DATA]` What was my route of visited places today?
- [ ] `[CURRENT DATA]` Did I go directly from home to work?
- [ ] `[DERIVED]` How long was it between leaving `<place A>` and arriving at `<place B>`?
- [ ] `[DERIVED]` How many stops did I make before arriving home?
- [ ] `[DERIVED]` Which places do I commonly visit together?
- [ ] `[NEW DATA]` How many miles did I drive on that trip?
- [ ] `[NEW DATA]` Which exact roads did I take?
- [ ] `[NEW DATA]` How long was I driving versus stopped?

Current visit sessions reconstruct stops and gaps, not a continuous breadcrumb trail. Exact routes, mileage, and travel modes require additional trip data.

## 8. Routines, habits, and comparisons

- [ ] `[DERIVED]` What is my usual schedule for `<place>`?
- [ ] `[DERIVED]` What days do I usually visit `<place>`?
- [ ] `[DERIVED]` When do I normally arrive and leave work?
- [ ] `[DERIVED]` Do I usually go to `<place>` on Fridays?
- [ ] `[DERIVED]` What places are part of my Monday routine?
- [ ] `[DERIVED]` Has my arrival time changed recently?
- [ ] `[DERIVED]` Am I spending more or less time at `<place>` lately?
- [ ] `[DERIVED]` Was this week different from my normal routine?
- [ ] `[DERIVED]` Which routine did I miss today/this week?
- [ ] `[DERIVED]` When am I usually home?
- [ ] `[DERIVED]` What time do I normally leave home?
- [ ] `[DERIVED]` Which days am I usually away from home the longest?
- [ ] `[DERIVED]` Compare my visits this week with last week.
- [ ] `[DERIVED]` Compare `<place A>` and `<place B>` by frequency/time spent.
- [ ] `[DERIVED]` What new places did I visit this month?

## 9. Parking and driving context

- [ ] `[NEW DATA]` Where did I park the car?
- [ ] `[NEW DATA]` Show where I parked on the map.
- [ ] `[NEW DATA]` Give me walking directions back to my car.
- [ ] `[NEW DATA]` What time did I park?
- [ ] `[NEW DATA]` How long has the car been parked?
- [ ] `[NEW DATA]` Where did I park yesterday/last Friday?
- [ ] `[NEW DATA]` Did I park near `<place>`?
- [ ] `[NEW DATA]` What is the address of my parking spot?
- [ ] `[NEW DATA]` How far am I from my car?
- [ ] `[NEW DATA]` Which parking location did I use most often?
- [ ] `[NEW DATA]` Where did I start driving?
- [ ] `[NEW DATA]` What time did I start/stop driving?
- [ ] `[NEW DATA]` How long was my last drive?
- [ ] `[NEW DATA]` Where was the car when driving mode ended unexpectedly?

The app currently detects and notifies that parking occurred, but it does not persist a dedicated parking event with coordinates and time. Supporting these requires a local `ParkingEvent` record and clear rules for replacing/retaining parking history.

## 10. Nearby and geographic history

- [ ] `[CURRENT DATA]` What places have I visited near here?
- [ ] `[CURRENT DATA]` Have I been here before?
- [ ] `[CURRENT DATA]` When was I last near/at this place?
- [ ] `[CURRENT DATA]` Which visited place is closest to me now?
- [ ] `[CURRENT DATA]` Show visited places within one/two/five miles.
- [ ] `[CURRENT DATA]` Which cities/areas have I visited based on saved addresses?
- [ ] `[DERIVED]` What area do I spend the most time in?
- [ ] `[DERIVED]` Which visited places are near each other?
- [ ] `[NEW DATA]` How many miles did I travel today?
- [ ] `[NEW DATA]` Show a heat map of everywhere I traveled.

The current database stores coordinates for recognized aggregate places, but visit sessions store the place identity rather than a continuous location trail.

## 11. Unknown, ambiguous, and custom places

- [ ] `[CURRENT DATA]` Did Charon detect any unknown places recently?
- [ ] `[CURRENT DATA]` How often have I visited this unknown place?
- [ ] `[CURRENT DATA]` When was the last unknown stay detected?
- [ ] `[PRIVACY/ACTION]` Name this place `<name>`.
- [ ] `[PRIVACY/ACTION]` Save this location as home/work/gym/other.
- [ ] `[PRIVACY/ACTION]` Change the detection radius for `<custom place>`.
- [ ] `[PRIVACY/ACTION]` Rename `<custom place>`.
- [ ] `[DERIVED]` Which recorded visits could not be matched to a POI?
- [ ] `[DERIVED]` Are any of my custom places overlapping?
- [ ] `[NEW DATA]` Was a visit assigned to the wrong nearby business?

Correction questions require an edit/reassignment workflow so changes update both aggregate history and visit sessions safely.

## 12. Data quality, confidence, and diagnostics

- [ ] `[DERIVED]` How confident are you that I visited `<place>`?
- [ ] `[CURRENT DATA]` Why was this visit recorded?
- [ ] `[CURRENT DATA]` Why was this visit ignored?
- [ ] `[CURRENT DATA]` Was background tracking working at `<time>`?
- [ ] `[CURRENT DATA]` When was the last location update?
- [ ] `[CURRENT DATA]` Were there gaps in tracking today?
- [ ] `[CURRENT DATA]` Did GPS noise affect this visit?
- [ ] `[CURRENT DATA]` Was this location ambiguous between multiple POIs?
- [ ] `[CURRENT DATA]` Is background location permission enabled?
- [ ] `[DERIVED]` Which visits have incomplete arrival or departure information?
- [ ] `[DERIVED]` Could this be a duplicate visit?
- [ ] `[PRIVACY/ACTION]` Mark this visit as incorrect.
- [ ] `[PRIVACY/ACTION]` Merge these duplicate visits.

Diagnostics are intentionally retained for only the recent diagnostic window; durable confidence/provenance per visit would require new fields on visit sessions.

## 13. Privacy, retention, export, and deletion

- [ ] `[PRIVACY/ACTION]` What tracking data do you have about me?
- [ ] `[PRIVACY/ACTION]` Is my visit history stored locally?
- [ ] `[PRIVACY/ACTION]` How far back does my history go?
- [ ] `[PRIVACY/ACTION]` How many visit records are stored?
- [ ] `[PRIVACY/ACTION]` How much storage is my tracking history using?
- [ ] `[PRIVACY/ACTION]` Show all data stored for `<place>`.
- [ ] `[PRIVACY/ACTION]` Export my visits for today/this month/all time.
- [ ] `[PRIVACY/ACTION]` Export this visit as CSV/JSON.
- [ ] `[PRIVACY/ACTION]` Delete this visit.
- [ ] `[PRIVACY/ACTION]` Delete visits to `<place>`.
- [ ] `[PRIVACY/ACTION]` Delete today’s/last month’s visit history.
- [ ] `[PRIVACY/ACTION]` Delete visits older than `<period>`.
- [ ] `[PRIVACY/ACTION]` Keep only the last `<period>` of visit history.
- [ ] `[PRIVACY/ACTION]` Stop/resume tracking.
- [ ] `[PRIVACY/ACTION]` Forget where I parked.
- [ ] `[PRIVACY/ACTION]` Delete all tracking data.

Destructive requests must require explicit confirmation and state exactly which local records will be removed.

## 14. Follow-up and conversational references

After Charon answers a tracking question, it should resolve references to the same result or result set:

- [ ] `[DERIVED]` How long was I there?
- [ ] `[DERIVED]` What time did I leave?
- [ ] `[CURRENT DATA]` When was the visit before that?
- [ ] `[CURRENT DATA]` What did I do next?
- [ ] `[CURRENT DATA]` Show me that place on the map.
- [ ] `[CURRENT DATA]` What is its address?
- [ ] `[DERIVED]` Is that normal for me?
- [ ] `[DERIVED]` Compare it with the previous week.
- [ ] `[CURRENT DATA]` How many times have I been there?
- [ ] `[PRIVACY/ACTION]` Rename it.
- [ ] `[PRIVACY/ACTION]` Delete that visit.
- [ ] `[PRIVACY/ACTION]` Correct the arrival/departure time.

Context must retain the referenced visit session or place ID; Charon must not guess what “there,” “that visit,” or “it” means when context is missing or stale.

## 15. Required response behavior

- [ ] Clearly distinguish “no matching visit” from “tracking data was unavailable.”
- [ ] Never invent an arrival, departure, duration, place, route, or parking location.
- [ ] State when a visit is still active and therefore has no departure time.
- [ ] State when only aggregate first/last/count data exists but no matching detailed session exists.
- [ ] Ask for clarification when multiple places share a name or the date is ambiguous.
- [ ] Interpret dates and times in the device’s local timezone and locale.
- [ ] Resolve relative dates from the current date: today, yesterday, last Friday, this week, last month.
- [ ] Support singular/plural and natural contractions without changing intent.
- [ ] Allow result limits: last three visits, top five places, visits after 6 PM.
- [ ] Preserve the same tracking answer object across Phone, CarPlay, and Android Auto.
- [ ] Offer “Show on map” only when coordinates exist.
- [ ] For sensitive or destructive actions, confirm before modifying local data.

## Suggested approval decision

Review each checkbox and mark it approved, rejected, or deferred. Implementation can then proceed in phases:

1. Exact visit lookup and recent-history questions using current data.
2. Counts, durations, comparisons, sequences, and routine summaries.
3. Conversational follow-ups and map actions.
4. Persisted parking events.
5. Corrections, export, retention controls, and advanced diagnostics.
