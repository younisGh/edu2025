// functions/index.js
const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");
const { defineSecret } = require("firebase-functions/params");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getAuth } = require("firebase-admin/auth");
const { getMessaging } = require("firebase-admin/messaging");
const { onDocumentCreated, onDocumentWritten } = require("firebase-functions/v2/firestore");
const { RtcRole, RtcTokenBuilder } = require('agora-access-token');

initializeApp();

// No cloud recording: disable any recording-related exports (section removed below)
const ENABLE_AGORA = false;

// خزّن مفتاح YouTube API كسِر باسم YOUTUBE_API_KEY (ستضبطه بالـ CLI)
const YOUTUBE_API_KEY = defineSecret("YOUTUBE_API_KEY");
// Secrets for Agora dynamic token generation
const AGORA_APP_ID = defineSecret('AGORA_APP_ID');
const AGORA_APP_CERTIFICATE = defineSecret('AGORA_APP_CERTIFICATE');

// ===================== Agora RTC Token (Callable) =====================
// Generate a fresh RTC token for joining a channel (web/mobile)
// Request data: { channel: string, uid?: number, role?: 'broadcaster'|'audience', expireSeconds?: number }
exports.getAgoraRtcToken = onCall({
  region: 'us-central1',
  secrets: [AGORA_APP_ID, AGORA_APP_CERTIFICATE],
  cors: true,
}, async (request) => {
  try {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Must be authenticated.');
    const channel = (request.data && String(request.data.channel || '').trim());
    if (!channel) throw new HttpsError('invalid-argument', "Missing 'channel'.");

    // Allow client to suggest uid or default to 0 (Agora can assign locally for SDKs)
    const uid = Number.isFinite(Number(request.data && request.data.uid)) ? Number(request.data.uid) : 0;
    const roleStr = (request.data && String(request.data.role || 'audience')).toLowerCase();
    const role = roleStr === 'broadcaster' ? RtcRole.PUBLISHER : RtcRole.SUBSCRIBER;
    const expireSeconds = Number.isFinite(Number(request.data && request.data.expireSeconds)) ? Number(request.data.expireSeconds) : 3600; // 1h default

    const appId = AGORA_APP_ID.value();
    const appCertificate = AGORA_APP_CERTIFICATE.value();
    if (!appId || !appCertificate) {
      throw new HttpsError('failed-precondition', 'Agora secrets are not configured.');
    }

    const currentTs = Math.floor(Date.now() / 1000);
    const privilegeExpiredTs = currentTs + expireSeconds;

    // Build token for RTC (communication/live)
    const token = RtcTokenBuilder.buildTokenWithUid(
      appId,
      appCertificate,
      channel,
      uid,
      role,
      privilegeExpiredTs
    );

    return {
      ok: true,
      token,
      appId, // optional: client may already have it
      channel,
      uid,
      expiresAt: privilegeExpiredTs,
    };
  } catch (err) {
    if (err instanceof HttpsError) throw err;
    logger.error('getAgoraRtcToken error', err);
    throw new HttpsError('internal', 'Failed to create Agora RTC token');
  }
});

// جلب الـ Uploads Playlist ID للقناة
async function getUploadsPlaylistId(channelId, apiKey) {
  const url = new URL("https://www.googleapis.com/youtube/v3/channels");
  url.searchParams.set("part", "contentDetails");
  url.searchParams.set("id", channelId);
  url.searchParams.set("key", apiKey);

  const res = await fetch(url);
  if (!res.ok) {
    throw new Error(`channels.list failed: ${res.status} ${await res.text()}`);
  }
  const data = await res.json();
  const item = data.items && data.items[0];
  if (!item || !item.contentDetails) {
    throw new Error("Channel not found or missing contentDetails");
  }
  return item.contentDetails.relatedPlaylists.uploads;
}

// مولّد يكرّر على كل عناصر الـ playlist مع الترقيم
async function* iteratePlaylistItems(playlistId, apiKey) {
  let pageToken = "";
  while (true) {
    const url = new URL("https://www.googleapis.com/youtube/v3/playlistItems");
    url.searchParams.set("part", "snippet");
    url.searchParams.set("playlistId", playlistId);
    url.searchParams.set("maxResults", "50");
    if (pageToken) url.searchParams.set("pageToken", pageToken);
    url.searchParams.set("key", apiKey);

    const res = await fetch(url);
    if (!res.ok) {
      throw new Error(`playlistItems.list failed: ${res.status} ${await res.text()}`);
    }
    const data = await res.json();
    for (const item of data.items || []) yield item;

    pageToken = data.nextPageToken || "";
    if (!pageToken) break;
  }
}

// Callable Function: list channel videos (metadata only, no writes)
exports.listYouTubeChannelVideos = onCall({ secrets: [YOUTUBE_API_KEY], timeoutSeconds: 300, region: 'us-central1', cors: true }, async (request) => {
  try {
    if (!request.auth) throw new HttpsError('unauthenticated', 'The function must be called while authenticated.');
    const channelId = (request.data && String(request.data.channelId || '').trim());
    if (!channelId) throw new HttpsError('invalid-argument', "Missing 'channelId'.");
    const apiKey = YOUTUBE_API_KEY.value();
    if (!apiKey) throw new HttpsError('failed-precondition', 'The YouTube API key is not configured.');

    const uploadsPlaylistId = await getUploadsPlaylistId(channelId, apiKey);
    const items = [];
    for await (const item of iteratePlaylistItems(uploadsPlaylistId, apiKey)) {
      const sn = item.snippet;
      if (!sn) continue;
      const videoId = sn.resourceId && sn.resourceId.videoId;
      if (!videoId) continue;
      const title = sn.title || '';
      const description = sn.description || '';
      const publishedAt = sn.publishedAt || null;
      const videoUrl = `https://www.youtube.com/watch?v=${videoId}`;
      const thumbs = sn.thumbnails || {};
      const thumbnailUrl = (thumbs.maxres && thumbs.maxres.url) ||
                           (thumbs.high && thumbs.high.url) ||
                           (thumbs.medium && thumbs.medium.url) ||
                           (thumbs.default && thumbs.default.url) ||
                           `https://img.youtube.com/vi/${videoId}/hqdefault.jpg`;
      items.push({ videoId, title, description, videoUrl, thumbnailUrl, publishedAt });
    }
    return { ok: true, items };
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    logger.error('listYouTubeChannelVideos error', error);
    throw new HttpsError('internal', 'Failed to list channel videos');
  }
});

// Callable Function: تُستدعى من Flutter عبر httpsCallable
exports.importYouTubeChannel = onCall({ secrets: [YOUTUBE_API_KEY], timeoutSeconds: 540, region: "us-central1", cors: true }, async (request) => {
        try {
        // تشترط مصادقة المستخدم
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "The function must be called while authenticated.");
        }

        const channelId = request.data.channelId;
        if (!channelId || typeof channelId !== 'string') {
            throw new HttpsError("invalid-argument", "The function must be called with a 'channelId' string argument.");
        }

        const apiKey = YOUTUBE_API_KEY.value();
        if (!apiKey) {
            logger.error("YouTube API key is not available in secret manager.");
            throw new HttpsError("failed-precondition", "The YouTube API key is not configured.");
        }

        const db = getFirestore();
        const uploadsPlaylistId = await getUploadsPlaylistId(channelId, apiKey);

        let imported = 0;
        let skipped = 0;

        for await (const item of iteratePlaylistItems(uploadsPlaylistId, apiKey)) {
            const sn = item.snippet;
            if (!sn) continue;

            const videoId = sn.resourceId && sn.resourceId.videoId;
            if (!videoId) continue;

            // منع التكرار: نستخدم معرف ثابت للمستند
            const docId = `yt_${videoId}`;
            const docRef = db.collection("videos").doc(docId);
            const docSnap = await docRef.get();
            if (docSnap.exists) {
                skipped++;
                continue;
            }

            const title = sn.title || "";
            const description = sn.description || "";
            const publishedAt = sn.publishedAt || null;
            const videoUrl = `https://www.youtube.com/watch?v=${videoId}`;

            const thumbs = sn.thumbnails || {};
            const thumbUrl =
                (thumbs.maxres && thumbs.maxres.url) ||
                (thumbs.high && thumbs.high.url) ||
                (thumbs.medium && thumbs.medium.url) ||
                (thumbs.default && thumbs.default.url) ||
                `https://img.youtube.com/vi/${videoId}/hqdefault.jpg`;

            await docRef.set({
                name: title,
                description: description,
                videoUrl: videoUrl,
                thumbnailUrl: thumbUrl,
                timeAdded: publishedAt ? new Date(publishedAt) : FieldValue.serverTimestamp(),
                videoId: videoId,
                source: "youtube",
            });

            imported++;
        }

        logger.info(`Import finished for channel ${channelId}. Imported: ${imported}, Skipped: ${skipped}`);
        return { ok: true, imported, skipped };
    } catch (error) {
        logger.error(`Error importing YouTube channel ${request.data.channelId || 'unknown'}:`, error);

        if (error instanceof HttpsError) {
            throw error; // Re-throw HttpsError directly
        }

        // Include underlying error message for easier debugging on client
        const msg = (error && (error.message || String(error))) || 'An unexpected error occurred while importing videos.';
        throw new HttpsError("internal", msg);
    }
  }
);

// ===================== Notifications (FCM + Firestore) =====================
// Helper: fetch all target user IDs for broadcast; for MVP, fetch all users collection
async function getAllUserIds() {
  const db = getFirestore();
  const snap = await db.collection('users').select().get();
  return snap.docs.map((d) => d.id);
}

// Helper: write per-user notification docs
async function writeUserNotifications(userIds, notification) {
  const db = getFirestore();
  const batchSize = 400; // chunk writes to avoid huge batches
  for (let i = 0; i < userIds.length; i += batchSize) {
    const chunk = userIds.slice(i, i + batchSize);
    const batch = db.batch();
    for (const uid of chunk) {
      const ref = db.collection('users').doc(uid).collection('notifications').doc();
      batch.set(ref, {
        title: notification.title || '',
        body: notification.body || '',
        type: notification.type || 'general',
        data: notification.data || {},
        from: notification.from || 'system',
        broadcast: !!notification.broadcast,
        createdAt: FieldValue.serverTimestamp(),
        read: false,
      });
    }
    await batch.commit();
  }
}

// Helper: send FCM to user tokens saved at users/{uid}.fcmTokens: []
async function sendFcmToUsers(userIds, fcmPayload) {
  const db = getFirestore();
  const messaging = getMessaging();
  // Collect tokens
  const tokens = [];
  const docs = await db.getAll(...userIds.map((uid) => db.collection('users').doc(uid)));
  for (const doc of docs) {
    const arr = (doc.data() && doc.data().fcmTokens) || [];
    if (Array.isArray(arr)) {
      for (const t of arr) {
        if (typeof t === 'string' && t.trim()) tokens.push(t.trim());
      }
    }
  }
  if (tokens.length === 0) return { sent: 0 };
  // FCM multicast send (chunk by 500)
  let sent = 0;
  for (let i = 0; i < tokens.length; i += 500) {
    const chunk = tokens.slice(i, i + 500);
    const res = await messaging.sendEachForMulticast({
      tokens: chunk,
      notification: {
        title: fcmPayload.title || '',
        body: fcmPayload.body || '',
      },
      data: fcmPayload.data || {},
    });
    sent += (res.successCount || 0);
  }
  return { sent };
}

// Callable: Admin sends notification to a single user or broadcast to all users
exports.sendAdminNotification = onCall({ region: 'asia-northeast1', cors: true }, async (request) => {
  try {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Must be authenticated.');
    const callerUid = request.auth.uid;
    const db = getFirestore();
    const callerDoc = await db.collection('users').doc(callerUid).get();
    const isAdmin = !!(callerDoc.data() && (callerDoc.data().isAdmin === true));
    if (!isAdmin) throw new HttpsError('permission-denied', 'Admin only.');

    const { title, body, data, targetUid, broadcast } = request.data || {};
    if (!title || !body) throw new HttpsError('invalid-argument', 'Missing title/body.');

    let userIds = [];
    if (broadcast === true) {
      userIds = await getAllUserIds();
    } else if (typeof targetUid === 'string' && targetUid) {
      userIds = [targetUid];
    } else {
      throw new HttpsError('invalid-argument', 'Provide targetUid or set broadcast=true');
    }

    const notification = { title, body, data: data || {}, type: 'admin', from: callerUid, broadcast: !!broadcast };
    await writeUserNotifications(userIds, notification);
    const sendRes = await sendFcmToUsers(userIds, { title, body, data: (data || {}) });
    return { ok: true, usersNotified: userIds.length, fcmSent: sendRes.sent };
  } catch (err) {
    if (err instanceof HttpsError) throw err;
    logger.error('sendAdminNotification error', err);
    throw new HttpsError('internal', 'Failed to send admin notification');
  }
});

// Trigger: on new video document -> notify all users
exports.onVideoCreatedNotify = onDocumentCreated({ region: 'asia-northeast1', document: 'videos/{videoId}' }, async (event) => {
  try {
    const data = event.data && event.data.data();
    if (!data) return;
    const title = (data.name || data.title || 'فيديو جديد');
    const body = (data.description || 'تمت إضافة فيديو جديد');
    const payload = { title, body, data: { type: 'video', videoId: event.params.videoId || '' } };
    const users = await getAllUserIds();
    await writeUserNotifications(users, { ...payload, type: 'video', broadcast: true, from: 'system' });
    await sendFcmToUsers(users, payload);
  } catch (e) {
    logger.error('onVideoCreatedNotify error', e);
  }
});

// Trigger: when live channel status becomes 'live' -> notify all users
exports.onLiveStatusChangeNotify = onDocumentWritten({ region: 'asia-northeast1', document: 'live_channels/{channel}' }, async (event) => {
  try {
    const before = event.data && event.data.before && event.data.before.data();
    const after = event.data && event.data.after && event.data.after.data();
    if (!after) return;
    const prevStatus = (before && before.status) || '';
    const currStatus = after.status || '';
    if (prevStatus === 'live' && currStatus === 'live') return; // no change
    if (currStatus !== 'live') return;

    const channel = event.params.channel || '';
    const title = 'بدء بث مباشر الآن';
    const body = `انضم الآن إلى البث المباشر (${channel})`;
    const payload = { title, body, data: { type: 'live', channel } };
    const users = await getAllUserIds();
    await writeUserNotifications(users, { ...payload, type: 'live', broadcast: true, from: 'system' });
    await sendFcmToUsers(users, payload);
  } catch (e) {
    logger.error('onLiveStatusChangeNotify error', e);
  }
});

// ===================== User Management (Admin) =====================
// Callable: Delete a user by UID from Firebase Authentication and Firestore users collection
exports.deleteUserByUid = onCall({ region: 'us-central1', cors: true }, async (request) => {
  try {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Must be authenticated.');
    const callerUid = request.auth.uid;
    const db = getFirestore();
    const callerDoc = await db.collection('users').doc(callerUid).get();
    const isAdmin = !!(callerDoc.data() && (callerDoc.data().isAdmin === true));
    if (!isAdmin) throw new HttpsError('permission-denied', 'Admin only.');

    const uid = (request.data && String(request.data.uid || '').trim());
    if (!uid) throw new HttpsError('invalid-argument', "Missing 'uid'.");

    // Delete from Firebase Authentication
    await getAuth().deleteUser(uid).catch((err) => {
      // If user does not exist in Auth, continue to cleanup Firestore
      if (err && err.code !== 'auth/user-not-found') throw err;
    });

    // Delete Firestore user document
    await db.collection('users').doc(uid).delete().catch(() => {});

    // Optional: cleanup user notifications subcollection (best-effort)
    try {
      const notifCol = db.collection('users').doc(uid).collection('notifications');
      const notifSnap = await notifCol.get();
      const batchSize = 400;
      for (let i = 0; i < notifSnap.docs.length; i += batchSize) {
        const chunk = notifSnap.docs.slice(i, i + batchSize);
        const batch = db.batch();
        for (const d of chunk) batch.delete(d.ref);
        await batch.commit();
      }
    } catch (_) { /* ignore */ }

    return { ok: true };
  } catch (err) {
    if (err instanceof HttpsError) throw err;
    logger.error('deleteUserByUid error', err);
    throw new HttpsError('internal', 'Failed to delete user');
  }
});

// Cloud recording endpoints removed (local-only recording)