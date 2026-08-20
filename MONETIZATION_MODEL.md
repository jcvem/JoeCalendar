# JoeCalendar — Monetization Model

> **Phase:** Early-stage (pre-launch). **Goal:** validate willingness-to-pay in TW/JP/KR
> before over-building. Two operating-team-controlled revenue streams + one user sub.
> Companion to `IMPLEMENTATION_PLAN.md` and `MRR_ANALYSIS.md`.

---

## 1. Revenue streams (summary)

| # | Stream | Owner | Who pays | Phase |
|---|--------|-------|----------|-------|
| R1 | **Freemium subscription** (remove ads + perks) | Us | End users | P3 |
| R2 | **Local Calendars** (editorial, team-curated) | Us (B2B sales) | Local businesses / orgs buying placement | P3 |
| R3 | **Promoted Events** (ad unit, free tier) | Us (self-serve/ad ops) | Sponsors buying event promotion | P3 |

R2 + R3 are the **operating-team-controlled** streams you specified — the strategic
ones. R1 is the baseline consumer sub.

---

## 2. R1 — Freemium subscription (ad removal + perks)

**Positioning:** app is free with ads; pay to remove ads + unlock convenience perks.

- **Free tier:** full calendar (device + Google sync, social groups), ads shown
  (promoted events + light banner), limited local-calendar follows (e.g. 2).
- **Pro (subscription):**
  - Remove all ads / promoted events.
  - Unlimited local-calendar follows.
  - Extra perks (nice-to-have, not core): more group color themes, advanced repeat
    rules, export. Keep small — core is "ad-free + local calendars."
- **Pricing (reference, adjust per market):**
  - TW: NT$90/mo or NT$890/yr (~$3 / ~$27).
  - JP: ¥480/mo or ¥4,800/yr (~$3 / ~$30).
  - KR: ₩1,200/mo or ₩11,000/yr (~$0.9 / ~$8) — KR价格敏感, cheaper.
  - Use **StoreKit**; local payment rails later (LINE Pay TW, Kakao Pay KR) if subs
    low via App Store.
- **Benchmark:** TimeTree/Benefit-style JP calendar subs sit ~¥480–¥960/mo; we undercut
  on price, win on local-calendar value.

---

## 3. R2 — Local Calendars (B2B, operating-team controlled) ★ core stream

**Concept:** the operating team creates & controls curated calendars showing "what's
on in the next 14 days" per city/category. Businesses/orgs **pay us** to be listed
as a Local Calendar or to sponsor entries.

### 3.1 Product shapes
- **City/neighborhood calendar** (e.g. "Taipei East District", "Osaka Umeda") —
  aggregated public + sponsored events.
- **Category calendar** (e.g. "Live Music Taipei", "Markets & Pop-ups", "Kids
  Weekend") — vertical, high intent.
- **Brand/Owner calendar** (e.g. a museum, venue, chain café) — the biz pays to
  publish its own events into the discovery surface.

### 3.2 Pricing model (B2B)
| Package | What | Indicative price (TW/JP/KR) |
|---------|------|------------------------------|
| Listing (entry) | 1 brand/local calendar, basic placement | NT$3,000–6,000 /mo (~$90–180) |
| Featured | priority rank + badge in Discover | +NT$5,000/mo (~$150) |
| City sponsorship | exclusive category slot in a city | NT$15,000–30,000/mo (~$450–900) |
| Self-serve credit | businesses load credits, pay per event placed | NT$200–500 / event (~$6–15) |

- Start **managed/sales-led** (founder + 1 BD), move to **self-serve credit** later.
- Margin is high (near-100% COGS = content curation time). This is the profit engine.

### 3.3 Why this works
- From `MRR_ANALYSIS.md`: Japan users already pay for calendar apps (Caho/Lifebear
  huge rating bases) → proven local-content willingness-to-pay.
- Local businesses have no cheap, targeted way to reach nearby calendar users → we
  are the wedge. Low CAC via the free app's existing reach.

---

## 4. R3 — Promoted Events (ad unit, free tier) ★ core stream

**Concept:** free users see commercially-bought event promotions inside Discover and
as subtle inline cards. Sponsors buy promotion; we target by region/interest.

- **Unit:** native event card ("Sponsored"), region + interest targeted, capped
  frequency (don't annoy Pro users — they're ad-free).
- **Pricing:** CPM or per-event-promotion. Reference: NT$80–150 CPM; or
  NT$1,500–4,000 / promoted event / 14-day run (~$45–120).
- **Inventory:** only free-tier impressions count; grows with free MAU.
- **Guardrail:** cap to ≤1–2 promoted cards per Discover session; never inject into
  private/group calendars (privacy + trust).

---

## 5. Unit economics sketch (illustrative, NOT a forecast)

Assume at 6 months: **100k MAU** (free-heavy, TW/JP/KR), 8% ad-free conversion.

- R1 subs: 8k subs × ~$2.50 avg/mo = **$20k/mo**.
- R3 promoted: 92k free MAU × ~$0.30 ARPMAU (ads) = **~$27k/mo** at modest fill.
- R2 local calendars: 30 paying local biz × ~$150/mo = **$4.5k/mo** (early, sales-led).
- **~$50k/mo gross** at 100k MAU — before scaling local-calendar sales (the lever).

Key lever = **R2 local-calendar count** (high-margin, operating-controlled). R3 scales
with free MAU; R1 is stable recurring.

---

## 6. Guardrails / trust (do not violate)
- **Never** show promoted/local content inside private or group calendars.
- Local calendars are **editorial** — disclose "Sponsored" clearly; keep organic curation.
- Ad-free Pro must be honored server-side (subscription flag in Firestore).
- Privacy: group-visibility events (pickleball-with-workout-friends) never leak to
  work group or to any ad targeting.

---

## 7. Phase 3 build checklist (for agy)
- [ ] Ad unit (AdMob or native promoted card) for free tier only.
- [ ] StoreKit paywall → `subscriptions/{uid}.adFree`.
- [ ] Local-calendar model + team admin publish flow (next-14-day window).
- [ ] Promoted-events model + targeting (region/interests) + frequency cap.
- [ ] Server-side enforcement: promo/local never in private/group views; ad-free honored.

---

*Draft v1 — founder to pressure-test pricing with 3–5 local-business interviews before launch.*
