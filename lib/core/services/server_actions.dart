import 'package:cloud_functions/cloud_functions.dart';

import '../features/features.dart';
import 'features_service.dart';

/// Calls one server function. Tests replace this with a fake.
abstract class ServerGateway {
  Future<Map<String, dynamic>> call(String name, Map<String, Object?> data);
}

class CloudServerGateway implements ServerGateway {
  const CloudServerGateway();

  @override
  Future<Map<String, dynamic>> call(String name, Map<String, Object?> data) async {
    final result = await FirebaseFunctions.instanceFor(region: 'asia-south1').httpsCallable(name).call<Object?>(data);
    final d = result.data;
    return d is Map ? Map<String, dynamic>.from(d) : const {};
  }
}

/// What the server says about itself (F33).
class ServerStatus {
  final Map<String, bool> switches;
  const ServerStatus(this.switches);

  int get on => switches.values.where((v) => v).length;
}

/// The function answered no: a real refusal (not allowed, bad input). Shown to the admin.
class ServerRefused implements Exception {
  final String code;
  final String? message;
  const ServerRefused(this.code, [this.message]);

  @override
  String toString() => 'ServerRefused($code)';
}

/// Admin actions done by the server (F21, F23, F27). With the matching switch
/// ON the app calls the function; if the function is not deployed or not
/// reachable the app falls back to the direct write it always had, so nothing
/// breaks before the owner has deployed. A real refusal is never hidden by a fallback.
class ServerActions {
  ServerActions._();

  static ServerGateway gateway = const CloudServerGateway();

  /// Codes that mean "the server is not there / not ready", not "no".
  static const _fallbackCodes = {'not-found', 'unimplemented', 'unavailable', 'failed-precondition', 'deadline-exceeded', 'internal'};

  /// Runs [name] when [flag] is on. Returns the answer, or null when the caller
  /// must do the old direct write (switch off, or no server). Throws [ServerRefused] for a real refusal.
  static Future<Map<String, dynamic>?> tryCall(String flag, String name, Map<String, Object?> data) async {
    if (!FeaturesService.isOn(flag)) return null;
    try {
      return await gateway.call(name, data);
    } on FirebaseFunctionsException catch (e) {
      if (_fallbackCodes.contains(e.code)) return null;
      throw ServerRefused(e.code, e.message);
    } catch (_) {
      return null; // offline or an odd error: the direct write will report its own problem
    }
  }

  static Future<bool> setRiskTier(String uid, String tier, String reason) async =>
      await tryCall(FeatureKey.serverAdminActions, 'adminSetRiskTier', {'uid': uid, 'tier': tier, 'reason': reason}) != null;

  static Future<bool> decideDriver(String uid, String status, {String? reason, String? note}) async =>
      await tryCall(FeatureKey.serverAdminActions, 'adminDecideDriver', {'uid': uid, 'status': status, 'reason': ?reason, 'note': ?note}) != null;

  static Future<bool> payoutDecision(String payoutId, String action, {String? reason, String? reference}) async =>
      await tryCall(FeatureKey.serverWallet, 'adminPayoutDecision', {'payoutId': payoutId, 'action': action, 'reason': ?reason, 'reference': ?reference}) != null;

  /// F33: asks the server whether it is there. Null when it is not reachable (not deployed yet).
  /// This call has no switch: it must work before anything is turned on.
  static Future<ServerStatus?> status() async {
    try {
      final r = await gateway.call('serverStatus', const {});
      if (r['ok'] != true) return null;
      final sw = r['switches'];
      return ServerStatus({if (sw is Map) for (final e in sw.entries) e.key.toString(): e.value == true});
    } catch (_) {
      return null;
    }
  }

  /// An announcement push. Returns how many people were tried, or null when the server is not there.
  static Future<int?> broadcast({required String title, required String body, String? role}) async {
    final r = await tryCall(FeatureKey.adminBroadcast, 'adminBroadcast', {'title': title, 'body': body, 'role': ?role});
    final people = r?['people'];
    return people is int ? people : null;
  }
}
