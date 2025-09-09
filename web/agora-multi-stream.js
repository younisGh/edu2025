// Minimal Agora Web SDK bridge for screen sharing (web-only)
// Publishes a separate screen client while keeping camera via Flutter plugin.

window.agoraBridge = (function () {
  const bridge = {};
  let screenClient = null;
  let screenTrack = null;
  let inited = false;
  let _appId = null;
  let _channel = null;
  let _uidScreen = null;
  let _tokenScreen = null;

  bridge.initScreenClient = async function ({ appId, channel, uidScreen, tokenScreen }) {
    _appId = appId; _channel = channel; _uidScreen = uidScreen; _tokenScreen = tokenScreen;
    if (inited) return true;
    if (!window.AgoraRTC) throw new Error('AgoraRTC not loaded');
    screenClient = AgoraRTC.createClient({ mode: 'live', codec: 'vp8' });
    await screenClient.initialize?.(_appId); // legacy API guard
    inited = true;
    return true;
  };

  bridge.startScreenShare = async function () {
    if (!inited) throw new Error('Call initScreenClient first');
    if (!screenClient) throw new Error('screenClient not ready');
    if (screenTrack) return true; // already sharing

    // Use new SDK API
    try {
      await screenClient.setClientRole?.('host');
    } catch (e) {}

    // Join as separate uid for screen
    await screenClient.join(_appId, _channel, _tokenScreen || null, _uidScreen);

    // Create display media
    const stream = await navigator.mediaDevices.getDisplayMedia({
      video: true,
      audio: false
    });
    screenTrack = AgoraRTC.createCustomVideoTrack({ mediaStreamTrack: stream.getVideoTracks()[0] });
    await screenClient.publish([screenTrack]);

    // When display ends
    const [vt] = stream.getVideoTracks();
    vt.addEventListener('ended', async () => {
      try { await bridge.stopScreenShare(); } catch (e) { console.warn(e); }
    });

    return true;
  };

  bridge.stopScreenShare = async function () {
    try {
      if (screenClient && screenTrack) {
        await screenClient.unpublish([screenTrack]);
        try { await screenTrack.stop(); } catch (e) {}
        try { await screenTrack.close?.(); } catch (e) {}
      }
    } finally {
      screenTrack = null;
      try { await screenClient?.leave(); } catch (e) {}
    }
    return true;
  };

  return bridge;
})();
