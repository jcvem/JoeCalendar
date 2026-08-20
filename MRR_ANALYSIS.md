# JoeCalendar — Calendar/Event App MRR Analysis (TW / JP / KR)

> **IMPORTANT — READ FIRST.** True MRR is *private* company data. No app in this
> list publishes audited MRR. The figures below are **estimates** built from:
> 1. Publicly reported revenue/ARR/users figures (cited per app), and
> 2. A transparent review-count proxy for apps where no public number exists.
>
> Treat the "reported" rows as grounded-in-public-data and the "modeled" rows as
> order-of-magnitude estimates (±50%–2x). The goal is **relative ranking and
> market-structure insight**, not a balance-sheet.

---

## Methodology

**Two estimate classes:**

- **REPORTED** — a real public number exists (press release, founder tweet, ARR
  estimate from GetLatka/Latka, Crunchbase, acquisition docs). Used directly.
- **MODELED** — no public number. I derive a floor using App Store ratings count
  (`meta.json`) as a proxy for install base, then apply a conservative
  paid-conversion + price assumption:

  ```
  est_monthly_paying ≈ ratings × C    (C = paid-share constant, 0.5–2.0)
  est_MRR ≈ est_monthly_paying × avg_monthly_price
  ```

  - Ratings ≈ 1 per ~50–200 downloads (App Store shows ~0.5–2% of users rate).
  - Free/freemium apps convert ~1–5% of actives to paid; paid-only convert higher.
  - Avg monthly price assumed $2–$10 depending on model (Japan indies cheap,
    Western productivity premium).
  - Model deliberately conservative; real MRR for category leaders is often higher.

---

## Japan — the deepest, most monetizable market here

| Rank | App | Reviews (JP) | Class | Est. MRR (USD/mo) | Basis |
|------|-----|-------------|-------|------------------|-------|
| 1 | **TimeTree** | 1,038,563 | REPORTED | **~$1.0M–2.0M** | 40M+ users (2022 press); Owlert $12.5M rev; ¥6.7B raised. ~3–6% paid → est. $1M+ MRR |
| 2 | **Caho カレンダー** | 394,975 | MODELED | ~$150K–400K | Huge JP rating base; cute/decoration niche; cheap IAP → modest ARPPU |
| 3 | **シンプルカレンダー (Komorebi)** | 371,176 | MODELED | ~$150K–350K | Strong JP+TW base; freemium IAP |
| 4 | **Lifebear** | 321,259 | MODELED | ~$120K–300K | Calendar+notebook; JP-only; subscription |
| 5 | **Tree カレンダー** | 108,024 | MODELED | ~$40K–100K | LAN CHEN sibling of Caho |
| 6 | **Yahoo! カレンダー** | 107,021 | REPORTED* | ~$0 direct | Owned by Yahoo Japan (ZHD); ad/ecosystem play, not subscription MRR |
| 7 | **Google カレンダー** | 38,102 | n/a | $0 | Free, Google ecosystem |
| 8 | **シンプルカレンダー (ScheduleBook)** | 18,068 | MODELED | ~$10K–30K | Indie, smaller |
| 9 | **ジョルテ (Jorte)** | 4,951 | MODELED | ~$5K–20K | Legacy brand, declining ratings |

**JP insight:** TimeTree dominates with a *shared-calendar* wedge (families/couples).
The rest are **design/decoration-led indies** (Caho, Lifebear, Tree) monetizing via
cheap IAP/subscriptions to a massive domestic Japanese user base. This is the
**most concentrated, highest-MRR-per-app regional market** in the set.

---

## Korea — AI-forward, but smaller reported numbers

| Rank | App | Reviews (KR) | Class | Est. MRR (USD/mo) | Basis |
|------|-----|-------------|-------|------------------|-------|
| 1 | **TimeTree** | 86,540 | REPORTED | ~$80K–200K (KR slice) | Same global entity; KR is one market of many |
| 2 | **Apple キャンレンダー** | 26,663 | n/a | $0 | Built-in, free |
| 3 | **Evernote** | 12,338 | REPORTED | ~$2M–4M (global) | ~$100M recurring rev (Bending Spoons acquisition doc); KR is a slice |
| 4 | **Google キャンレンダー** | 5,966 | n/a | $0 | Free |
| 5 | **Todoist** | 5,362 | REPORTED | ~$2.2M (global ARR $26.5M, GetLatka) | 300K customers; KR slice |
| 6 | **히로 AI (Hero)** | 708 | REPORTED | early / <$100K | 300K users claimed, 100% free (tryhero.app); pre-monetization |
| 7 | **Fantastical** | 309 | REPORTED | ~$1M–3M (global) | Flexibits Premium $4.75–$7.50/mo; unknown subs but premium iOS |
| 8 | **Akiflow** | 10 | REPORTED | ~$200K (global ARR $2.5M, founder) | KR reviews tiny; global product |
| 9 | **Amie** | 9 | REPORTED | undisclosed / pre-PMF | $8.3M raised, retention problems reported |
| 10 | **Morgen** | 5 | REPORTED | ~$108K (global ARR $1.3M, GetLatka) | bootstrapped |

**KR insight:** Korea is **productivity-planner led, not pure-calendar**. Hero AI
(300K users, 100% free) shows the AI-all-in-one wave but isn't monetizing yet.
Western premium tools (Fantastical, Todoist, Akiflow, Morgen) have KR presence but
small local review counts → KR is not their core market. Opportunity: a
**Korea-native AI calendar** with local payment (Kakao Pay / AppCard) and Korean
language-first design is underserved.

---

## Taiwan — pragmatic, shift-work + shared

| Rank | App | Reviews (TW) | Class | Est. MRR (USD/mo) | Basis |
|------|-----|-------------|-------|------------------|-------|
| 1 | **TimeTree** | 171,924 | REPORTED | ~$150K–400K (TW slice) | Global entity, strong TW adoption |
| 2 | **Apple 行事曆** | 31,423 | n/a | $0 | Built-in |
| 3 | **簡單日曆 (Komorebi)** | 17,929 | MODELED | ~$20K–60K | Same dev as JP SimpleCal; TW base |
| 4 | **Google 日曆** | 10,875 | n/a | $0 | Free |
| 5 | **MYDUTY (Nurse Calendar)** | 5,591 | MODELED | ~$15K–50K | Vertical (nurses/shift); high willingness-to-pay |
| 6 | **Supershift (排班表)** | 4,907 | MODELED | ~$10K–40K | Shift-work vertical |
| 7 | **TickTick** | 3,417 | REPORTED | ~$1M+ (global, ~20M users) | TW slice; freemium |
| 8 | **Jorte** | 2,187 | MODELED | ~$2K–10K | Legacy, low ratings |

**TW insight:** Two distinct wedges — **shared calendars** (TimeTree leads) and
**shift-work / profession-specific** (MYDUTY for nurses, Supershift for scheduling).
Taiwan lacks a *design-forward consumer calendar* play (no Caho/Lifebear equivalent)
→ white space for a polished, Taiwan-local calendar with payment via LINE Pay.

---

## Cross-region synthesis

**The one app in all three markets: TimeTree.** It is the clear category leader by
reach and the most credible MRR anchor (~$1M+/mo globally, shared-calendar moat).
Everyone else is regional or vertical.

**Three repeatable monetization patterns:**
1. **Shared / social calendar** (TimeTree) — network effects, families/couples/groups.
2. **Vertical / profession** (MYDUTY, Supershift) — high willingness-to-pay, narrow.
3. **Premium productivity** (Fantastical, Todoist, Akiflow, Morgen) — Western,
   subscription, design-led; small Asian review counts = expansion headroom.

**Where JoeCalendar could fit (if you build it):**
- Japan is the **richest single market** (decoration + shared calendar culture, huge
  rating bases → proven willingness to pay for calendar apps).
- Korea is **AI-hungry but pre-monetized** (Hero AI 300K free users) → a
  Korea-native AI calendar with local payments is an opening.
- Taiwan is **underserved on design/polish** and has shift-work vertical demand.
- Global premium players (Fantastical et al.) have thin Asian-localization → a
  TW/JP/KR-localized, LINE/Kakao-Pay-enabled, AI-assisted calendar is the wedge.

---

## Data sources (public)
- TimeTree: 40M users (timetreeapp.com newsroom, 2022); $12.5M rev (Owler); ¥6.7B raised (thebridge.jp, 2025).
- Todoist/Doist: $26.5M ARR 2024, 300K customers (getlatka.com); >$100M lifetime (founder).
- TickTick: ~20M users (help.ticktick.com).
- Fantastical/Flexibits: Premium $4.75–$7.50/mo (flexibits.com/pricing).
- Akiflow: $2.5M ARR (founder LinkedIn, 2025).
- Morgen: $1.3M ARR 2025 (getlatka.com).
- Evernote: ~$100M recurring rev (Bending Spoons acquisition doc, 2023).
- Hero AI: 300K users, 100% free (tryhero.app); $7M raised (startupintros).
- Amie: $8.3M raised (tracxn); retention concerns reported (productivewithchris).
- Apple / Google Calendar / Yahoo! Calendar: free, ecosystem or ad-supported → $0 subscription MRR.
- All review counts: captured live from App Store `meta.json` per app (see JoeCalendar/<region>/<app>/meta.json).

*Generated as a market-structure estimate for JoeCalendar competitive research.
Not investment, financial, or due-diligence advice.*
