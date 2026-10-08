import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/l10n/l10n.dart';
import '../core/models/risk.dart';
import '../core/models/saved_search.dart';
import '../core/widgets/saved_search_menu.dart';
import '../core/models/truck_board.dart';
import '../core/services/truck_board_service.dart';
import '../core/services/vehicle_type_service.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';
import '../core/widgets/logistics_labels.dart';
import 'post_load_screen.dart';

String truckBoardErrorKey(Object e) {
  if (e is AccountRestrictedException) return 'accountRestricted';
  if (e is TruckBoardException) {
    return switch (e.reason) {
      'own_post' => 'truckOwnPost',
      'closed' => 'truckPostClosed',
      _ => 'truckRequestInvalid',
    };
  }
  return 'somethingWrong';
}

/// Customer: browse drivers' empty trucks and send a request.
class TruckBoardScreen extends StatefulWidget {
  /// Injectable for tests.
  final Stream<List<TruckPost>>? posts;
  const TruckBoardScreen({super.key, this.posts});

  @override
  State<TruckBoardScreen> createState() => _TruckBoardScreenState();
}

class _TruckBoardScreenState extends State<TruckBoardScreen> {
  late final Stream<List<TruckPost>> _posts = (widget.posts ?? TruckBoardService.watchOpenBoard()).asBroadcastStream();
  final _from = TextEditingController();
  final _to = TextEditingController();
  final _capacity = TextEditingController();
  String? _type;
  DateTime? _after;
  DateTime? _before;

  /// Cards shown so far; "Load more" adds another page.
  int _shown = _boardPage;
  static const _boardPage = 20;

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    _capacity.dispose();
    super.dispose();
  }

  TruckFilter get _filter {
    final cap = num.tryParse(_capacity.text.trim());
    return TruckFilter(
      from: _from.text,
      to: _to.text,
      vehicleType: _type,
      onOrAfter: _after,
      onOrBefore: _before,
      minCapacity: cap == null || cap <= 0 ? null : cap,
    );
  }

  void _apply(Map<String, dynamic> m) {
    final f = TruckFilter.fromMap(m);
    _from.text = f.from;
    _to.text = f.to;
    _capacity.text = f.minCapacity == null ? '' : formatNum(f.minCapacity!);
    setState(() {
      _type = f.vehicleType;
      _after = f.onOrAfter;
      _before = f.onOrBefore;
      _shown = _boardPage;
    });
  }

  Future<void> _pickDate(bool after) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: (after ? _after : _before) ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (d != null) setState(() => after ? _after = d : _before = d);
  }

  Future<void> _request(TruckPost post) async {
    final pickup = TextEditingController(text: post.fromCity);
    final drop = TextEditingController(text: post.toCity);
    final weight = TextEditingController();
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr(c, 'requestTruck')),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(key: const ValueKey('reqPickup'), controller: pickup, decoration: InputDecoration(labelText: tr(c, 'pickupLocation')), inputFormatters: [LengthLimitingTextInputFormatter(100)]),
            TextField(key: const ValueKey('reqDrop'), controller: drop, decoration: InputDecoration(labelText: tr(c, 'dropLocation')), inputFormatters: [LengthLimitingTextInputFormatter(100)]),
            TextField(key: const ValueKey('reqWeight'), controller: weight, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: tr(c, 'weightTons')), inputFormatters: [LengthLimitingTextInputFormatter(10)]),
            TextField(key: const ValueKey('reqNote'), controller: note, maxLength: 200, decoration: InputDecoration(labelText: tr(c, 'noteOptional'))),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr(c, 'cancel'))),
          FilledButton(key: const ValueKey('reqSend'), onPressed: () => Navigator.pop(c, true), child: Text(tr(c, 'sendRequest'))),
        ],
      ),
    );
    final values = (pickup.text, drop.text, num.tryParse(weight.text.trim()), note.text);
    if (ok != true || !mounted) return;
    try {
      await TruckBoardService.sendRequest(post, pickup: values.$1, drop: values.$2, weight: values.$3 ?? 0, note: values.$4);
      if (mounted) showSnack(context, tr(context, 'requestSent'));
    } catch (e) {
      if (mounted) showSnack(context, tr(context, truckBoardErrorKey(e)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text(tr(context, 'emptyTrucks')),
        actions: [
          TextButton(
            key: const ValueKey('myTruckRequests'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyTruckRequestsScreen())),
            child: Text(tr(context, 'myRequests')),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Row(children: [
              Expanded(child: TextField(key: const ValueKey('boardFrom'), controller: _from, onChanged: (_) => setState(() => _shown = _boardPage), decoration: InputDecoration(labelText: tr(context, 'routeFrom')), inputFormatters: [LengthLimitingTextInputFormatter(100)])),
              const SizedBox(width: 8),
              Expanded(child: TextField(key: const ValueKey('boardTo'), controller: _to, onChanged: (_) => setState(() => _shown = _boardPage), decoration: InputDecoration(labelText: tr(context, 'routeTo')), inputFormatters: [LengthLimitingTextInputFormatter(100)])),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: DropdownButtonFormField<String?>(
              isExpanded: true,
              key: const ValueKey('boardType'),
              initialValue: _type,
              items: [
                DropdownMenuItem(value: null, child: Text(tr(context, 'allTypes'))),
                for (final t in VehicleTypeService.ids) DropdownMenuItem(value: t, child: Text(vehicleTypeLabel(context, t))),
              ],
              onChanged: (v) => setState(() => _type = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Column(children: [
              TextField(
                  key: const ValueKey('boardCapacity'),
                  controller: _capacity,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() => _shown = _boardPage),
                  decoration: InputDecoration(labelText: tr(context, 'capacityMin')), inputFormatters: [LengthLimitingTextInputFormatter(10)]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('boardAfter'),
                    onPressed: () => _pickDate(true),
                    child: Text(_after == null ? tr(context, 'filterDateFrom') : formatDate(_after!), overflow: TextOverflow.ellipsis),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('boardBefore'),
                    onPressed: () => _pickDate(false),
                    child: Text(_before == null ? tr(context, 'filterDateTo') : formatDate(_before!), overflow: TextOverflow.ellipsis),
                  ),
                ),
              ]),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SavedSearchMenu(kind: SearchKind.trucks, canSave: !_filter.isEmpty, currentFilter: () => _filter.toMap(), onApply: _apply),
          ),
          Expanded(
            child: LiveStream<List<TruckPost>>(
              stream: () => _posts,
              builder: (context, all) {
                final list = [for (final p in all) if (_filter.matches(p)) p];
                if (list.isEmpty) return EmptyState(icon: Icons.local_shipping_outlined, title: tr(context, 'noEmptyTrucks'));
                final shown = list.length > _shown ? _shown : list.length;
                final more = list.length > shown;
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
                  itemCount: shown + (more ? 1 : 0),
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    if (i == shown) {
                      return OutlinedButton.icon(
                        key: const ValueKey('boardLoadMore'),
                        onPressed: () => setState(() => _shown += _boardPage),
                        icon: const Icon(Icons.expand_more_rounded),
                        label: Text(tr(context, 'loadMore')),
                      );
                    }
                    final p = list[i];
                    return AppCard(
                      key: ValueKey('truckPost_${p.id}'),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        RouteText(pickup: p.fromCity, drop: p.toCity),
                        const SizedBox(height: 6),
                        Text('${vehicleTypeLabel(context, p.vehicleType)} • ${formatNum(p.capacity)} T • ${p.vehicleNumber} • ${formatDate(p.availableDate)}',
                            style: TextStyle(color: AppColors.muted)),
                        if (p.driverName.isNotEmpty) Text(p.driverName, style: const TextStyle(fontWeight: FontWeight.w700)),
                        if (p.note.isNotEmpty) Text(p.note, style: TextStyle(color: AppColors.muted, fontSize: 13)),
                        const SizedBox(height: 8),
                        FilledButton(key: ValueKey('request_${p.id}'), onPressed: () => _request(p), child: Text(tr(context, 'requestTruck'))),
                      ]),
                    );
                  },
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}

/// Customer: requests sent, with their answers. An accepted request offers
/// "Post the load for this driver".
class MyTruckRequestsScreen extends StatelessWidget {
  const MyTruckRequestsScreen({super.key});

  Color _color(String s) => switch (s) {
        TruckRequest.accepted => AppColors.success,
        TruckRequest.declined => Colors.redAccent,
        TruckRequest.withdrawn => AppColors.faint,
        _ => AppColors.warning,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'myRequests'))),
      body: LiveStream<List<TruckRequest>>(
        stream: TruckBoardService.watchMyRequests,
        builder: (context, list) {
          if (list.isEmpty) return EmptyState(icon: Icons.send_outlined, title: tr(context, 'noRequests'));
          return ListView(padding: const EdgeInsets.all(16), children: [
            for (final r in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AppCard(
                  key: ValueKey('myRequest_${r.id}'),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: RouteText(pickup: r.pickup, drop: r.drop)),
                      StatusChip(label: tr(context, 'request_${r.status}'), color: _color(r.status)),
                    ]),
                    Text('${formatNum(r.weight)} T${r.note.isEmpty ? '' : ' • ${r.note}'}', style: TextStyle(color: AppColors.muted)),
                    if (r.status == TruckRequest.accepted)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: FilledButton(
                          key: ValueKey('postFor_${r.id}'),
                          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => PostLoadScreen(repostFrom: r.toLoadDraft(), invitedDriverId: r.driverId),
                          )),
                          child: Text(tr(context, 'postLoadForDriver')),
                        ),
                      ),
                    if (r.status == TruckRequest.pending)
                      TextButton(
                        key: ValueKey('withdraw_${r.id}'),
                        onPressed: () => TruckBoardService.withdrawRequest(r.id),
                        child: Text(tr(context, 'withdrawRequest')),
                      ),
                  ]),
                ),
              ),
          ]);
        },
      ),
    );
  }
}
