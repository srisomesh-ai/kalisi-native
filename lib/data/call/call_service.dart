import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../db/database.dart';
import '../api/api_client.dart';
import '../crypto/kalisi_crypto.dart';
import '../../util/ids.dart';

enum CallState { idle, calling, ringing, connecting, connected, ended }

/// One audio call.
///
/// Signalling (offer / answer / ICE candidates) travels as ordinary encrypted
/// control messages through the existing send + poll pipeline, so calling needs
/// no extra server. Media itself goes peer-to-peer over WebRTC.
class CallService extends ChangeNotifier {
  final KalisiDb _db;
  final ApiClient _api;
  CallService(this._db, this._api);

  CallState state = CallState.idle;
  Contact? peer;
  Persona? _me;
  String? callId;
  bool muted = false;
  bool speakerOn = false;
  bool incoming = false;
  DateTime? connectedAt;
  String? error;

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  Timer? _ticker;
  final List<RTCIceCandidate> _pendingRemote = [];
  bool _remoteDescSet = false;

  /// Public STUN works for most networks. TURN is needed for the rest —
  /// see RELEASE_SETUP notes; without it some calls simply cannot connect.
  static List<Map<String, dynamic>> iceServers = [
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun1.l.google.com:19302'},
  ];

  Duration get duration => connectedAt == null
      ? Duration.zero
      : DateTime.now().difference(connectedAt!);

  bool get isActive => state != CallState.idle && state != CallState.ended;

  // ---------------- outgoing ----------------

  Future<void> startCall(Persona me, Contact contact) async {
    if (isActive) return;
    _me = me;
    peer = contact;
    incoming = false;
    callId = newUuid();
    _setState(CallState.calling);

    try {
      await _openMedia();
      await _createPeer();

      final offer = await _pc!.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': false,
      });
      await _pc!.setLocalDescription(offer);

      await _signal('call-offer', {
        'callId': callId,
        'sdp': offer.sdp,
        'type': offer.type,
      });
    } catch (e) {
      error = 'Could not start the call';
      await hangUp(notifyPeer: true);
    }
  }

  // ---------------- incoming ----------------

  /// A call is being offered to us.
  Future<void> onOffer(
    Persona me,
    Contact from,
    Map<String, dynamic> data,
  ) async {
    if (isActive) {
      // already busy — tell them
      await _signalTo(me, from, 'call-end', {
        'callId': data['callId'],
        'reason': 'busy',
      });
      return;
    }
    _me = me;
    peer = from;
    incoming = true;
    callId = data['callId']?.toString();
    _pendingOffer = data;
    _setState(CallState.ringing);
  }

  Map<String, dynamic>? _pendingOffer;

  Future<void> accept() async {
    final data = _pendingOffer;
    if (data == null || _me == null || peer == null) return;
    _setState(CallState.connecting);
    try {
      await _openMedia();
      await _createPeer();

      await _pc!.setRemoteDescription(
        RTCSessionDescription(data['sdp']?.toString(), data['type']?.toString()),
      );
      _remoteDescSet = true;
      for (final c in _pendingRemote) {
        await _pc!.addCandidate(c);
      }
      _pendingRemote.clear();

      final answer = await _pc!.createAnswer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': false,
      });
      await _pc!.setLocalDescription(answer);

      await _signal('call-answer', {
        'callId': callId,
        'sdp': answer.sdp,
        'type': answer.type,
      });
    } catch (_) {
      error = 'Could not connect';
      await hangUp(notifyPeer: true);
    }
  }

  Future<void> decline() async {
    await _signal('call-end', {'callId': callId, 'reason': 'declined'});
    await _cleanup();
    _setState(CallState.ended);
  }

  // ---------------- signalling in ----------------

  Future<void> onAnswer(Map<String, dynamic> data) async {
    if (_pc == null) return;
    try {
      await _pc!.setRemoteDescription(
        RTCSessionDescription(data['sdp']?.toString(), data['type']?.toString()),
      );
      _remoteDescSet = true;
      for (final c in _pendingRemote) {
        await _pc!.addCandidate(c);
      }
      _pendingRemote.clear();
      _setState(CallState.connecting);
    } catch (_) {}
  }

  Future<void> onCandidate(Map<String, dynamic> data) async {
    final c = RTCIceCandidate(
      data['candidate']?.toString(),
      data['sdpMid']?.toString(),
      (data['sdpMLineIndex'] as num?)?.toInt(),
    );
    if (_pc == null || !_remoteDescSet) {
      _pendingRemote.add(c);
      return;
    }
    try {
      await _pc!.addCandidate(c);
    } catch (_) {}
  }

  Future<void> onRemoteEnd(String? reason) async {
    if (reason == 'busy') error = 'Line busy';
    if (reason == 'declined') error = 'Call declined';
    await _cleanup();
    _setState(CallState.ended);
  }

  // ---------------- controls ----------------

  void toggleMute() {
    muted = !muted;
    _localStream?.getAudioTracks().forEach((t) => t.enabled = !muted);
    notifyListeners();
  }

  Future<void> toggleSpeaker() async {
    speakerOn = !speakerOn;
    try {
      await Helper.setSpeakerphoneOn(speakerOn);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> hangUp({bool notifyPeer = true}) async {
    if (notifyPeer && callId != null) {
      await _signal('call-end', {'callId': callId, 'reason': 'hangup'});
    }
    await _cleanup();
    _setState(CallState.ended);
  }

  /// Clear a finished call so the UI can close.
  void reset() {
    state = CallState.idle;
    peer = null;
    callId = null;
    error = null;
    incoming = false;
    connectedAt = null;
    _pendingOffer = null;
    notifyListeners();
  }

  // ---------------- internals ----------------

  Future<void> _openMedia() async {
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': false,
    });
  }

  Future<void> _createPeer() async {
    _pc = await createPeerConnection({
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
    });

    _localStream?.getTracks().forEach((t) {
      _pc!.addTrack(t, _localStream!);
    });

    _pc!.onIceCandidate = (c) {
      if (c.candidate == null) return;
      _signal('call-ice', {
        'callId': callId,
        'candidate': c.candidate,
        'sdpMid': c.sdpMid,
        'sdpMLineIndex': c.sdpMLineIndex,
      });
    };

    _pc!.onConnectionState = (s) {
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        connectedAt ??= DateTime.now();
        _startTicker();
        _setState(CallState.connected);
      } else if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        error = 'Could not connect — the network may need a TURN server';
        hangUp(notifyPeer: true);
      } else if (s ==
          RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        hangUp(notifyPeer: false);
      }
    };
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      notifyListeners();
    });
  }

  Future<void> _cleanup() async {
    _ticker?.cancel();
    _ticker = null;
    try {
      _localStream?.getTracks().forEach((t) => t.stop());
      await _localStream?.dispose();
    } catch (_) {}
    _localStream = null;
    try {
      await _pc?.close();
    } catch (_) {}
    _pc = null;
    _remoteDescSet = false;
    _pendingRemote.clear();
    _pendingOffer = null;
    muted = false;
  }

  Future<void> _signal(String kind, Map<String, dynamic> data) async {
    final me = _me;
    final c = peer;
    if (me == null || c == null) return;
    await _signalTo(me, c, kind, data);
  }

  Future<void> _signalTo(
    Persona me,
    Contact to,
    String kind,
    Map<String, dynamic> data,
  ) async {
    if (to.publicJwk == null) return;
    final obj = <String, dynamic>{
      'kind': kind,
      ...data,
      'cid': newUuid(),
      'ts': nowMs(),
    };
    try {
      final enc =
          await KalisiCrypto.encryptObject(obj, me.privateJwk, to.publicJwk!);
      await _api.send(
        kalId: me.kalId,
        token: me.token,
        to: to.kalId,
        clientId: obj['cid'] as String,
        iv: enc.iv,
        blob: enc.blob,
      );
    } catch (_) {}
  }

  void _setState(CallState s) {
    state = s;
    notifyListeners();
  }

  @override
  void dispose() {
    _cleanup();
    super.dispose();
  }
}
