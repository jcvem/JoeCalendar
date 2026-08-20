# JoeCalendar — iOS Native (Swift) Implementation Plan

> **Role:** Senior PM plan. **Status:** Early-stage, fast loops. Tests relaxed.
> **Stack:** Native iOS (Swift + SwiftUI), Firebase (Firestore + Auth + Cloud Functions),
> Google Calendar API + Apple EventKit for sync, Gemini (via agy) for translations.
> **Aesthetic:** TimeTree-inspired, Japanese editorial restraint.

---

## 0. Goals (from founder)
Cover TimeTree's basic feature set **+** these differentiators:

1. **Device calendar sync** (Apple EventKit — two-way).
2. **Google Calendar sync** (Google Calendar API — OAuth, two-way).
3. **Social / grouped sharing** — user creates events visible to *friend groups*
   (e.g. "Workout friends" see biweekly pickleball; "Close friends" see it;
   "Work friends" do NOT). Groups are the privacy unit.
4. **Discover / nearby + local calendars (monetization)**
   - *Promoted events*: free users shown commercially-bought promotions (ad unit).
   - *Local calendars*: editorially curated by the operating team, show "what's on
     in the next 2 weeks." This is a core revenue stream.
   - Main app = **freemium**: free with ads; paid subscription removes ads (+ maybe
     extra groups/features).
5. **UI**: TimeTree-inspired, Japanese aesthetic (clean, calm, rounded, soft).
6. **i18n**: device-default + user-overridable. First: **繁體中文 (zh-Hant),
   English, 日本語**. Translations via **Gemini (through agy)** for human quality.
7. **Backend**: Firebase (Firestore + Auth + Functions). Project name **JoeCalendar**.
   agy creates it via connected Google account; if Google Cloud features need
   enabling, agy reports → founder enables manually.
8. **Pace**: quick loops; testing relaxed at this stage.
9. **Execution**: agy implements.

---

## 1. Architecture (high level)

```
iOS App (SwiftUI)
 ├─ EventKit wrapper (device calendar, two-way)
 ├─ Google Sign-In + Calendar API (OAuth, two-way)
 ├─ Firebase Auth (email/Google/Apple sign-in)
 ├─ Firestore (events, groups, friendships, local-calendars, promos)
 ├─ Cloud Functions (group-event fan-out, promo targeting, local-cal publish)
 ├─ Gemini translation service (agy-generated strings → 3 locales)
 └─ Ad unit (free tier) / Paywall (subscription to remove ads)
```

### Data model (Firestore)
- `users/{uid}` — profile, linkedCalendars, friendIds, groupIds, locale, adFree.
- `groups/{groupId}` — name, ownerUid, memberUids[], privacy default.
- `friendships/{id}` — uidA, uidB, status.
- `events/{eventId}` — title, start, end, calendarType (device|google|joe|local|promo),
  visibility: { type: public|group|private, groupIds[] }, createdBy, source.
- `localCalendars/{id}` — curated by team; `events` subcollection or denormalized;
  window = next 14 days; region/tags.
- `promotions/{id}` — sponsor, creative, targeting (region/interests), schedule,
  paid flag; shown to free users.
- `subscriptions/{uid}` — adFree bool, plan, expiry.

---

## 2. Phased delivery (fast loops)

### Phase 0 — Foundation (agy)
- [ ] `git` repo ready (done: 01ad454).
- [ ] Xcode project: SwiftUI app "JoeCalendar", target iOS 17+.
- [ ] Firebase init: **project "JoeCalendar"** (agy w/ Google account).
  - If agy hits a gated Google Cloud feature → **report to founder, manual enable**.
  - Register iOS app, download `GoogleService-Info.plist` (gitignored).
- [ ] Firebase Auth (Email + Google + Sign in with Apple).
- [ ] i18n scaffold: `Localizable.xcstrings` / String Catalogs, 3 locales
  (zh-Hant, en, ja). Translations produced via **Gemini (agy)**.
- [ ] Design system: Japanese-calm palette, rounded cards, typography (see §5).

### Phase 1 — Core calendar (TimeTree baseline)
- [ ] Month / week / list views (TimeTree-style).
- [ ] Event create/edit (title, time, notes, color, repeat).
- [ ] **Apple EventKit sync** (two-way, on-device + Firestore mirror).
- [ ] **Google Calendar sync** (OAuth, two-way).
- [ ] Notifications / reminders.

### Phase 2 — Social groups (the differentiator)
- [ ] Friends: search by JoeCalendar ID / contacts, send/accept.
- [ ] Groups: create group, add members, set privacy.
- [ ] Event visibility: private / specific groups / public.
- [ ] Group event feed + per-group calendar view.
- [ ] Cloud Function: when event created with group visibility, fan out to members.

### Phase 3 — Discover & monetization
- [ ] **Local calendars**: team-curated, next-14-days feed; team admin publishes.
- [ ] **Promoted events**: ad unit for free users; targeting by region/interests.
- [ ] **Freemium**: ad-free subscription (StoreKit); paywall; ad removal.

### Phase 4 — Polish & i18n completion
- [ ] Gemini translation pass for all UI strings (3 locales, human-quality).
- [ ] Japanese-aesthetic UI refinement (motion, spacing, iconography).
- [ ] Device-locale default + in-app override.

---

## 3. Key risks / decisions to confirm
- **Google Cloud enablement** may require founder action (billing, APIs).
  agy will report; founder enables; loop continues.
- **EventKit two-way sync conflict resolution** — keep simple MVP (last-write-wins
  + source tagging), refine later.
- **Privacy model** — groups are the unit; explicitly prevent work-group leakage
  (founder's pickleball example). Enforce server-side in Cloud Functions.
- **Ads SDK** — start with AdMob (Firebase-native) for free tier.
- **StoreKit** subscription for ad-removal.

---

## 4. Assignment to agy
agy implements Phase 0 → 4 in fast loops. PM (me) verifies each phase:
build runs, Firestore schema sane, i18n keys present, social/promo logic correct.

---

## 5. UI direction (TimeTree + Japanese)
- Calm, high-whitespace, rounded cards, soft shadows.
- Accent: single restrained color (not purple). Pastel group colors.
- Typography: humanist sans; CJK via system fonts (Hiragino/PingFang/Noto).
- Motion: gentle, purposeful (no gratuitous animation).

---

*Plan v1 — founder to confirm before Phase 0 dispatch.*
