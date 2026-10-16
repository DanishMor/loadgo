/// Party khata (G23): a private notebook of who owes whom. Records only, not a payment and not a legal account.
/// Money is integer paise. Positive balance = the party owes me; negative = I owe the party.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

class KhataEntryKind {
  KhataEntryKind._();

  /// The party owes me more (I did a trip, I lent, I billed).
  static const owed = 'owed';

  /// The party paid me / I paid the party back (reduces what they owe).
  static const received = 'received';
  static const all = [owed, received];
}

class KhataParty {
  final String id;
  final String name;
  final String note;
  final int balancePaise;
  const KhataParty({required this.id, required this.name, this.note = '', this.balancePaise = 0});

  static const maxName = 40;
  static const maxNote = 60;
  static const maxParties = 100;

  factory KhataParty.fromDoc(String id, Map<String, dynamic>? d) {
    final m = d ?? const <String, dynamic>{};
    final b = m['balancePaise'];
    return KhataParty(
      id: id,
      name: m['name'] is String ? m['name'] as String : '',
      note: m['note'] is String ? m['note'] as String : '',
      balancePaise: b is int && b.abs() <= KhataEntry.maxBalance ? b : 0,
    );
  }
}

class KhataEntry {
  final String id;
  final String kind;
  final int amountPaise;
  final String note;
  final DateTime date;
  const KhataEntry({required this.id, required this.kind, required this.amountPaise, this.note = '', required this.date});

  /// One entry at most ten crore rupees; the balance of a party stays inside a safe range.
  static const maxPaise = 100000000000;
  static const maxBalance = 1000000000000;
  static const maxNote = 60;

  /// What this entry does to the party's balance.
  int get signed => kind == KhataEntryKind.owed ? amountPaise : -amountPaise;

  factory KhataEntry.fromDoc(String id, Map<String, dynamic>? d) {
    final m = d ?? const <String, dynamic>{};
    final a = m['amountPaise'];
    final at = m['date'];
    return KhataEntry(
      id: id,
      kind: m['kind'] == KhataEntryKind.received ? KhataEntryKind.received : KhataEntryKind.owed,
      amountPaise: a is int && a > 0 && a <= maxPaise ? a : 0,
      note: m['note'] is String ? m['note'] as String : '',
      date: at is Timestamp ? at.toDate() : (at is DateTime ? at : DateTime.fromMillisecondsSinceEpoch(0)),
    );
  }
}

class KhataBook {
  KhataBook._();

  static int balance(Iterable<KhataEntry> entries) => entries.fold(0, (s, e) => s + e.signed);

  /// Totals over all parties: what others owe me and what I owe others.
  static ({int theyOwe, int iOwe}) totals(Iterable<KhataParty> parties) {
    var they = 0, mine = 0;
    for (final p in parties) {
      if (p.balancePaise > 0) they += p.balancePaise;
      if (p.balancePaise < 0) mine += -p.balancePaise;
    }
    return (theyOwe: they, iOwe: mine);
  }

  /// A plain-text statement a person can send on WhatsApp. [money] formats paise (the screen passes its formatter).
  static String statementText({required String partyName, required Iterable<KhataEntry> entries, required String Function(int paise) money, required String Function(DateTime) date, String owedLabel = 'Owed', String receivedLabel = 'Received', String balanceLabel = 'Balance'}) {
    final sorted = entries.toList()..sort((a, b) => a.date.compareTo(b.date));
    final buf = StringBuffer(partyName)..writeln();
    for (final e in sorted) {
      buf.writeln('${date(e.date)}  ${e.kind == KhataEntryKind.owed ? owedLabel : receivedLabel}  ${money(e.amountPaise)}${e.note.isEmpty ? '' : '  (${e.note})'}');
    }
    buf.write('$balanceLabel: ${money(balance(sorted))}');
    return buf.toString();
  }
}
