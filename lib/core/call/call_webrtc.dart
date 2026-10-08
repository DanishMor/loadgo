import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'call_models.dart';
import 'call_provider.dart';

/// Free WebRTC voice call (flutter_webrtc) with Google's public STUN servers.
/// STUN only: if both phones sit behind strict networks the call may not
/// connect and the app says so. LATER(paid): a TURN server or a masked-number
/// provider.
class WebRtcCallProvider implements CallProvider {
  static const iceServers = <String, dynamic>{
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
  };

  RTCPeerConnection? _pc;
  MediaStream? _local;
  RTCVideoRenderer? _remoteAudio;
  final _candidates = StreamController<CallCandidate>.broadcast();
  final _connected = StreamController<bool>.broadcast();
  bool _closed = false;

  @override
  bool get supported => true;

  @override
  Stream<CallCandidate> get localCandidates => _candidates.stream;

  @override
  Stream<bool> get connected => _connected.stream;

  @override
  Future<void> init() async {
    try {
      _local = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': false});
    } catch (_) {
      throw MicDeniedException();
    }
    final pc = await createPeerConnection(iceServers);
    _pc = pc;
    for (final t in _local!.getAudioTracks()) {
      await pc.addTrack(t, _local!);
    }
    pc.onIceCandidate = (c) {
      final text = c.candidate;
      if (text == null || _candidates.isClosed) return;
      _candidates.add(CallCandidate(from: '', candidate: text, sdpMid: c.sdpMid, sdpMLineIndex: c.sdpMLineIndex));
    };
    pc.onTrack = (event) async {
      if (event.streams.isEmpty) return;
      // The web needs a renderer to play the remote audio; phones play it by themselves.
      final r = _remoteAudio ??= RTCVideoRenderer();
      await r.initialize();
      r.srcObject = event.streams.first;
    };
    pc.onConnectionState = (s) {
      if (_closed || _connected.isClosed) return;
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) _connected.add(true);
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed || s == RTCPeerConnectionState.RTCPeerConnectionStateClosed) _connected.add(false);
    };
  }

  @override
  Future<String> createOffer() async {
    final offer = await _pc!.createOffer({'offerToReceiveAudio': 1, 'offerToReceiveVideo': 0});
    await _pc!.setLocalDescription(offer);
    return offer.sdp ?? '';
  }

  @override
  Future<String> acceptOffer(String offerSdp) async {
    await _pc!.setRemoteDescription(RTCSessionDescription(offerSdp, 'offer'));
    final answer = await _pc!.createAnswer({'offerToReceiveAudio': 1, 'offerToReceiveVideo': 0});
    await _pc!.setLocalDescription(answer);
    return answer.sdp ?? '';
  }

  @override
  Future<void> setAnswer(String answerSdp) => _pc!.setRemoteDescription(RTCSessionDescription(answerSdp, 'answer'));

  @override
  Future<void> addRemoteCandidate(CallCandidate c) => _pc!.addCandidate(RTCIceCandidate(c.candidate, c.sdpMid, c.sdpMLineIndex));

  @override
  Future<void> setMuted(bool muted) async {
    for (final t in _local?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      t.enabled = !muted;
    }
  }

  @override
  Future<void> setSpeaker(bool on) async {
    try {
      await Helper.setSpeakerphoneOn(on);
    } catch (_) {
      // Not available on every platform (the web chooses the output itself).
    }
  }

  @override
  Future<void> close() async {
    _closed = true;
    try {
      for (final t in _local?.getTracks() ?? const <MediaStreamTrack>[]) {
        await t.stop();
      }
      await _local?.dispose();
      await _pc?.close();
      await _remoteAudio?.dispose();
    } catch (_) {}
    await _candidates.close();
    await _connected.close();
  }
}
