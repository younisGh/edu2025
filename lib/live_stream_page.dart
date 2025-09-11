import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
// Conditional import: real web implementation on web, stub elsewhere
import 'web_recording/web_local_recorder_stub.dart'
    if (dart.library.html) 'web_recording/web_local_recorder_web.dart';
// Screen share bridge (web-only)
import 'web_stream/screen_share_stub.dart'
    if (dart.library.html) 'web_stream/screen_share_web.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:educational_platform/utils/typography.dart';

const appId = "8e5303f31e2246e2b0851ad8b39979d7";
// Token will be fetched dynamically from Firebase Function `getAgoraRtcToken`
// Leave empty here to avoid using expired hardcoded tokens
const token = "";
const channel = "edu";

class LiveStreamPage extends StatefulWidget {
  const LiveStreamPage({super.key});

  @override
  State<LiveStreamPage> createState() => _LiveStreamPageState();
}

class _LiveStreamPageState extends State<LiveStreamPage> {
  // int? _remoteUid; // Replaced by _remoteUids
  final List<int> _remoteUids = []; // To store multiple remote user uids
  bool _localUserJoined = false;
  late RtcEngine _engine;
  bool _isMicMuted = false;
  bool _isCameraDisabled = false;
  bool _showParticipantList = false; // To toggle participant list visibility
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _participantsSub;
  final Map<int, String> _participantNames = {};
  bool _isCheckingAdmin = true;
  bool _isAdmin = false;
  bool _showComments = false; // default: hidden until toggled
  final TextEditingController _commentCtrl = TextEditingController();
  final FocusNode _commentFocus = FocusNode();
  String? _replyToId;
  String? _replyToName;
  double _commentsHeight = 160; // adjustable comments panel height
  String _liveStatus = 'live'; // live | paused | ended
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _statusSub;
  // Local recording (screen + mic) via Android native
  static const MethodChannel _localRecChannel = MethodChannel(
    'local_recording',
  );
  bool _isLocalRecording = false;
  // Web-only recorder
  WebLocalRecorder? _webRecorder;

  bool _hasJoined = false; // join guard

  // Web screen sharing
  ScreenShareBridge? _screenShare;
  bool _isScreenSharing = false;

  String _initialsFromName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'م';
    final parts = trimmed.split(RegExp(r'\s+'));
    final first = parts.isNotEmpty && parts[0].isNotEmpty ? parts[0][0] : '';
    final second = parts.length > 1 && parts[1].isNotEmpty ? parts[1][0] : '';
    final initials = (first + second).trim();
    return initials.isEmpty ? 'م' : initials;
  }

  Future<void> _togglePause() async {
    try {
      final newStatus = _liveStatus == 'paused' ? 'live' : 'paused';
      await FirebaseFirestore.instance
          .collection('live_channels')
          .doc(channel)
          .set({'status': newStatus}, SetOptions(merge: true));
      // Local feedback only on non-web (engine available)
      if (!kIsWeb) {
        final pause = newStatus == 'paused';
        await _engine.muteLocalAudioStream(pause);
        await _engine.enableLocalVideo(!pause);
        if (pause) {
          await _engine.stopPreview();
        } else {
          await _engine.startPreview();
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر تغيير حالة البث: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _endLive() async {
    try {
      await FirebaseFirestore.instance
          .collection('live_channels')
          .doc(channel)
          .set({
            'status': 'ended',
            'endedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      // Leave channel gracefully where applicable
      try {
        await _engine.leaveChannel();
      } catch (_) {}
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم إنهاء البث'),
          backgroundColor: Colors.orange,
        ),
      );
      // Navigate back to home (root)
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر إنهاء البث: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _logAuthState([String context = '']) {
    final u = FirebaseAuth.instance.currentUser;
    debugPrint(
      '[AUTH${context.isNotEmpty ? ' $context' : ''}] user=${u?.uid ?? 'null'}',
    );
  }

  // Fetch token for a specific uid (used for screen share client)
  Future<String> _fetchAgoraTokenFor({
    required String role,
    required int uid,
  }) async {
    _logAuthState('before _fetchAgoraTokenFor');
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('يجب تسجيل الدخول قبل طلب التوكن');
    }
    // Ensure fresh ID token before calling callable
    await user.getIdToken(true);
    debugPrint('[CALLABLE] getAgoraRtcToken (for uid=$uid, role=$role)');
    final callable = FirebaseFunctions.instanceFor(
      region: 'us-central1',
    ).httpsCallable('getAgoraRtcToken');
    final res = await callable.call({
      'channel': channel,
      'uid': uid,
      'role': role,
      'expireSeconds': 3600,
    });
    final data = res.data as Map;
    final tok = (data['token'] ?? '').toString();
    if (tok.isEmpty) throw Exception('Returned empty token for uid');
    debugPrint('[CALLABLE] getAgoraRtcToken success (uid=$uid)');
    return tok;
  }

  // ============ Web Screen Share (secondary publisher) ============
  Future<void> _startScreenShareWeb() async {
    if (!kIsWeb) return;
    try {
      final ctx = context;
      _screenShare ??= ScreenShareBridge();
      // Use a dedicated uid for the screen client (must be different from camera uid)
      const int screenUid = 1001;
      final token = await _fetchAgoraTokenFor(
        role: 'broadcaster',
        uid: screenUid,
      );
      await _screenShare!.init(
        appId: appId,
        channel: channel,
        uidScreen: screenUid,
        tokenScreen: token,
      );
      await _screenShare!.start();
      if (ctx.mounted) setState(() => _isScreenSharing = true);
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(
          content: Text('بدأت مشاركة الشاشة (ويب)'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      final ctx = context;
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text('تعذر بدء مشاركة الشاشة: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _stopScreenShareWeb() async {
    if (!kIsWeb) return;
    try {
      final ctx = context;
      if (_screenShare != null) {
        await _screenShare!.stop();
      }
      if (ctx.mounted) setState(() => _isScreenSharing = false);
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(
          content: Text('تم إيقاف مشاركة الشاشة'),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      final ctx = context;
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text('تعذر إيقاف مشاركة الشاشة: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _joinChannelAsAudience() async {
    try {
      final newToken = await _fetchAgoraToken(role: 'audience');
      await _engine.joinChannel(
        token: newToken,
        channelId: channel,
        uid: 0,
        options: const ChannelMediaOptions(),
      );
      _hasJoined = true;
    } catch (e) {
      debugPrint('Audience failed to join: $e');
    }
  }

  Future<String?> _resolvePhotoUrl(String? url) async {
    try {
      if (url == null || url.isEmpty) return null;
      if (url.startsWith('gs://')) {
        final ref = FirebaseStorage.instance.refFromURL(url);
        return await ref.getDownloadURL();
      }
      return url;
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _guardAndInit();
  }

  Future<void> _guardAndInit() async {
    try {
      _logAuthState('enter _guardAndInit');
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _denyAccess('يجب تسجيل الدخول للوصول إلى صفحة البث.');
        return;
      }
      Map<String, dynamic>? data;
      try {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        data = snap.data();
      } catch (e, st) {
        debugPrint('[GUARD] failed to load user doc: $e\n$st');
        _denyAccess('تعذر تحميل صلاحيات المستخدم: $e');
        return;
      }
      final roleVal = (data?['role'] ?? '').toString();
      final isAdminVal = data?['isAdmin'] == true;
      final isAdmin = isAdminVal || roleVal == 'Admin';
      if (!mounted) return;
      setState(() {
        _isAdmin = isAdmin;
        _isCheckingAdmin = false;
      });
      debugPrint('[ROLE] isAdmin=$isAdmin');
      // Listen to live status
      _statusSub = FirebaseFirestore.instance
          .collection('live_channels')
          .doc(channel)
          .snapshots()
          .listen((d) {
            final st = (d.data()?['status'] ?? 'live').toString();
            if (mounted) {
              setState(() {
                _liveStatus = st;
              });
              if (!_isAdmin && st == 'live' && !_hasJoined) {
                // Audience joins only when live starts
                _joinChannelAsAudience();
              }
              if (st == 'ended') {
                // End view for audience
                if (!_isAdmin) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('انتهى البث المباشر'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  Navigator.of(context).maybePop();
                }
              }
            }
          });
      try {
        await initAgora();
      } catch (e, st) {
        debugPrint('[INIT_AGORA] failed: $e\n$st');
        _denyAccess('تعذر تهيئة البث (Agora): $e');
        return;
      }
    } catch (e) {
      _denyAccess('تعذر التحقق من الصلاحيات: $e');
    }
  }

  void _denyAccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
    // On web keep the page to allow reading console/logs; mobile pops back
    if (!kIsWeb) {
      Navigator.of(context).pop();
    }
  }

  Future<void> initAgora() async {
    // Request permissions only if broadcasting
    if (_isAdmin) {
      // On web, permission_handler is not supported and will throw. Browsers
      // prompt for mic/cam access automatically when Agora starts publishing.
      if (!kIsWeb) {
        await [Permission.microphone, Permission.camera].request();
      }
    }

    try {
      _engine = createAgoraRtcEngine();
      await _engine.initialize(
        const RtcEngineContext(
          appId: appId,
          channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
        ),
      );
    } catch (e, st) {
      debugPrint('[AGORA_INIT] Engine init error: $e\n$st');
      rethrow;
    }

    _engine.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (RtcConnection connection, int elapsed) async {
          debugPrint("local user ${connection.localUid} joined");
          setState(() {
            _localUserJoined = true;
          });
          // Register local participant in Firestore
          final uid = connection.localUid;
          if (uid != null) {
            final currentUser = FirebaseAuth.instance.currentUser;
            final displayName =
                (currentUser?.displayName?.trim().isNotEmpty ?? false)
                ? currentUser!.displayName!.trim()
                : (currentUser?.phoneNumber?.trim().isNotEmpty ?? false)
                ? currentUser!.phoneNumber!.trim()
                : 'مشارك';
            await FirebaseFirestore.instance
                .collection('live_channels')
                .doc(channel)
                .collection('participants')
                .doc(uid.toString())
                .set({
                  'name': displayName,
                  'joinedAt': FieldValue.serverTimestamp(),
                }, SetOptions(merge: true));
          }
          // Listen for participant names list
          _participantsSub ??= FirebaseFirestore.instance
              .collection('live_channels')
              .doc(channel)
              .collection('participants')
              .snapshots()
              .listen((snap) {
                final map = <int, String>{};
                for (final d in snap.docs) {
                  final id = int.tryParse(d.id);
                  if (id != null) {
                    final name = (d.data()['name'] ?? '').toString();
                    map[id] = name.isNotEmpty ? name : 'مشارك';
                  }
                }
                if (mounted) {
                  setState(() {
                    _participantNames
                      ..clear()
                      ..addAll(map);
                  });
                }
              });
        },
        onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
          debugPrint("remote user $remoteUid joined");
          setState(() {
            _remoteUids.add(remoteUid); // Add to list
          });
        },
        onUserOffline:
            (
              RtcConnection connection,
              int remoteUid,
              UserOfflineReasonType reason,
            ) {
              debugPrint("remote user $remoteUid left channel");
              setState(() {
                _remoteUids.remove(remoteUid); // Remove from list
                _participantNames.remove(remoteUid);
              });
            },
        onTokenPrivilegeWillExpire: (RtcConnection connection, String token) {
          debugPrint('[onTokenPrivilegeWillExpire] requesting new token...');
          _renewAgoraToken();
        },
      ),
    );

    // Role-based preparation only (no auto-join). Join will happen on Start for admin,
    // and when status becomes 'live' for audience.
    if (_isAdmin) {
      await _engine.setClientRole(role: ClientRoleType.clientRoleBroadcaster);
      await _engine.enableVideo();
      // Do not start preview until Start is pressed
    } else {
      await _engine.setClientRole(role: ClientRoleType.clientRoleAudience);
    }
  }

  Future<String> _fetchAgoraToken({required String role}) async {
    _logAuthState('before _fetchAgoraToken');
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('يجب تسجيل الدخول قبل طلب التوكن');
    }
    await user.getIdToken(true);
    debugPrint('[CALLABLE] getAgoraRtcToken (role=$role)');
    final callable = FirebaseFunctions.instanceFor(
      region: 'us-central1',
    ).httpsCallable('getAgoraRtcToken');
    final res = await callable.call({
      'channel': channel,
      'uid': 0,
      'role': role,
      'expireSeconds': 3600,
    });
    final data = res.data as Map;
    final tok = (data['token'] ?? '').toString();
    if (tok.isEmpty) throw Exception('Returned empty token');
    debugPrint('[CALLABLE] getAgoraRtcToken success');
    return tok;
  }

  Future<void> _renewAgoraToken() async {
    try {
      final newToken = await _fetchAgoraToken(
        role: _isAdmin ? 'broadcaster' : 'audience',
      );
      await _engine.renewToken(newToken);
      debugPrint('Agora token renewed successfully');
    } catch (e) {
      debugPrint('Failed to renew token: $e');
    }
  }

  @override
  void dispose() {
    super.dispose();
    _dispose();
  }

  Future<void> _dispose() async {
    _remoteUids.clear();
    await _statusSub?.cancel();
    // Remove local participant doc (best-effort)
    try {
      // We can't directly get local uid here from engine API, so try cleanup by querying for current user name matches
      // Alternatively, keep last local uid in state when join succeeds
    } catch (_) {}
    await _participantsSub?.cancel();
    // Stop screen share (web) if still active
    if (kIsWeb && _isScreenSharing) {
      try {
        await _screenShare?.stop();
      } catch (_) {}
      _isScreenSharing = false;
    }
    await _engine.leaveChannel();
    await _engine.release();
  }

  void _onToggleMute() {
    setState(() {
      _isMicMuted = !_isMicMuted;
    });
    _engine.muteLocalAudioStream(_isMicMuted);
  }

  void _onToggleVideo() {
    setState(() {
      _isCameraDisabled = !_isCameraDisabled;
    });
    _engine.enableLocalVideo(!_isCameraDisabled);
    if (_isCameraDisabled) {
      _engine.stopPreview();
    } else {
      _engine.startPreview();
    }
  }

  void _onCallEnd() {
    _dispose().then((_) {
      if (mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  void _toggleParticipantList() {
    setState(() {
      _showParticipantList = !_showParticipantList;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[900],
      body: SafeArea(
        child: Stack(
          children: [
            if (_isCheckingAdmin)
              const Center(child: CircularProgressIndicator())
            else ...[
              Positioned.fill(child: _videoStage()),
              // Local video preview
              if (_isAdmin)
                Positioned(
                  right: 16.0,
                  bottom: 90.0,
                  child: SizedBox(
                    width: 120,
                    height: 180,
                    child: _localUserJoined
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(12.0),
                            child: AgoraVideoView(
                              controller: VideoViewController(
                                rtcEngine: _engine,
                                canvas: const VideoCanvas(
                                  uid: 0,
                                ), // Local user's UID is 0
                              ),
                            ),
                          )
                        : Container(
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(12.0),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.2),
                              ),
                            ),
                            child: const Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2.0,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            ),
                          ),
                  ),
                ),
              // Controls
              _buildControls(),
              // Top bar with back button and participant list toggle
              Positioned(
                top: 16.0,
                left: 8.0,
                right: 8.0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back_ios_new,
                        color: Colors.white,
                      ),
                      onPressed: _onCallEnd,
                    ),
                    Row(
                      children: [
                        if (_isAdmin) _buildAdminLiveControls(),
                        IconButton(
                          icon: Icon(
                            _showParticipantList
                                ? Icons.group_off
                                : Icons.group,
                            color: Colors.white,
                          ),
                          onPressed: _toggleParticipantList,
                        ),
                        IconButton(
                          icon: Icon(
                            _showComments
                                ? Icons.chat_bubble
                                : Icons.chat_bubble_outline,
                            color: Colors.white,
                          ),
                          onPressed: () =>
                              setState(() => _showComments = !_showComments),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Participant List Overlay
              if (_showParticipantList) _buildParticipantList(),
              // Comments Panel
              if (_showComments) _buildCommentsPanel(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _videoStage() {
    if (_liveStatus == 'paused') {
      return Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(12.0),
          ),
          child: Text(
            'البث متوقف مؤقتًا',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: sf(context, 18.0),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    if (_remoteUids.isEmpty) {
      return Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(12.0),
          ),
          child: Text(
            'في انتظار انضمام المشاركين إلى البث...',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: sf(context, 16.0),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );
    }

    // واحد => ملء الشاشة، أكثر => شبكة 2xN
    if (_remoteUids.length == 1) {
      final uid = _remoteUids.first;
      return _remoteVideoTile(uid);
    }

    final tiles = _remoteUids
        .map(
          (uid) =>
              AspectRatio(aspectRatio: 16 / 9, child: _remoteVideoTile(uid)),
        )
        .toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 60, 12, 100),
      child: GridView.builder(
        itemCount: tiles.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 16 / 9,
        ),
        itemBuilder: (_, i) => tiles[i],
      ),
    );
  }

  Widget _remoteVideoTile(int uid) {
    final name = _participantNames[uid] ?? 'UID $uid';
    return ClipRRect(
      borderRadius: BorderRadius.circular(12.0),
      child: Stack(
        children: [
          Positioned.fill(
            child: AgoraVideoView(
              controller: VideoViewController.remote(
                rtcEngine: _engine,
                canvas: VideoCanvas(uid: uid),
                connection: const RtcConnection(channelId: channel),
              ),
            ),
          ),
          Positioned(
            left: 8,
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white24),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.person, color: Colors.white, size: sd(context, 16)),
                  const SizedBox(width: 6),
                  Text(
                    name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Positioned(
      bottom: 20.0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: <Widget>[
            if (_isAdmin)
              InkWell(
                onTap: _onToggleMute,
                customBorder: const CircleBorder(),
                child: Container(
                  padding: const EdgeInsets.all(12.0),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isMicMuted
                        ? Colors.white.withValues(alpha: 0.3)
                        : Colors.black.withValues(alpha: 0.4),
                  ),
                  child: Icon(
                    _isMicMuted ? Icons.mic_off : Icons.mic,
                    color: _isMicMuted ? Colors.grey[400] : Colors.white,
                    size: 28.0,
                  ),
                ),
              ),
            if (_isAdmin)
              InkWell(
                onTap: _isLocalRecording
                    ? _stopLocalRecording
                    : _startLocalRecording,
                customBorder: const CircleBorder(),
                child: Container(
                  padding: const EdgeInsets.all(12.0),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isLocalRecording
                        ? Colors.red.withValues(alpha: 0.9)
                        : Colors.black.withValues(alpha: 0.4),
                  ),
                  child: Icon(
                    _isLocalRecording
                        ? Icons.stop_circle
                        : Icons.fiber_manual_record,
                    color: _isLocalRecording ? Colors.white : Colors.redAccent,
                    size: 28.0,
                  ),
                ),
              ),
            InkWell(
              onTap: _onCallEnd,
              customBorder: const CircleBorder(),
              child: Container(
                padding: const EdgeInsets.all(16.0),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.redAccent,
                ),
                child: const Icon(
                  Icons.call_end,
                  color: Colors.white,
                  size: 32.0,
                ),
              ),
            ),
            if (_isAdmin)
              InkWell(
                onTap: _onToggleVideo,
                customBorder: const CircleBorder(),
                child: Container(
                  padding: const EdgeInsets.all(12.0),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isCameraDisabled
                        ? Colors.white.withValues(alpha: 0.3)
                        : Colors.black.withValues(alpha: 0.4),
                  ),
                  child: Icon(
                    _isCameraDisabled ? Icons.videocam_off : Icons.videocam,
                    color: _isCameraDisabled ? Colors.grey[400] : Colors.white,
                    size: sd(context, 28.0),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminLiveControls() {
    return Row(
      children: [
        Tooltip(
          message: 'بدء بث جديد',
          child: IconButton(
            icon: const Icon(
              Icons.play_circle_fill,
              color: Colors.lightGreenAccent,
            ),
            onPressed: _startNewLive,
          ),
        ),
        Tooltip(
          message: _liveStatus == 'paused' ? 'استئناف' : 'إيقاف مؤقت',
          child: IconButton(
            icon: Icon(
              _liveStatus == 'paused' ? Icons.play_arrow : Icons.pause,
              color: Colors.amber,
            ),
            onPressed: _togglePause,
          ),
        ),
        Tooltip(
          message: 'إنهاء البث',
          child: IconButton(
            icon: const Icon(Icons.stop_circle, color: Colors.redAccent),
            onPressed: _endLive,
          ),
        ),
        if (kIsWeb)
          Tooltip(
            message: _isScreenSharing
                ? 'إيقاف مشاركة الشاشة'
                : 'بدء مشاركة الشاشة',
            child: IconButton(
              icon: Icon(
                _isScreenSharing ? Icons.stop_screen_share : Icons.screen_share,
                color: Colors.cyanAccent,
              ),
              onPressed: _isScreenSharing
                  ? _stopScreenShareWeb
                  : _startScreenShareWeb,
            ),
          ),
        const SizedBox(width: 8),
        Tooltip(
          message: _isLocalRecording
              ? 'إيقاف التسجيل المحلي'
              : 'بدء التسجيل المحلي (ميكروفون فقط)',
          child: IconButton(
            icon: Icon(
              _isLocalRecording
                  ? Icons.fiber_smart_record
                  : Icons.fiber_manual_record,
              color: _isLocalRecording ? Colors.redAccent : Colors.orangeAccent,
            ),
            onPressed: _isLocalRecording
                ? _stopLocalRecording
                : _startLocalRecording,
          ),
        ),
      ],
    );
  }

  Future<void> _startLocalRecording() async {
    try {
      final ctx = context;
      if (kIsWeb) {
        _webRecorder ??= WebLocalRecorder();
        if (!_webRecorder!.isSupported) {
          if (!ctx.mounted) return;
          ScaffoldMessenger.of(ctx).showSnackBar(
            const SnackBar(
              content: Text('التسجيل عبر المتصفح غير مدعوم'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
        await _webRecorder!.start();
        setState(() {
          _isLocalRecording = true;
        });
        if (!ctx.mounted) return;
        ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(
            content: Text('بدأ التسجيل المحلي (ويب)'),
            backgroundColor: Colors.green,
          ),
        );
        return;
      } else {
        // Request mic permission explicitly
        final mic = await Permission.microphone.request();
        if (!mic.isGranted) {
          if (!ctx.mounted) return;
          ScaffoldMessenger.of(ctx).showSnackBar(
            const SnackBar(
              content: Text('يتطلب التسجيل إذن الميكروفون'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
        // Ask native side to start screen recording (user will see system dialog)
        final ok =
            await _localRecChannel.invokeMethod<bool>('startLocalRecording') ??
            false;
        if (!ok) {
          if (!ctx.mounted) return;
          ScaffoldMessenger.of(ctx).showSnackBar(
            const SnackBar(
              content: Text('تعذر بدء التسجيل المحلي'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
        setState(() {
          _isLocalRecording = true;
        });
        if (!ctx.mounted) return;
        ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(
            content: Text('بدأ التسجيل المحلي'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      final ctx = context;
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text('خطأ عند بدء التسجيل: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _stopLocalRecording() async {
    try {
      final ctx = context;
      if (kIsWeb) {
        if (_webRecorder == null) return;
        final data = await _webRecorder!.stop();
        setState(() {
          _isLocalRecording = false;
        });
        if (!ctx.mounted) return;
        // Ask user: save to disk or upload
        await showModalBottomSheet(
          context: ctx,
          backgroundColor: Colors.grey[900],
          builder: (ctx) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'ماذا تريد أن تفعل بالتسجيل؟',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        try {
                          await _webRecorder!.saveToDisk(data);
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                content: Text('تم حفظ الملف على جهازك'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        } catch (e) {
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(
                                content: Text('فشل الحفظ المحلي: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.download),
                      label: const Text('حفظ على الجهاز'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text(
                        'إلغاء',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
        return;
      } else {
        final path = await _localRecChannel.invokeMethod<String>(
          'stopLocalRecording',
        );
        setState(() {
          _isLocalRecording = false;
        });
        if (path == null || path.isEmpty) {
          if (!ctx.mounted) return;
          ScaffoldMessenger.of(ctx).showSnackBar(
            const SnackBar(
              content: Text('لم يتم إنشاء ملف التسجيل'),
              backgroundColor: Colors.orange,
            ),
          );
          return;
        }
        // Upload to Firebase Storage
        final file = File(path);
        if (!await file.exists()) {
          if (!ctx.mounted) return;
          ScaffoldMessenger.of(ctx).showSnackBar(
            const SnackBar(
              content: Text('فشل العثور على ملف التسجيل'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
        final ts = DateTime.now().millisecondsSinceEpoch;
        final ref = FirebaseStorage.instance.ref().child(
          'local_recordings/$channel/$ts.mp4',
        );
        final task = await ref.putFile(
          file,
          SettableMetadata(contentType: 'video/mp4'),
        );
        final downloadUrl = await task.ref.getDownloadURL();
        // Create Firestore document similar to cloud recording format
        final currentUser = FirebaseAuth.instance.currentUser;
        await FirebaseFirestore.instance.collection('videos').add({
          'title': 'تسجيل محلي - $channel',
          'description': '',
          'createdAt': FieldValue.serverTimestamp(),
          'visibility': 'public',
          'source': 'local_recording',
          'channel': channel,
          'ownerUid': currentUser?.uid,
          'vodUrl': downloadUrl,
          'videoUrl': downloadUrl,
          'storage': {
            'bucket': FirebaseStorage.instance.bucket,
            'path': ref.fullPath,
            'gsUrl': 'gs://${FirebaseStorage.instance.bucket}/${ref.fullPath}',
            'downloadUrl': downloadUrl,
          },
        });
        if (!ctx.mounted) return;
        ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(
            content: Text('تم حفظ التسجيل ورفعه إلى التخزين'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      final ctx = context;
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text('فشل إيقاف/رفع التسجيل: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _startNewLive() async {
    try {
      final ctx = context;
      // Update live status
      await FirebaseFirestore.instance
          .collection('live_channels')
          .doc(channel)
          .set({
            'status': 'live',
            'startedAt': FieldValue.serverTimestamp(),
            'endedAt': null,
          }, SetOptions(merge: true));

      // Ensure camera/video enabled before publishing (Iris requirement)
      _isCameraDisabled = false;
      await _engine.enableVideo();
      await _engine.enableLocalVideo(true);
      await _engine.startPreview();

      // Join as broadcaster
      final newToken = await _fetchAgoraToken(role: 'broadcaster');
      await _engine.joinChannel(
        token: newToken,
        channelId: channel,
        uid: 0,
        options: const ChannelMediaOptions(),
      );
      _hasJoined = true;

      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(
          content: Text('تم بدء البث'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      final ctx = context;
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text('تعذر بدء البث: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildParticipantList() {
    return Positioned(
      top: 60.0, // Adjust as needed, below the top bar
      right: 8.0,
      child: Container(
        width: 200, // Adjust width as needed
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.4,
        ),
        padding: const EdgeInsets.all(12.0),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(10.0),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 5.0,
              spreadRadius: 2.0,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min, // Important for Column in ScrollView
          children: [
            Text(
              'المشاركون (${_remoteUids.length})',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16.0,
              ),
            ),
            const Divider(color: Colors.white54),
            if (_remoteUids.isEmpty)
              const Text(
                'لا يوجد مشاركون آخرون حتى الآن.',
                style: TextStyle(
                  color: Colors.white70,
                  fontStyle: FontStyle.italic,
                ),
              )
            else
              Expanded(
                // To make ListView scrollable within fixed height
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _remoteUids.length,
                  itemBuilder: (context, index) {
                    final uid = _remoteUids[index];
                    final name = _participantNames[uid] ?? 'UID $uid';
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Row(
                        children: [
                          Icon(
                            Icons.person,
                            color: Colors.white70,
                            size: sd(context, 18),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              name,
                              style: const TextStyle(color: Colors.white),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommentsPanel() {
    return Positioned(
      bottom: 80.0,
      left: 8.0,
      right: 8.0,
      child: Container(
        padding: const EdgeInsets.all(10.0),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12.0),
          border: Border.all(color: Colors.white24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle to resize comments panel height
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: (details) {
                final maxH = MediaQuery.of(context).size.height * 0.6;
                final minH = 100.0;
                setState(() {
                  _commentsHeight = (_commentsHeight - details.delta.dy).clamp(
                    minH,
                    maxH,
                  );
                });
              },
              child: Center(
                child: Container(
                  width: 42,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.white38,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            // Header with title and hide button
            Row(
              children: [
                const Text(
                  'التعليقات',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'إخفاء',
                  onPressed: () => setState(() {
                    _showComments = false;
                  }),
                  icon: const Icon(
                    Icons.visibility_off,
                    color: Colors.white70,
                    size: 20,
                  ),
                ),
              ],
            ),
            if (_replyToId != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'الرد على: ${_replyToName ?? ''}',
                        style: const TextStyle(color: Colors.white70),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setState(() {
                        _replyToId = null;
                        _replyToName = null;
                      }),
                      child: const Icon(
                        Icons.close,
                        color: Colors.white70,
                        size: 18,
                      ),
                    ),
                  ],
                ),
              ),
            // Taller, scrollable comments list with visible scrollbar
            SizedBox(
              height: _commentsHeight,
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('live_channels')
                    .doc(channel)
                    .collection('comments')
                    .orderBy('createdAt', descending: false)
                    .limit(100)
                    .snapshots(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    );
                  }
                  final docs = snap.data?.docs ?? [];
                  if (docs.isEmpty) {
                    return const Center(
                      child: Text(
                        'لا توجد تعليقات بعد',
                        style: TextStyle(color: Colors.white70),
                      ),
                    );
                  }
                  // Build nested comments (top-level + replies)
                  final topLevel = docs.where(
                    (d) => (d.data()['parentId'] == null),
                  );
                  List<QueryDocumentSnapshot<Map<String, dynamic>>> repliesOf(
                    String parentId,
                  ) => docs
                      .where((d) => (d.data()['parentId'] ?? '') == parentId)
                      .toList();

                  return Scrollbar(
                    thumbVisibility: true,
                    child: ListView(
                      padding: const EdgeInsets.only(right: 4),
                      children: [
                        for (final doc in topLevel)
                          _buildCommentTile(
                            id: doc.id,
                            data: doc.data(),
                            onReply: () {
                              setState(() {
                                _replyToId = doc.id;
                                _replyToName = (doc.data()['name'] ?? 'مستخدم')
                                    .toString();
                              });
                              _commentFocus.requestFocus();
                            },
                            // children
                            children: [
                              for (final child in repliesOf(doc.id))
                                _buildCommentTile(
                                  id: child.id,
                                  data: child.data(),
                                  isReply: true,
                                  parentName: (doc.data()['name'] ?? 'مستخدم')
                                      .toString(),
                                  onReply: () {
                                    setState(() {
                                      _replyToId = doc.id;
                                      _replyToName =
                                          (doc.data()['name'] ?? 'مستخدم')
                                              .toString();
                                    });
                                    _commentFocus.requestFocus();
                                  },
                                ),
                            ],
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commentCtrl,
                    focusNode: _commentFocus,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'اكتب تعليقًا...',
                      hintStyle: const TextStyle(color: Colors.white70),
                      filled: true,
                      fillColor: Colors.black.withValues(alpha: 0.4),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    onSubmitted: (_) => _sendComment(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _sendComment,
                  icon: const Icon(Icons.send, color: Colors.white),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('يجب تسجيل الدخول لإرسال تعليق'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Resolve display name and role from Firestore first, with safe fallbacks
      String displayName = 'مستخدم';
      String roleText = 'مستخدم';
      try {
        final uDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        final uData = uDoc.data();
        if (uData != null) {
          final profileName = (uData['name'] ?? '').toString().trim();
          final displayNameAlt = (uData['displayName'] ?? '').toString().trim();
          final roleVal = (uData['role'] ?? '').toString();
          final isAdminVal = uData['isAdmin'] == true;
          if (profileName.isNotEmpty) {
            displayName = profileName;
          } else if (displayNameAlt.isNotEmpty) {
            displayName = displayNameAlt;
          } else if ((user.displayName?.trim().isNotEmpty ?? false)) {
            displayName = user.displayName!.trim();
          } else if ((user.phoneNumber?.trim().isNotEmpty ?? false)) {
            displayName = user.phoneNumber!.trim();
          }
          roleText = (isAdminVal || roleVal == 'Admin') ? 'مشرف' : 'مستخدم';
        } else {
          // Fallbacks if no user doc
          displayName = (user.displayName?.trim().isNotEmpty ?? false)
              ? user.displayName!.trim()
              : (user.phoneNumber?.trim().isNotEmpty ?? false)
              ? user.phoneNumber!.trim()
              : 'مستخدم';
          roleText = _isAdmin ? 'مشرف' : 'مستخدم';
        }
      } catch (_) {
        // Network/permission fallback
        displayName = (user.displayName?.trim().isNotEmpty ?? false)
            ? user.displayName!.trim()
            : (user.phoneNumber?.trim().isNotEmpty ?? false)
            ? user.phoneNumber!.trim()
            : 'مستخدم';
        roleText = _isAdmin ? 'مشرف' : 'مستخدم';
      }

      // Resolve user photo URL
      String? photoUrl;
      try {
        final uDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        final uData = uDoc.data();
        final raw =
            (uData?['pictureUrl'] ?? uData?['photoUrl'] ?? user.photoURL)
                ?.toString();
        photoUrl = await _resolvePhotoUrl(raw);
      } catch (_) {
        try {
          photoUrl = await _resolvePhotoUrl(user.photoURL);
        } catch (_) {}
      }

      await FirebaseFirestore.instance
          .collection('live_channels')
          .doc(channel)
          .collection('comments')
          .add({
            'uid': user.uid,
            'name': displayName,
            'text': text,
            'role': roleText,
            'photoUrl': photoUrl,
            'parentId': _replyToId,
            'createdAt': FieldValue.serverTimestamp(),
          });
      _commentCtrl.clear();
      setState(() {
        _replyToId = null;
        _replyToName = null;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر إرسال التعليق: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildCommentTile({
    required String id,
    required Map<String, dynamic> data,
    bool isReply = false,
    String? parentName,
    VoidCallback? onReply,
    List<Widget> children = const [],
  }) {
    final name = (data['name'] ?? 'مستخدم').toString();
    final text = (data['text'] ?? '').toString();
    final role = (data['role'] ?? '').toString();
    final commentUid = (data['uid'] ?? '').toString();
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final canDelete =
        _isAdmin || (currentUid != null && currentUid == commentUid);
    return Padding(
      padding: EdgeInsets.only(
        top: 6.0,
        bottom: 6.0,
        right: isReply ? 24.0 : 0.0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FutureBuilder<String?>(
            future: _resolvePhotoUrl((data['photoUrl'] ?? '').toString()),
            builder: (context, snap) {
              final resolved = snap.data;
              return CircleAvatar(
                radius: 12,
                backgroundColor: Colors.white24,
                backgroundImage: (resolved != null && resolved.isNotEmpty)
                    ? NetworkImage(resolved)
                    : null,
                child: (resolved == null || resolved.isEmpty)
                    ? Text(
                        _initialsFromName(name),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    : null,
              );
            },
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (role.isNotEmpty) const TextSpan(text: ' '),
                      if (role.isNotEmpty)
                        WidgetSpan(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: role == 'مشرف'
                                  ? Colors.purple
                                  : Colors.blueGrey,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              role,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ),
                      const TextSpan(
                        text: ': ',
                        style: TextStyle(color: Colors.white),
                      ),
                      TextSpan(
                        text: text,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
                if (isReply && (parentName?.isNotEmpty ?? false))
                  Padding(
                    padding: const EdgeInsets.only(top: 2.0),
                    child: Text(
                      '↪︎ ردًا على $parentName',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                      ),
                    ),
                  ),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: onReply,
                      icon: const Icon(
                        Icons.reply,
                        size: 16,
                        color: Colors.white70,
                      ),
                      label: const Text(
                        'رد',
                        style: TextStyle(color: Colors.white70),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                      ),
                    ),
                    if (canDelete)
                      TextButton.icon(
                        onPressed: () => _confirmAndDeleteComment(id),
                        icon: const Icon(
                          Icons.delete,
                          size: 16,
                          color: Colors.redAccent,
                        ),
                        label: const Text(
                          'حذف',
                          style: TextStyle(color: Colors.redAccent),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                        ),
                      ),
                  ],
                ),
                if (children.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Column(children: children),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmAndDeleteComment(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('تأكيد الحذف', style: TextStyle(color: Colors.white)),
        content: const Text(
          'هل تريد حذف هذا التعليق؟ سيتم حذف الردود المرتبطة به أيضًا.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('حذف', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final batch = FirebaseFirestore.instance.batch();
      final commentsCol = FirebaseFirestore.instance
          .collection('live_channels')
          .doc(channel)
          .collection('comments');

      // Delete the parent comment
      batch.delete(commentsCol.doc(id));
      // Delete direct replies (one level deep)
      final repliesSnap = await commentsCol
          .where('parentId', isEqualTo: id)
          .get();
      for (final doc in repliesSnap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم حذف التعليق'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر حذف التعليق: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
