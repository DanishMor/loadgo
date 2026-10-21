import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../bilty/lr_service.dart';
import '../features/features.dart';
import '../services/booking_service.dart';
import '../services/breadcrumbs.dart';
import '../services/fleet_service.dart';
import '../services/load_service.dart';
import '../services/notification_service.dart';
import '../services/offer_service.dart';
import '../services/support_service.dart';
import '../../firebase_options.dart';
import '../app_info.dart';

/// Z1/Z3: what a failed read means, in one short code the owner can read out on the phone.
enum ProbeStatus { ok, noAccess, needsIndex, offline, timeout, other }

extension ProbeStatusCode on ProbeStatus {
  /// The code shown on error screens. `null` for OK.
  String? get code => switch (this) {
        ProbeStatus.ok => null,
        ProbeStatus.noAccess => 'E-PERM',
        ProbeStatus.needsIndex => 'E-INDEX',
        ProbeStatus.offline => 'E-NET',
        ProbeStatus.timeout => 'E-TIMEOUT',
        ProbeStatus.other => 'E-GEN',
      };

  /// Translation key of the plain-words explanation (Hindi first, 12 languages).
  String get messageKey => switch (this) {
        ProbeStatus.ok => 'dgOk',
        ProbeStatus.noAccess => 'dgNoAccess',
        ProbeStatus.needsIndex => 'dgNeedsIndex',
        ProbeStatus.offline => 'dgOffline',
        ProbeStatus.timeout => 'dgTimeout',
        ProbeStatus.other => 'dgOther',
      };
}

class ProbeResult {
  final String name;
  final ProbeStatus status;

  /// For [ProbeStatus.needsIndex]: the fields named in the message, and the console link to create it, if Firestore gave one.
  final String detail;
  final String? consoleLink;
  final int ms;
  const ProbeResult(this.name, this.status, {this.detail = '', this.consoleLink, this.ms = 0});
}

class Diagnose {
  Diagnose._();

  static final _link = RegExp(r'https://console\.firebase\.google\.com/\S+');

  /// The short code for an error-screen message key (Z3): E-PERM, E-INDEX, E-NET, E-TIMEOUT; E-GEN for the rest.
  static String codeForKey(String messageKey) => switch (messageKey) {
        'errorNoAccess' => 'E-PERM',
        'errorIndex' => 'E-INDEX',
        'errorNetwork' || 'errorOffline' => 'E-NET',
        'errorSlow' => 'E-TIMEOUT',
        _ => 'E-GEN',
      };

  /// Sorts any error into a [ProbeStatus]. [online] is what the connectivity service says.
  static ProbeStatus classify(Object? error, {bool online = true}) {
    if (error is TimeoutException) return online ? ProbeStatus.timeout : ProbeStatus.offline;
    if (error is FirebaseException) {
      final msg = (error.message ?? '').toLowerCase();
      switch (error.code) {
        case 'permission-denied':
          return ProbeStatus.noAccess;
        case 'failed-precondition':
          return msg.contains('index') ? ProbeStatus.needsIndex : ProbeStatus.other;
        case 'unavailable':
        case 'network-request-failed':
          return ProbeStatus.offline;
        case 'deadline-exceeded':
          return online ? ProbeStatus.timeout : ProbeStatus.offline;
      }
    }
    if (error != null && error.runtimeType.toString() == 'SocketException') return ProbeStatus.offline;
    return ProbeStatus.other;
  }

  /// The console link from an index error, if there is one (only a Firebase console address is ever kept).
  static String? indexLink(Object? error) {
    if (error is! FirebaseException) return null;
    return _link.firstMatch(error.message ?? '')?.group(0);
  }

  /// A short description of the missing index, without the link.
  static String indexDetail(Object? error) {
    if (error is! FirebaseException) return '';
    final m = RegExp(r'index[^.]*?(?:on|for)[^.]*', caseSensitive: false).firstMatch((error.message ?? '').replaceAll(_link, ''));
    return m == null ? '' : Redactor.clean(m.group(0)!, maxLength: 160);
  }

  /// Runs one read and reports. [run] must only read. Nothing here writes.
  static Future<ProbeResult> probe(String name, Future<Object?> Function() run, {Duration timeout = const Duration(seconds: 6), bool online = true}) async {
    final sw = Stopwatch()..start();
    try {
      await run().timeout(timeout);
      return ProbeResult(name, ProbeStatus.ok, ms: sw.elapsedMilliseconds);
    } catch (e) {
      final s = classify(e, online: online);
      return ProbeResult(name, s,
          detail: s == ProbeStatus.needsIndex ? indexDetail(e) : '', consoleLink: s == ProbeStatus.needsIndex ? indexLink(e) : null, ms: sw.elapsedMilliseconds);
    }
  }

  /// The main list queries of a role, built by the same services the screens use. Each reads the first answer only.
  static List<(String, Future<Object?> Function())> probesFor(String? role) {
    Future<Object?> first(Stream<Object?> s) => s.first;
    final common = <(String, Future<Object?> Function())>[
      ('notifications', () => first(NotificationService.watchMine())),
      ('support tickets', () => first(SupportService.watchMine())),
    ];
    final lr = <(String, Future<Object?> Function())>[
      ('LR register: my LRs', () => first(LrService.watchMine())),
      ('LR register: my share links', () => first(LrService.watchMyShares())),
    ];
    return switch (role) {
      'driver' => [
          ('open loads', () => first(LoadService.watchOpen())),
          ('my bookings', () => first(BookingService.watchForDriver())),
          ('my offers', () => first(OfferService.watchMine())),
          ...lr,
          ...common,
        ],
      'fleet' => [
          ('my loads', () => first(LoadService.watchMine())),
          ('fleet bookings', () => first(FleetService.watchFleetBookings())),
          ('my fleets', () => first(FleetService.watchMyFleets())),
          ...lr,
          ...common,
        ],
      _ => [
          ('my loads', () => first(LoadService.watchMine())),
          ('my bookings', () => first(BookingService.watchForCustomer())),
          ('offers on my loads', () => first(OfferService.watchForCustomer())),
          ...lr,
          ...common,
        ],
    };
  }

  static Future<List<ProbeResult>> runAll(List<(String, Future<Object?> Function())> probes, {Duration timeout = const Duration(seconds: 6), bool online = true}) async {
    final out = <ProbeResult>[];
    for (final (name, run) in probes) {
      out.add(await probe(name, run, timeout: timeout, online: online));
    }
    return out;
  }

  /// The text the owner copies and sends. Everything goes through [Redactor]; no phone numbers, tokens or ids.
  /// The console link of an index error is kept (it only names the project and the index).
  static String report({
    required List<ProbeResult> results,
    required Features features,
    required bool online,
    String platform = '',
    String? role,
    String projectId = '',
  }) {
    final b = StringBuffer()
      ..writeln('Load 20 diagnose report')
      ..writeln('project: ${projectId.isEmpty ? DefaultFirebaseOptions.currentPlatform.projectId : projectId}')
      ..writeln('app version: $appVersion')
      ..writeln('platform: ${Redactor.clean(platform)}')
      ..writeln('role: ${role ?? 'unknown'}')
      ..writeln('network: ${online ? 'online' : 'offline'}')
      ..writeln('server time difference: not measured (needs a write; this screen never writes)')
      ..writeln('queries:');
    for (final r in results) {
      b.writeln('- ${Redactor.clean(r.name)}: ${r.status.code ?? 'OK'} (${r.ms} ms)${r.detail.isEmpty ? '' : ' ${Redactor.clean(r.detail)}'}');
      if (r.consoleLink != null) b.writeln('  index link: ${r.consoleLink}');
    }
    b.writeln('flags:');
    b.writeln('- pilotMode: ${features.pilotMode}');
    for (final spec in Features.registry) {
      b.writeln('- ${spec.key}: ${features.isOn(spec.key)}');
    }
    return b.toString();
  }
}
