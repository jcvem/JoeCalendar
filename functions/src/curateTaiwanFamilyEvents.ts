/**
 * JoeCalendar — Local Calendar Auto-Curation (Phase A: Taipei Family Activities)
 * 
 * Ingests Taipei family/parent-child activities, filters to the upcoming 30-day sliding window,
 * maps to CalendarEvent data schema, and idempotently upserts to Firestore.
 */

import * as admin from "firebase-admin";

// MARK: - Configuration & Constants

export const TAIPEI_QINZI_CALENDAR_ID = "taipei_qinzi";
export const WINDOW_DAYS = 30;

export const FAMILY_KEYWORDS = [
  "親子",
  "兒童",
  "親子共學",
  "family",
  "kid",
  "童玩",
  "童話",
  "繪本",
  "幼兒",
  "嬰幼兒",
  "小小",
  "兒童劇",
  "說故事",
  "闖關",
  "野餐",
  "手作",
  "劇團",
  "戲偶",
  "魔法",
  "魔術",
  "遊樂"
];

export const CALENDAR_METADATA = {
  id: TAIPEI_QINZI_CALENDAR_ID,
  title: "臺北 親子活動",
  region: "Taipei",
  category: "親子活動",
  isCurated: true,
  tags: ["親子", "Taipei", "family"],
  colorHex: "#2D5D72",
};

// API Endpoints
export const TAIPEI_TRAVEL_API_URL = "https://www.travel.taipei/open-api/zh-tw/Events/Activity";
export const CULTURE_MOC_API_URL = "https://cloud.culture.tw/frontsite/trans/SearchShowAction.do?method=doFindTypeJ&category=4";

// MARK: - Data Interfaces

export interface NormalizedCuratedEvent {
  externalId: string;
  externalCalendarId: string;
  source: string;
  title: string;
  startDate: Date;
  endDate: Date;
  isAllDay: boolean;
  location: string | null;
  notes: string | null;
  calendarType: "local";
  visibility: {
    type: "public";
    groupIds: string[];
  };
  recurrence: "none";
  syncStatus: "synced";
  createdBy: string;
  colorHex: string;
}

interface TravelTaipeiApiItem {
  id: number | string;
  title?: string;
  description?: string;
  begin?: string;
  end?: string;
  location?: string;
  address?: string;
  url?: string;
  update?: string;
  posted?: string;
  [key: string]: any;
}

interface TravelTaipeiApiResponse {
  total?: number;
  data?: TravelTaipeiApiItem[];
  [key: string]: any;
}

interface CultureTwShowInfo {
  time?: string;
  endTime?: string;
  location?: string;
  locationName?: string;
  onSales?: string;
  price?: string;
  latitude?: string | null;
  longitude?: string | null;
}

interface CultureTwItem {
  UID: string;
  title: string;
  category?: string;
  showInfo?: CultureTwShowInfo[];
  descriptionFilterHtml?: string;
  comment?: string;
  webSales?: string;
  sourceWebPromote?: string;
  startDate?: string;
  endDate?: string;
  [key: string]: any;
}

// MARK: - Filtering Utilities

/**
 * Checks if a string contains any of the family keywords (case-insensitive).
 */
export function matchesFamilyKeywords(text: string): boolean {
  if (!text) return false;
  const lower = text.toLowerCase();
  return FAMILY_KEYWORDS.some((kw) => lower.includes(kw.toLowerCase()));
}

/**
 * Validates whether an event falls within the [now, now + WINDOW_DAYS] window.
 */
export function isWithinWindow(startDate: Date, endDate: Date, now: Date, windowDays: number = WINDOW_DAYS): boolean {
  if (isNaN(startDate.getTime()) || isNaN(endDate.getTime())) {
    return false;
  }
  
  const windowStart = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 0, 0, 0, 0);
  const windowEnd = new Date(windowStart.getTime() + windowDays * 24 * 60 * 60 * 1000);

  // Event must not have ended in the past
  if (endDate < windowStart) {
    return false;
  }

  // Event must start before or on the window end date
  if (startDate > windowEnd) {
    return false;
  }

  return true;
}

/**
 * Parses date string in common Taiwan open data formats:
 * - "YYYY-MM-DD HH:mm:ss"
 * - "YYYY/MM/DD HH:mm:ss"
 * - "YYYY-MM-DD"
 * - "YYYY/MM/DD"
 * - ISO string
 */
export function parseDateString(dateStr?: string | null): Date | null {
  if (!dateStr || typeof dateStr !== "string") return null;
  const trimmed = dateStr.trim();
  if (!trimmed) return null;

  // Replace slashes with dashes for standard ISO parsing
  const normalized = trimmed.replace(/\//g, "-");
  
  // If format is "YYYY-MM-DD HH:mm:ss", format with 'T' and timezone offset
  if (/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/.test(normalized)) {
    // Treat as Asia/Taipei (+08:00)
    const d = new Date(normalized.replace(" ", "T") + "+08:00");
    if (!isNaN(d.getTime())) return d;
  }
  
  if (/^\d{4}-\d{2}-\d{2}$/.test(normalized)) {
    const d = new Date(normalized + "T00:00:00+08:00");
    if (!isNaN(d.getTime())) return d;
  }

  const d = new Date(normalized);
  return isNaN(d.getTime()) ? null : d;
}

// MARK: - Feed Ingestion

/**
 * Fetches events from travel.taipei Open API.
 * Note: If the official endpoint is guarded by Cloudflare WAF bot mitigation (403),
 * logs the warning and returns an empty array to allow fallback gracefully.
 */
export async function fetchTravelTaipeiFeed(): Promise<NormalizedCuratedEvent[]> {
  console.log(`[Curation] Fetching travel.taipei activities from: ${TAIPEI_TRAVEL_API_URL}`);
  
  try {
    const response = await fetch(TAIPEI_TRAVEL_API_URL, {
      method: "GET",
      headers: {
        "Accept": "application/json",
        "User-Agent": "JoeCalendar-Curator/1.0 (asia-east1; Node.js 20)",
      },
    });

    if (!response.ok) {
      console.warn(`[Curation] travel.taipei returned HTTP status ${response.status} (${response.statusText}).`);
      return [];
    }

    const contentType = response.headers.get("content-type") || "";
    if (!contentType.includes("application/json")) {
      console.warn(`[Curation] travel.taipei returned non-JSON content-type: ${contentType}. Likely WAF challenge.`);
      return [];
    }

    const json = (await response.json()) as TravelTaipeiApiResponse;
    const items = json.data || [];
    console.log(`[Curation] travel.taipei returned ${items.length} raw items (reported total: ${json.total ?? items.length}).`);

    const results: NormalizedCuratedEvent[] = [];

    for (const item of items) {
      if (!item.id || !item.title) continue;

      const title = item.title.trim();
      const desc = item.description || "";
      const fullText = `${title} ${desc} ${item.location || ""}`;

      // Keyword match
      if (!matchesFamilyKeywords(fullText)) {
        continue;
      }

      const startDate = parseDateString(item.begin);
      const endDate = parseDateString(item.end) || startDate;

      if (!startDate || !endDate) continue;

      const originId = String(item.id);
      const externalId = `travel.taipei_${originId}`;
      const location = item.location || item.address || "Taipei, Taiwan";
      const notes = item.url || (desc.length > 500 ? desc.slice(0, 500) + "..." : desc) || null;

      // Determine isAllDay
      const isAllDay = (item.begin?.includes("00:00:00") && item.end?.includes("23:59:59")) || false;

      results.push({
        externalId,
        externalCalendarId: TAIPEI_QINZI_CALENDAR_ID,
        source: "travel.taipei",
        title,
        startDate,
        endDate,
        isAllDay,
        location,
        notes,
        calendarType: "local",
        visibility: { type: "public", groupIds: [] },
        recurrence: "none",
        syncStatus: "synced",
        createdBy: "system_curator",
        colorHex: CALENDAR_METADATA.colorHex,
      });
    }

    return results;
  } catch (error: any) {
    console.error(`[Curation] Failed to fetch travel.taipei feed:`, error?.message || error);
    return [];
  }
}

/**
 * Fetches parent-child cultural events from Ministry of Culture (文化部) Open API (Category 4: 親子活動).
 * Filters to venues located in Taipei / New Taipei.
 */
export async function fetchCultureTwQinziFeed(): Promise<NormalizedCuratedEvent[]> {
  console.log(`[Curation] Fetching culture.tw 親子活動 from: ${CULTURE_MOC_API_URL}`);

  try {
    const response = await fetch(CULTURE_MOC_API_URL, {
      method: "GET",
      headers: {
        "Accept": "application/json",
        "User-Agent": "JoeCalendar-Curator/1.0 (asia-east1; Node.js 20)",
      },
    });

    if (!response.ok) {
      console.warn(`[Curation] culture.tw returned HTTP status ${response.status} (${response.statusText}).`);
      return [];
    }

    const items = (await response.json()) as CultureTwItem[];
    if (!Array.isArray(items)) {
      console.warn(`[Curation] culture.tw returned unexpected payload structure.`);
      return [];
    }

    console.log(`[Curation] culture.tw returned ${items.length} raw parent-child activities.`);
    const results: NormalizedCuratedEvent[] = [];

    for (const item of items) {
      if (!item.UID || !item.title) continue;

      const title = item.title.trim();
      const showInfos = Array.isArray(item.showInfo) ? item.showInfo : [];
      const notes = item.webSales || item.sourceWebPromote || item.descriptionFilterHtml || item.comment || null;

      // Filter shows by Taipei / New Taipei region
      const taipeiShows = showInfos.filter((show) => {
        const loc = `${show.location || ""} ${show.locationName || ""}`;
        return loc.includes("臺北") || loc.includes("台北") || loc.includes("新北");
      });

      if (taipeiShows.length === 0) {
        continue;
      }

      // If multiple show times exist, create an event entry per unique show session
      taipeiShows.forEach((show, index) => {
        const start = parseDateString(show.time) || parseDateString(item.startDate);
        const end = parseDateString(show.endTime) || parseDateString(show.time) || parseDateString(item.endDate) || start;

        if (!start || !end) return;

        const originId = taipeiShows.length > 1 ? `${item.UID}_${index}` : item.UID;
        const externalId = `culture.tw_${originId}`;
        const venue = [show.locationName, show.location].filter(Boolean).join(" - ") || "Taipei, Taiwan";

        results.push({
          externalId,
          externalCalendarId: TAIPEI_QINZI_CALENDAR_ID,
          source: "culture.tw",
          title,
          startDate: start,
          endDate: end,
          isAllDay: false,
          location: venue,
          notes,
          calendarType: "local",
          visibility: { type: "public", groupIds: [] },
          recurrence: "none",
          syncStatus: "synced",
          createdBy: "system_curator",
          colorHex: CALENDAR_METADATA.colorHex,
        });
      });
    }

    return results;
  } catch (error: any) {
    console.error(`[Curation] Failed to fetch culture.tw feed:`, error?.message || error);
    return [];
  }
}

// MARK: - Firestore Sync Pipeline

/**
 * Ensures the parent curated calendar doc exists in `localCalendars/{calendarId}`
 * and refreshes its 30-day sliding window.
 */
export async function ensureCuratedCalendarDoc(
  db: admin.firestore.Firestore,
  now: Date,
  windowDays: number = WINDOW_DAYS
): Promise<void> {
  const calRef = db.collection("localCalendars").doc(TAIPEI_QINZI_CALENDAR_ID);
  const calDoc = await calRef.get();

  const windowStartDate = admin.firestore.Timestamp.fromDate(now);
  const windowEndDate = admin.firestore.Timestamp.fromDate(
    new Date(now.getTime() + windowDays * 24 * 60 * 60 * 1000)
  );

  if (!calDoc.exists) {
    console.log(`[Curation] Creating curated calendar doc: localCalendars/${TAIPEI_QINZI_CALENDAR_ID}`);
    await calRef.set({
      id: TAIPEI_QINZI_CALENDAR_ID,
      title: CALENDAR_METADATA.title,
      description: "臺北市及周邊嚴選親子活動、兒童劇團、手作體驗與展演年曆。",
      region: CALENDAR_METADATA.region,
      category: CALENDAR_METADATA.category,
      isCurated: true,
      tags: CALENDAR_METADATA.tags,
      colorHex: CALENDAR_METADATA.colorHex,
      windowStartDate,
      windowEndDate,
      subscriberCount: 0,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  } else {
    console.log(`[Curation] Updating 30-day sliding window on localCalendars/${TAIPEI_QINZI_CALENDAR_ID}`);
    await calRef.set(
      {
        title: CALENDAR_METADATA.title,
        region: CALENDAR_METADATA.region,
        category: CALENDAR_METADATA.category,
        isCurated: true,
        tags: CALENDAR_METADATA.tags,
        colorHex: CALENDAR_METADATA.colorHex,
        windowStartDate,
        windowEndDate,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  }
}

/**
 * Upserts curated events into `localCalendarEvents/{externalId}`.
 * Performs idempotent diffing to skip unchanged records and minimize writes.
 */
export async function upsertCuratedEvents(
  db: admin.firestore.Firestore,
  events: NormalizedCuratedEvent[]
): Promise<{ upsertedCount: number; skippedCount: number }> {
  if (events.length === 0) {
    return { upsertedCount: 0, skippedCount: 0 };
  }

  let upsertedCount = 0;
  let skippedCount = 0;

  // Chunk events into batches of 400 (Firestore max 500)
  const CHUNK_SIZE = 400;
  for (let i = 0; i < events.length; i += CHUNK_SIZE) {
    const chunk = events.slice(i, i + CHUNK_SIZE);
    const batch = db.batch();
    let batchHasOperations = false;

    // Fetch existing docs in this chunk to diff
    const docRefs = chunk.map((e) => db.collection("localCalendarEvents").doc(e.externalId));
    const snapshots = await db.getAll(...docRefs);

    for (let j = 0; j < chunk.length; j++) {
      const event = chunk[j];
      const snapshot = snapshots[j];
      const docRef = docRefs[j];

      const startTimestamp = admin.firestore.Timestamp.fromDate(event.startDate);
      const endTimestamp = admin.firestore.Timestamp.fromDate(event.endDate);

      if (snapshot.exists) {
        const data = snapshot.data();
        // Check if essential fields are unchanged
        const isSameTitle = data?.title === event.title;
        const isSameLocation = data?.location === event.location;
        const isSameNotes = data?.notes === event.notes;
        const isSameStart = (data?.startDate as admin.firestore.Timestamp)?.toMillis() === startTimestamp.toMillis();
        const isSameEnd = (data?.endDate as admin.firestore.Timestamp)?.toMillis() === endTimestamp.toMillis();

        if (isSameTitle && isSameLocation && isSameNotes && isSameStart && isSameEnd) {
          skippedCount++;
          continue;
        }
      }

      const payload: Record<string, any> = {
        id: event.externalId,
        title: event.title,
        startDate: startTimestamp,
        endDate: endTimestamp,
        isAllDay: event.isAllDay,
        location: event.location,
        notes: event.notes,
        calendarType: event.calendarType,
        externalCalendarId: event.externalCalendarId,
        externalId: event.externalId,
        source: event.source,
        visibility: event.visibility,
        recurrence: event.recurrence,
        syncStatus: event.syncStatus,
        createdBy: event.createdBy,
        colorHex: event.colorHex,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      if (!snapshot.exists) {
        payload.createdAt = admin.firestore.FieldValue.serverTimestamp();
      }

      batch.set(docRef, payload, { merge: true });
      batchHasOperations = true;
      upsertedCount++;
    }

    if (batchHasOperations) {
      await batch.commit();
    }
  }

  return { upsertedCount, skippedCount };
}

/**
 * Main execution handler for curateTaiwanFamilyEvents.
 */
export async function runCurateTaiwanFamilyEvents(
  db: admin.firestore.Firestore
): Promise<{ totalFetched: number; validEvents: number; upserted: number; skipped: number }> {
  const now = new Date();
  console.log(`[Curation] Starting Taiwan Family Events curation job at ${now.toISOString()}`);

  // 1. Ensure parent curated calendar document exists and window is refreshed
  await ensureCuratedCalendarDoc(db, now, WINDOW_DAYS);

  // 2. Fetch feeds (travel.taipei + culture.tw)
  const [taipeiEvents, cultureEvents] = await Promise.all([
    fetchTravelTaipeiFeed(),
    fetchCultureTwQinziFeed(),
  ]);

  const allEvents = [...taipeiEvents, ...cultureEvents];
  console.log(`[Curation] Total fetched events matching family keywords: ${allEvents.length} (Taipei: ${taipeiEvents.length}, Culture.tw: ${cultureEvents.length})`);

  // 3. Filter to next 30-day window
  const windowEvents = allEvents.filter((ev) => isWithinWindow(ev.startDate, ev.endDate, now, WINDOW_DAYS));
  console.log(`[Curation] Events within upcoming ${WINDOW_DAYS}-day window: ${windowEvents.length}`);

  // 4. Idempotently upsert to Firestore
  const { upsertedCount, skippedCount } = await upsertCuratedEvents(db, windowEvents);
  console.log(`[Curation] Completed: ${upsertedCount} events upserted/updated, ${skippedCount} events skipped (unchanged).`);

  return {
    totalFetched: allEvents.length,
    validEvents: windowEvents.length,
    upserted: upsertedCount,
    skipped: skippedCount,
  };
}
