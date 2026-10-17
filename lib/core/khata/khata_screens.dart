import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../errors/error_text.dart';
import '../l10n/l10n.dart';
import '../services/khata_service.dart';
import '../theme/design_tokens.dart';
import '../widgets/common.dart';
import '../widgets/ds/app_button.dart';
import '../widgets/ds/app_dialogs.dart';
import '../widgets/ds/app_top_bar.dart';
import '../widgets/ds/money_text.dart';
import '../widgets/live_stream.dart';
import '../widgets/logistics_labels.dart' show askPricePaise;
import 'khata_models.dart';

/// G23: "Khata": who owes me and whom I owe. A private notebook (records only). Behind the `khata` switch.
class KhataScreen extends StatefulWidget {
  final Stream<List<KhataParty>>? source;
  const KhataScreen({super.key, this.source});

  @override
  State<KhataScreen> createState() => _KhataScreenState();
}

class _KhataScreenState extends State<KhataScreen> {
  List<KhataParty> _last = const [];

  Future<void> _addParty() async {
    final name = TextEditingController();
    final note = TextEditingController();
    final ok = await showAppDialog<bool>(
      context,
      title: tr(context, 'khataAddParty'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(key: const ValueKey('khataPartyName'), controller: name, maxLength: KhataParty.maxName, decoration: InputDecoration(labelText: tr(context, 'khataPartyName'))),
        TextField(key: const ValueKey('khataPartyNote'), controller: note, maxLength: KhataParty.maxNote, decoration: InputDecoration(labelText: tr(context, 'khataNote'))),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr(context, 'cancel'))),
        FilledButton(key: const ValueKey('khataPartySave'), onPressed: () => Navigator.pop(context, true), child: Text(tr(context, 'save'))),
      ],
    );
    if (ok != true || name.text.trim().isEmpty) return;
    try {
      await KhataService.addParty(name.text, note: note.text, currentCount: _last.length);
    } catch (e) {
      if (mounted) showSnack(context, e is StateError ? tr(context, 'khataTooMany') : errorText(context, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Scaffold(
      appBar: AppTopBar(title: tr(context, 'khataTitle')),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('khataAddPartyButton'),
        onPressed: _addParty,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: Text(tr(context, 'khataAddParty')),
      ),
      body: LiveStream<List<KhataParty>>(
        stream: () => widget.source ?? KhataService.watchParties(),
        builder: (context, parties) {
          _last = parties;
          if (parties.isEmpty) {
            return EmptyState(icon: Icons.menu_book_outlined, title: tr(context, 'khataEmpty'), subtitle: tr(context, 'khataEmptyHint'));
          }
          final t = KhataBook.totals(parties);
          // A builder, not a list of children: a book can hold up to 100 parties. Row 0 is the totals, the last row the note.
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(DsSpace.s4, DsSpace.s4, DsSpace.s4, 96),
            itemCount: parties.length + 2,
            itemBuilder: (context, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: DsSpace.s3),
                  child: AppCard(
                    key: const ValueKey('khataTotals'),
                    child: Row(children: [
                      Expanded(child: _total(context, 'khataTheyOwe', t.theyOwe, c.success)),
                      const SizedBox(width: DsSpace.s3),
                      Expanded(child: _total(context, 'khataIOwe', t.iOwe, c.error)),
                    ]),
                  ),
                );
              }
              if (i == parties.length + 1) {
                return Padding(
                  padding: const EdgeInsets.only(top: DsSpace.s2),
                  child: Text(tr(context, 'khataRecordsOnly'), style: DsType.caption.copyWith(color: c.textHint)),
                );
              }
              final p = parties[i - 1];
              return Padding(
                padding: const EdgeInsets.only(bottom: DsSpace.s2),
                child: AppCard(
                  key: ValueKey('khataParty_${p.id}'),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => KhataPartyScreen(party: p))),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(p.name, style: DsType.subtitle),
                        if (p.note.isNotEmpty) Text(p.note, style: DsType.caption.copyWith(color: c.textMuted)),
                      ]),
                    ),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      MoneyText(p.balancePaise.abs(), color: p.balancePaise > 0 ? c.success : (p.balancePaise < 0 ? c.error : c.textMuted)),
                      Text(tr(context, p.balancePaise > 0 ? 'khataTheyOwe' : (p.balancePaise < 0 ? 'khataIOwe' : 'khataSettled')), style: DsType.caption.copyWith(color: c.textMuted)),
                    ]),
                  ]),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _total(BuildContext context, String key, int paise, Color color) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr(context, key), style: DsType.caption.copyWith(color: context.ds.textMuted)),
        MoneyText(paise, size: MoneySize.large, color: color),
      ]);
}

/// One party: the lines, add "owed" / "received", share the statement, delete a wrong line.
class KhataPartyScreen extends StatelessWidget {
  final KhataParty party;
  final Stream<List<KhataEntry>>? source;
  const KhataPartyScreen({super.key, required this.party, this.source});

  Future<void> _add(BuildContext context, String kind) async {
    final paise = await askPricePaise(context, title: tr(context, kind == KhataEntryKind.owed ? 'khataAddOwed' : 'khataAddReceived'), label: tr(context, 'khataAmount'));
    if (paise == null || !context.mounted) return;
    try {
      await KhataService.addEntry(party.id, kind: kind, amountPaise: paise, date: DateTime.now());
    } catch (e) {
      if (context.mounted) showSnack(context, errorText(context, e));
    }
  }

  Future<void> _delete(BuildContext context, KhataEntry e) async {
    final ok = await showConfirmDialog(context, title: tr(context, 'khataDeleteLine'), message: tr(context, 'khataDeleteLineHint'), danger: true);
    if (ok != true) return;
    try {
      await KhataService.deleteEntry(party.id, e);
    } catch (err) {
      if (context.mounted) showSnack(context, errorText(context, err));
    }
  }

  Future<void> _share(BuildContext context, List<KhataEntry> entries) async {
    final text = KhataBook.statementText(
      partyName: party.name,
      entries: entries,
      money: (p) => MoneyText.format(p),
      date: (d) => formatDate(d),
      owedLabel: tr(context, 'khataOwedWord'),
      receivedLabel: tr(context, 'khataReceivedWord'),
      balanceLabel: tr(context, 'khataBalanceWord'),
    );
    try {
      await SharePlus.instance.share(ShareParams(text: text));
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
      if (context.mounted) showSnack(context, tr(context, 'khataCopied'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return LiveStream<List<KhataEntry>>(
      stream: () => source ?? KhataService.watchEntries(party.id),
      builder: (context, entries) {
        final bal = KhataBook.balance(entries);
        return Scaffold(
          appBar: AppTopBar(
            title: party.name,
            actions: [
              IconButton(key: const ValueKey('khataShare'), tooltip: tr(context, 'khataShare'), icon: const Icon(Icons.share_outlined), onPressed: entries.isEmpty ? null : () => _share(context, entries)),
            ],
          ),
          // A builder: a party can have hundreds of lines. Row 0 is the balance and the two buttons, then the lines.
          body: ListView.builder(
            padding: const EdgeInsets.all(DsSpace.s4),
            itemCount: entries.isEmpty ? 2 : entries.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) {
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  AppCard(
                    key: const ValueKey('khataBalance'),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(tr(context, bal > 0 ? 'khataTheyOwe' : (bal < 0 ? 'khataIOwe' : 'khataSettled')), style: DsType.caption.copyWith(color: c.textMuted)),
                      MoneyText(bal.abs(), size: MoneySize.large, color: bal > 0 ? c.success : (bal < 0 ? c.error : c.text)),
                    ]),
                  ),
                  const SizedBox(height: DsSpace.s3),
                  Row(children: [
                    Expanded(child: AppButton(key: const ValueKey('khataOwed'), label: tr(context, 'khataAddOwed'), icon: Icons.add_rounded, onPressed: () => _add(context, KhataEntryKind.owed))),
                    const SizedBox(width: DsSpace.s2),
                    Expanded(child: AppButton(key: const ValueKey('khataReceived'), label: tr(context, 'khataAddReceived'), icon: Icons.remove_rounded, kind: AppButtonKind.secondary, onPressed: () => _add(context, KhataEntryKind.received))),
                  ]),
                  const SizedBox(height: DsSpace.s3),
                ]);
              }
              if (entries.isEmpty) return Padding(padding: const EdgeInsets.all(DsSpace.s4), child: Text(tr(context, 'khataNoLines'), textAlign: TextAlign.center, style: DsType.body.copyWith(color: c.textMuted)));
              final e = entries[i - 1];
              return ListTile(
                key: ValueKey('khataEntry_${e.id}'),
                contentPadding: EdgeInsets.zero,
                title: MoneyText(e.amountPaise, signed: false, color: e.kind == KhataEntryKind.owed ? c.success : c.error),
                subtitle: Text('${formatDate(e.date)}${e.note.isEmpty ? '' : ' • ${e.note}'}'),
                leading: Icon(e.kind == KhataEntryKind.owed ? Icons.call_made_rounded : Icons.call_received_rounded, color: e.kind == KhataEntryKind.owed ? c.success : c.error),
                trailing: IconButton(tooltip: tr(context, 'khataDeleteLine'), icon: const Icon(Icons.delete_outline_rounded), onPressed: () => _delete(context, e)),
              );
            },
          ),
        );
      },
    );
  }
}
