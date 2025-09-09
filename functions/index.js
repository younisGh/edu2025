// functions/index.js
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");
const { defineSecret } = require("firebase-functions/params");
const { Storage } = require('@google-cloud/storage');
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const { onDocumentCreated, onDocumentWritten } = require("firebase-functions/v2/firestore");
const { RtcRole, RtcTokenBuilder } = require('agora-access-token');

initializeApp();
const storage = new Storage();

// Toggle to enable/disable Agora Recording functions export (to avoid secrets during notification-only deploys)
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

// Callable Function: تُستدعى من Flutter عبر httpsCallable
exports.importYouTubeChannel = onCall(
    {secrets: [YOUTUBE_API_KEY], timeoutSeconds: 540, region: "us-central1"},
    async (request) => {
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

// =============== Agora Cloud Recording ===============
if (ENABLE_AGORA) {
  // Helper to build Agora auth header
  function agoraAuthHeader() {
    const cid = AGORA_CUSTOMER_ID.value();
    const csec = AGORA_CUSTOMER_CERTIFICATE.value();
    const token = Buffer.from(`${cid}:${csec}`).toString('base64');
    return { Authorization: `Basic ${token}` };
  }

  // Start recording for a channel; stores resourceId/sid in live_channels/{channel}.recording
  exports.startAgoraRecording = onCall(
    { secrets: [AGORA_APP_ID, AGORA_CUSTOMER_ID, AGORA_CUSTOMER_CERTIFICATE, RECORDING_VENDOR, RECORDING_REGION, RECORDING_BUCKET, RECORDING_ACCESS_KEY, RECORDING_SECRET_KEY], timeoutSeconds: 120, region: 'us-central1' },
    async (request) => {
      try {
        if (!request.auth) throw new HttpsError('unauthenticated', 'Must be authenticated.');
        const channel = (request.data && request.data.channel) || '';
        const uid = (request.data && request.data.uid) || 1;
        if (!channel) throw new HttpsError('invalid-argument', "Missing 'channel'.");

        const appId = AGORA_APP_ID.value();
        const vendor = Number(RECORDING_VENDOR.value() || 1);
        const region = Number(RECORDING_REGION.value() || 0);
        const bucket = RECORDING_BUCKET.value();
        const accessKey = RECORDING_ACCESS_KEY.value();
        const secretKey = RECORDING_SECRET_KEY.value();
        if (!appId || !bucket || !accessKey || !secretKey) {
          throw new HttpsError('failed-precondition', 'Recording storage secrets are not configured.');
        }

        // 1) Acquire
        const acquireRes = await fetch(`https://api.agora.io/v1/apps/${appId}/cloud_recording/acquire`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', ...agoraAuthHeader() },
          body: JSON.stringify({
            cname: channel,
            uid: String(uid),
            clientRequest: { resourceExpiredHour: 24 }
          })
        });
        if (!acquireRes.ok) throw new HttpsError('internal', `acquire failed: ${acquireRes.status} ${await acquireRes.text()}`);
        const acquireData = await acquireRes.json();
        const resourceId = acquireData.resourceId;
        if (!resourceId) throw new HttpsError('internal', 'Missing resourceId from acquire.');

        // 2) Start
        const startRes = await fetch(`https://api.agora.io/v1/apps/${appId}/cloud_recording/resourceid/${resourceId}/mode/mix/start`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', ...agoraAuthHeader() },
          body: JSON.stringify({
            cname: channel,
            uid: String(uid),
            clientRequest: {
              recordingConfig: {
                maxIdleTime: 30,
                streamTypes: 2,
                channelType: 1,
                videoStreamType: 0,
                transcodingConfig: {
                  height: 720,
                  width: 1280,
                  bitrate: 2000,
                  fps: 24,
                  mixedVideoLayout: 1,
                  backgroundColor: '#000000'
                }
              },
              storageConfig: {
                vendor,
                region,
                bucket,
                accessKey,
                secretKey,
                fileNamePrefix: ['agora', channel, String(Date.now())]
              }
            }
          })
        });
        if (!startRes.ok) throw new HttpsError('internal', `start failed: ${startRes.status} ${await startRes.text()}`);
        const startData = await startRes.json();
        const sid = startData.sid;
        if (!sid) throw new HttpsError('internal', 'Missing sid from start.');

        // Persist resourceId/sid under live_channels/{channel}
        const db = getFirestore();
        await db.collection('live_channels').doc(channel).set({
          recording: {
            resourceId,
            sid,
            startedAt: FieldValue.serverTimestamp(),
          }
        }, { merge: true });

        logger.info(`Recording started for channel=${channel} resourceId=${resourceId} sid=${sid}`);
        return { ok: true, resourceId, sid };
      } catch (error) {
        logger.error('startAgoraRecording error:', error);
        if (error instanceof HttpsError) throw error;
        throw new HttpsError('internal', 'Failed to start recording');
      }
    }
  );

  // Stop recording and create a videos doc with playback URL
  exports.stopAgoraRecording = onCall(
    { secrets: [AGORA_APP_ID, AGORA_CUSTOMER_ID, AGORA_CUSTOMER_CERTIFICATE, RECORDING_BUCKET], timeoutSeconds: 120, region: 'us-central1' },
    async (request) => {
      try {
        if (!request.auth) throw new HttpsError('unauthenticated', 'Must be authenticated.');
        const channel = (request.data && request.data.channel) || '';
        let resourceId = (request.data && request.data.resourceId) || '';
        let sid = (request.data && request.data.sid) || '';
        const title = (request.data && request.data.title) || 'بث مباشر مسجل';
        const description = (request.data && request.data.description) || '';
        const appId = AGORA_APP_ID.value();
        if (!channel || !appId) throw new HttpsError('invalid-argument', 'Missing channel/appId.');

        const db = getFirestore();
        if (!resourceId || !sid) {
          const lc = await db.collection('live_channels').doc(channel).get();
          const rec = (lc.data() && lc.data().recording) || {};
          resourceId = resourceId || rec.resourceId;
          sid = sid || rec.sid;
        }
        if (!resourceId || !sid) throw new HttpsError('failed-precondition', 'Recording identifiers not found.');

        const stopRes = await fetch(`https://api.agora.io/v1/apps/${appId}/cloud_recording/resourceid/${resourceId}/sid/${sid}/mode/mix/stop`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', ...agoraAuthHeader() },
          body: JSON.stringify({ cname: channel, uid: '1', clientRequest: {} })
        });
        if (!stopRes.ok) throw new HttpsError('internal', `stop failed: ${stopRes.status} ${await stopRes.text()}`);
        const stopData = await stopRes.json();

        // Build playback URL from S3 key if present
        const bucket = RECORDING_BUCKET.value();
        let videoUrl = '';
        let s3Key = '';
        try {
          const serverResp = stopData.serverResponse || {};
          let list = serverResp.fileList;
          if (typeof list === 'string') {
            try { list = JSON.parse(list); } catch (_) {}
          }
          if (Array.isArray(list) && list.length > 0) {
            const first = list[0];
            const fileName = first.fileName || first.filename || first.file_name || '';
            if (fileName) {
              s3Key = fileName;
              videoUrl = `https://${bucket}.s3.amazonaws.com/${fileName}`;
            }
          }
        } catch (e) {
          logger.warn('Failed to parse fileList from stop response', e);
        }

        // Optionally copy recording from S3 to Firebase Storage bucket as requested
        let gsUrl = '';
        let httpsDownloadUrl = '';
        try {
          if (videoUrl) {
            // Download from S3 (requires the object to be publicly readable or bucket policy allowing it)
            const s3Resp = await fetch(videoUrl);
            if (!s3Resp.ok) {
              logger.warn(`Failed to fetch S3 object for copying: ${s3Resp.status}`);
            } else {
              const arrayBuffer = await s3Resp.arrayBuffer();
              const buffer = Buffer.from(arrayBuffer);
              const contentType = s3Resp.headers.get('content-type') || 'video/mp4';

              // Destination in Firebase Storage bucket
              const targetBucketName = 'educational-platform-16729.firebasestorage.app';
              const destPath = `recordings/${channel}/${Date.now()}_${s3Key.split('/').pop() || 'recording.mp4'}`;
              const bucketRef = storage.bucket(targetBucketName);
              const fileRef = bucketRef.file(destPath);

              // Add a download token for public URL
              const token = require('crypto').randomUUID();
              await fileRef.save(buffer, {
                metadata: {
                  contentType,
                  metadata: { firebaseStorageDownloadTokens: token },
                }
              });

              gsUrl = `gs://${targetBucketName}/${destPath}`;
              // Standard Firebase Storage download URL format
              const encodedPath = encodeURIComponent(destPath);
              httpsDownloadUrl = `https://firebasestorage.googleapis.com/v0/b/${targetBucketName}/o/${encodedPath}?alt=media&token=${token}`;
            }
          }
        } catch (copyErr) {
          logger.warn('Copy to Firebase Storage failed', copyErr);
        }

        // Create videos doc (aligning with app schema: vodUrl/createdAt/visibility)
        const videoDocRef = db.collection('videos').doc();
        await videoDocRef.set({
          name: title,
          title: title,
          description: description,
          videoUrl: httpsDownloadUrl || videoUrl,
          vodUrl: httpsDownloadUrl || videoUrl,
          thumbnailUrl: '',
          timeAdded: FieldValue.serverTimestamp(),
          createdAt: FieldValue.serverTimestamp(),
          views: 0,
          visibility: 'public',
          source: 'live',
          liveChannel: channel,
          storage: gsUrl ? { gsUrl, downloadUrl: httpsDownloadUrl } : undefined,
          agora: {
            resourceId,
            sid,
            stopResponse: stopData,
          },
        });

        // Clear recording state on channel
        await db.collection('live_channels').doc(channel).set({
          recording: { resourceId: '', sid: '', endedAt: FieldValue.serverTimestamp() }
        }, { merge: true });

        logger.info(`Recording stopped for channel=${channel} sid=${sid} -> video=${videoDocRef.id}`);
        return { ok: true, videoId: videoDocRef.id, videoUrl };
      } catch (error) {
        logger.error('stopAgoraRecording error:', error);
        if (error instanceof HttpsError) throw error;
        throw new HttpsError('internal', 'Failed to stop recording');
      }
    }
  );
}