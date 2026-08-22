# Local Calendar Auto-Curation Plan — Taiwan Family Activities (親子活動)

**Goal:** Automatically discover + populate curated local calendars so that editing/adding
Firestore records (or running the scheduled job) surfaces real upcoming events on every device.

**Scope (v1):** Region = Taipei + New Taipei. Category = 親子活動 (parent-child / family activities).
Capture window = next 30 days. Backend = scheduled Cloud Function (asia-east1). Client reads Firestore.

---

## Ground truth (verified in repo, 2026-08-21)
- `localCalendars/{id}` collection exists — curated calendar *metadata* (title, region, category,
  tags, windowStartDate/EndDate, `isCurated`). App reads `whereField("isCurated", isEqualTo: true)`.
- `DiscoverService.localEventsMap: [String: [CalendarEvent]]` + `events(for:)` already exist —
  the app EXPECTS per-calendar events; they are just not loaded from Firestore yet (seed/fallback only).
- `CalendarEvent` already has `calendarType: .local`, `externalId`, `externalCalendarId`, `source`.
- 3 Cloud Functions LIVE (`firebase functions:list`): `fanOutGroupEvent`, `targetPromotionsForUser`,
  `publishLocalCalendarWindow` (scheduled daily). The last is the natural host hook.
- Real, FREE, LEGAL data sources confirmed:
  - Taipei: `travel.taipei` Open API → 活動展演 (Events/Activities) JSON endpoint (24k+ downloads).
  - New Taipei: `data.ntpc.gov.tw` open platform (event/activity datasets).
  - `data.gov.tw` has a literal "Parent-child activities" dataset.

## Firestore schema to add
- `localCalendars/{calendarId}` — auto-create curated calendar per (region, category):
  `{ id:"taipei_qinzi", title:"臺北 親子活動", region:"Taipei", category:"親子活動",
     isCurated:true, windowStartDate, windowEndDate, tags:[...], colorHex, subscriberCount:0 }`
- `localCalendarEvents/{eventId}` — upsert by source `externalId` (idempotent):
  maps to existing `CalendarEvent`:
  `title, startDate, endDate, isAllDay, location, notes(sourceUrl), calendarType:.local,
   externalCalendarId:calendarId, externalId, source:"travel.taipei"|"ntpc", createdAt, updatedAt`

## Backend (Cloud Function)
Extend / add `curateTaiwanFamilyEvents` (or reuse `publishLocalCalendarWindow`), scheduled daily, asia-east1:
1. For `region ∈ {Taipei, New Taipei}`, `category = 親子活動`:
   - Taipei: GET travel.taipei 活動展演 API (JSON).
   - New Taipei: GET data.ntpc.gov.tw events dataset.
   - Keyword/category filter to family/parent-child activities.
2. Normalize → `CalendarEvent`; keep only events with `startDate` within next `WINDOW_DAYS=30`.
3. **Upsert** by `externalId`; skip if unchanged (no duplicate spam on daily re-run).
4. Ensure parent `localCalendars` doc exists + `isCurated=true`; refresh `windowEndDate`.
5. Idempotent, small payload, daily cadence.

## Client (DiscoverService)
- Extend `fetchCuratedCalendarsFromFirestore()` to also load `localCalendarEvents` per visible calendar
  into `localEventsMap` (the field already exists; populate source is TBD).
- Bump Discover window from 14 → 30 days for this feed.
- Preserve offline seed fallback.

## Phasing
- **Phase A** — Function: ingest Taipei via travel.taipei; verify API schema via curl FIRST;
  upsert into Firestore. (THIS PHASE.)
- **Phase B** — Add New Taipei (data.ntpc.gov.tw) + client event-loading + 30-day window.
- **Phase C** — Admin guardrails: dedup/quality filter, category label localization (zh-Hant/en/ja),
  manual-override flag on calendar docs.

## Caveats
- travel.taipei / NTPC field names, date formats, and any API key MUST be verified by curl before coding.
- Tourism APIs are broad; 親子 filtering is keyword-based → expect curation tuning.
- Client event-loading path is not yet wired to Firestore (Phase B).

## Acceptance (Phase A)
- `curl` against travel.taipei 活動展演 returns parseable JSON with event title/date/location fields.
- Function upserts ≥1 Taipei 親子 event into `localCalendarEvents` with `externalCalendarId:"taipei_qinzi"`.
- `localCalendars/taipei_qinzi` exists with `isCurated:true`.
- Re-running the function does NOT create duplicates (upsert by externalId).
- Function deployable to asia-east1 and passes `tsc` typecheck.
