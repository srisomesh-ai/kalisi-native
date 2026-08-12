import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:drift/drift.dart' show Value;
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
  bool onHold = false;
  bool bluetoothOn = false;
  bool incoming = false;
  DateTime? connectedAt;
  String? error;

  RTCPeerConnection? _pc;
  Timer? _buzz;
  Timer? _dropTimer;
  Timer? _setupTimeout;
  MediaStream? _localStream;
  Timer? _ticker;
  final List<RTCIceCandidate> _pendingRemote = [];
  /// Our own candidates, held until the other side can accept them.
  final List<Map<String, dynamic>> _pendingLocal = [];
  bool _remoteDescSet = false;
  /// True once the far end has a peer connection ready.
  bool _peerReady = false;

  /// Public STUN works for most networks. TURN is needed for the rest —
  /// see RELEASE_SETUP notes; without it some calls simply cannot connect.
  static List<Map<String, dynamic>> iceServers = [
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun1.l.google.com:19302'},
    {'urls': 'stun:stun2.l.google.com:19302'},
    {'urls': 'stun:stun3.l.google.com:19302'},
    {'urls': 'stun:stun.cloudflare.com:3478'},
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

    // a soft repeating tone so the caller knows it's ringing
    _startRingback();

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

      // If nothing connects within a minute, stop waiting.
      _setupTimeout?.cancel();
      _setupTimeout = Timer(const Duration(seconds: 60), () {
        if (state != CallState.connected) {
          error = 'No answer';
          hangUp(notifyPeer: true);
        }
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
    _startRinging();
    _setState(CallState.ringing);
  }

  Map<String, dynamic>? _pendingOffer;

  Future<void> accept() async {
    final data = _pendingOffer;
    if (data == null || _me == null || peer == null) return;
    _stopRinging();
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

      // We're answering, so the caller is definitely up: send freely.
      _peerReady = true;
      await _signal('call-answer', {
        'callId': callId,
        'sdp': answer.sdp,
        'type': answer.type,
      });
      await _flushLocal();
    } catch (_) {
      error = 'Could not connect';
      await hangUp(notifyPeer: true);
    }
  }

  Future<void> decline() async {
    _stopRinging();
    await _signal('call-end', {'callId': callId, 'reason': 'declined'});
    await _logCall(reason: 'declined');
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

      // The callee is now up — release everything we held back.
      _peerReady = true;
      await _flushLocal();

      _setState(CallState.connecting);
    } catch (_) {}
  }

  /// Send any candidates we generated before the far end was ready.
  Future<void> _flushLocal() async {
    if (_pendingLocal.isEmpty) return;
    final queued = List<Map<String, dynamic>>.from(_pendingLocal);
    _pendingLocal.clear();
    for (final d in queued) {
      await _signal('call-ice', d);
    }
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
    await _logCall(reason: reason);
    await _cleanup();
    _setState(CallState.ended);
  }

  // ---------------- controls ----------------

  void toggleMute() {
    muted = !muted;
    _localStream?.getAudioTracks().forEach((t) => t.enabled = !muted);
    notifyListeners();
  }

  /// Hold: stop sending and playing audio without dropping the call.
  void toggleHold() {
    onHold = !onHold;
    _localStream?.getAudioTracks().forEach((t) => t.enabled = !onHold);
    try {
      _pc?.getReceivers().then((rs) {
        for (final r in rs) {
          r.track?.enabled = !onHold;
        }
      });
    } catch (_) {}
    notifyListeners();
  }

  /// Route audio to a paired Bluetooth headset if there is one.
  Future<void> toggleBluetooth() async {
    bluetoothOn = !bluetoothOn;
    try {
      if (bluetoothOn) {
        await Helper.setSpeakerphoneOn(false);
        speakerOn = false;
      }
      await Helper.setBluetoothScoOn(bluetoothOn);
    } catch (_) {
      // no headset connected — put the flag back
      bluetoothOn = false;
    }
    notifyListeners();
  }

  Future<void> toggleSpeaker() async {
    speakerOn = !speakerOn;
    try {
      if (speakerOn && bluetoothOn) {
        await Helper.setBluetoothScoOn(false);
        bluetoothOn = false;
      }
      await Helper.setSpeakerphoneOn(speakerOn);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> hangUp({bool notifyPeer = true}) async {
    if (notifyPeer && callId != null) {
      await _signal('call-end', {'callId': callId, 'reason': 'hangup'});
    }
    await _logCall();
    await _cleanup();
    _setState(CallState.ended);
  }

  /// Record the call in the chat so there's a history, like WhatsApp.
  Future<void> _logCall({String? reason}) async {
    final me = _me;
    final c = peer;
    if (me == null || c == null) return;
    final connected = connectedAt != null;
    final secs = duration.inSeconds;

    final text = connected
        ? (secs >= 60
            ? 'Voice call · ${secs ~/ 60} min ${secs % 60} sec'
            : 'Voice call · $secs sec')
        : (incoming
            ? (reason == 'declined' ? 'Call declined' : 'Missed voice call')
            : (reason == 'declined' ? 'Call declined' : 'No answer'));

    try {
      await _db.insertMessage(MessagesCompanion.insert(
        id: newUuid(),
        contactId: c.id,
        personaId: me.id,
        fromMe: incoming ? 'them' : 'me',
        kind: const Value('call'),
        body: Value(text),
        ts: nowMs(),
        status: const Value('delivered'),
      ));
    } catch (_) {}
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

  /// Ring with the device's notification tone plus a repeating vibration.
  void _startRinging() {
    _buzz?.cancel();
    _buzz = Timer.periodic(const Duration(milliseconds: 1600), (_) {
      HapticFeedback.heavyImpact();
      Future.delayed(const Duration(milliseconds: 220),
          () => HapticFeedback.heavyImpact());
    });
    HapticFeedback.heavyImpact();
    try {
      // The device's own ringtone — the sound the user already knows.
      // Respects their silent/vibrate switch.
      FlutterRingtonePlayer().playRingtone(looping: true, asAlarm: false);
    } catch (_) {
      // vibration alone still signals the call
    }
  }

  /// Quiet repeating tone while we wait for them to pick up.
  void _startRingback() {
    _buzz?.cancel();
    _buzz = Timer.periodic(const Duration(seconds: 3), (_) {
      try {
        SystemSound.play(SystemSoundType.click);
      } catch (_) {}
    });
  }

  void _stopRinging() {
    _buzz?.cancel();
    _buzz = null;
    try {
      FlutterRingtonePlayer().stop();
    } catch (_) {}
  }

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
      final data = {
        'callId': callId,
        'candidate': c.candidate,
        'sdpMid': c.sdpMid,
        'sdpMLineIndex': c.sdpMLineIndex,
      };
      // The caller produces candidates before the callee has a peer
      // connection. Sending them then loses them, so hold until ready.
      if (!_peerReady) {
        _pendingLocal.add(data);
        return;
      }
      _signal('call-ice', data);
    };

    _pc!.onConnectionState = (s) {
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _dropTimer?.cancel();
        _stopRinging();
        HapticFeedback.mediumImpact();
        connectedAt ??= DateTime.now();
        _startTicker();
        _setState(CallState.connected);
      } else if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        error = 'Could not connect — the network may need a TURN server';
        hangUp(notifyPeer: true);
      } else if (s ==
          RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        // A brief drop usually recovers on its own — give it a moment
        // before tearing the call down.
        _dropTimer?.cancel();
        _dropTimer = Timer(const Duration(seconds: 8), () {
          final st = _pc?.connectionState;
          if (st ==
                  RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
              st == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
            hangUp(notifyPeer: false);
          }
        });
      } else if (s ==
          RTCPeerConnectionState.RTCPeerConnectionStateConnecting) {
        _setState(CallState.connecting);
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
    _stopRinging();
    _ticker?.cancel();
    _ticker = null;
    _dropTimer?.cancel();
    _dropTimer = null;
    _setupTimeout?.cancel();
    _setupTimeout = null;
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
    _peerReady = false;
    _pendingRemote.clear();
    _pendingLocal.clear();
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
