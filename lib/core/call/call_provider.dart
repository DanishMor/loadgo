import 'call_models.dart';

/// The media side of a call. The app only talks to this interface, so the
/// free WebRTC implementation can be replaced later.
///
/// LATER(paid): a masked-number provider (the phone network rings both people
/// without either seeing a number) and a push message to ring a closed app.
abstract class CallProvider {
  /// False when this device cannot place calls (the call button explains it).
  bool get supported;

  /// Opens the microphone and the connection. Throws [MicDeniedException]
  /// when the microphone is refused.
  Future<void> init();

  /// The caller's offer (SDP text).
  Future<String> createOffer();

  /// The callee takes the caller's offer and makes the answer (SDP text).
  Future<String> acceptOffer(String offerSdp);

  /// The caller takes the callee's answer.
  Future<void> setAnswer(String answerSdp);

  Future<void> addRemoteCandidate(CallCandidate c);

  /// Candidates found on this phone, to send to the other one.
  Stream<CallCandidate> get localCandidates;

  /// Emits true once audio flows, false if the connection failed or closed.
  Stream<bool> get connected;

  Future<void> setMuted(bool muted);
  Future<void> setSpeaker(bool on);
  Future<void> close();
}

class MicDeniedException implements Exception {
  @override
  String toString() => 'MicDeniedException';
}

class CallUnsupportedException implements Exception {
  @override
  String toString() => 'CallUnsupportedException';
}
