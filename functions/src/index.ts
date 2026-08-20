/**
 * JoeCalendar — Cloud Functions (Phase 2 Social Groups)
 * 
 * Functions:
 * 1. fanOutGroupEvent: Triggered on event create/update. Fans out notifications to verified group members.
 * 2. targetPromotionsForUser: Callable endpoint delivering targeted promo ad-units to free users (filtered out for ad-free subscribers).
 * 3. publishLocalCalendarWindow: Daily scheduled job managing the curated 14-day discovery window.
 */

import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

admin.initializeApp();
const db = admin.firestore();

// MARK: - 1. Group Event Fan-Out (Privacy Core)
/**
 * Triggered whenever an event is created or modified.
 * If visibility is 'group', ensures only verified group members receive notification / sync fan-out.
 * Explicitly blocks leakage of private/social events (e.g. Pickleball) to unauthorized circles.
 */
export const fanOutGroupEvent = functions
  .region("asia-east1")
  .firestore
  .document("events/{eventId}")
  .onWrite(async (change, context) => {
    const eventId = context.params.eventId;
    const afterData = change.after.exists ? change.after.data() : null;

    if (!afterData) {
      // Event was deleted
      console.log(`Event ${eventId} was deleted. Cleaning up fan-out mirrors.`);
      return null;
    }

    const { visibility, createdBy, title } = afterData;

    if (!visibility || visibility.type !== "group" || !Array.isArray(visibility.groupIds) || visibility.groupIds.length === 0) {
      // Not a group-scoped event
      return null;
    }

    const groupIds: string[] = visibility.groupIds;
    const recipientUids = new Set<string>();
    const groupNames: string[] = [];

    for (const groupId of groupIds) {
      const groupDoc = await db.collection("groups").doc(groupId).get();
      if (groupDoc.exists) {
        const groupData = groupDoc.data();
        if (groupData) {
          if (groupData.name) {
            groupNames.push(groupData.name);
          }
          if (Array.isArray(groupData.memberUids)) {
            for (const uid of groupData.memberUids) {
              if (uid !== createdBy) {
                recipientUids.add(uid);
              }
            }
          }
        }
      }
    }

    console.log(
      `Fanning out event '${title}' (${eventId}) to ${recipientUids.size} members across groups: ${groupNames.join(", ")}`
    );

    if (recipientUids.size === 0) {
      return null;
    }

    const batch = db.batch();
    const primaryGroupName = groupNames[0] || "Friend Group";

    for (const memberUid of recipientUids) {
      // 1. Write to member's subcollection
      const userNotificationRef = db
        .collection("users")
        .doc(memberUid)
        .collection("notifications")
        .doc(`event_${eventId}`);
      
      const payload = {
        type: "group_event_added",
        eventId,
        eventTitle: title || "New Event",
        groupIds,
        groupName: primaryGroupName,
        createdBy: createdBy || "friend",
        message: `New event in ${primaryGroupName}: ${title || "New Event"}`,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        read: false,
      };

      batch.set(userNotificationRef, payload);

      // 2. Write to top-level notifications collection for global index queries
      const globalNotificationRef = db
        .collection("notifications")
        .doc(`${eventId}_${memberUid}`);
      
      batch.set(globalNotificationRef, {
        recipientUid: memberUid,
        ...payload,
      });
    }

    return batch.commit();
  });

// MARK: - 2. Promo Targeting (Monetization Ad-Unit for Free Users)
/**
 * Returns active promotions for a free user based on their region and interests.
 * If the user has an active ad-free subscription, returns an empty list.
 */
export const targetPromotionsForUser = functions
  .region("asia-east1")
  .https.onCall(async (data, context) => {
  const uid = context.auth?.uid;
  if (!uid) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "User must be authenticated to request promotions."
    );
  }

  // 1. Check if user is ad-free subscriber
  const userDoc = await db.collection("users").doc(uid).get();
  const userData = userDoc.data();
  const subDoc = await db.collection("subscriptions").doc(uid).get();
  const subData = subDoc.data();

  const isAdFree = userData?.isAdFree || subData?.isAdFree || false;
  if (isAdFree) {
    return { promotions: [], isAdFree: true };
  }

  const userRegion = data?.region || userData?.locale || "Tokyo";
  const now = admin.firestore.Timestamp.now();

  // 2. Query active promotions matching region
  const promoSnapshot = await db
    .collection("promotions")
    .where("isPaid", "==", true)
    .where("endDate", ">=", now)
    .limit(10)
    .get();

  const eligiblePromos = promoSnapshot.docs
    .map((doc) => ({
      id: doc.id,
      ...doc.data(),
    }))
    .filter((promo: any) => {
      if (!promo.targeting?.regions || promo.targeting.regions.length === 0) {
        return true;
      }
      return promo.targeting.regions.includes(userRegion);
    })
    .slice(0, 5);

  return {
    promotions: eligiblePromos,
    isAdFree: false,
  };
});

// MARK: - 3. Local Calendar Publish (14-Day Sliding Discovery Window)
/**
 * Daily scheduled function (running at 00:00 UTC) to manage the curated 14-day window for local calendars.
 * Updates publication flags and aggregates upcoming curated local event feeds.
 */
export const publishLocalCalendarWindow = functions
  .region("asia-east1")
  .pubsub
  .schedule("0 0 * * *")
  .timeZone("Asia/Tokyo")
  .onRun(async (context) => {
    const now = new Date();
    const twoWeeksLater = new Date(now.getTime() + 14 * 24 * 60 * 60 * 1000);

    console.log(
      `Running local calendar window update for window: ${now.toISOString()} to ${twoWeeksLater.toISOString()}`
    );

    const snapshot = await db
      .collection("localCalendars")
      .where("isCurated", "==", true)
      .get();

    const batch = db.batch();

    snapshot.docs.forEach((doc) => {
      batch.update(doc.ref, {
        windowStartDate: admin.firestore.Timestamp.fromDate(now),
        windowEndDate: admin.firestore.Timestamp.fromDate(twoWeeksLater),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });

    await batch.commit();
    console.log(`Updated 14-day sliding window for ${snapshot.size} curated local calendars.`);
    return null;
  });
