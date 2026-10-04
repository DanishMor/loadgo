import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/models/risk.dart';
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
  String? _type;

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  TruckFilter get _filter => TruckFilter(from: _from.text, to: _to.text, vehicleType: _type);

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
            TextField(key: const ValueKey('reqPickup'), controller: pickup, decoration: InputDecoration(labelText: tr(c, 'pickupLocation'))),
            TextField(key: const ValueKey('reqDrop'), controller: drop, decoration: InputDecoration(labelText: tr(c, 'dropLocation'))),
            TextField(key: const ValueKey('reqWeight'), controller: weight, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: tr(c, 'weightTons'))),
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
              Expanded(child: TextField(key: const ValueKey('boardFrom'), controller: _from, onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: tr(context, 'routeFrom')))),
              const SizedBox(width: 8),
              Expanded(child: TextField(key: const ValueKey('boardTo'), controller: _to, onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: tr(context, 'routeTo')))),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: DropdownButtonFormField<String?>(
              key: const ValueKey('boardType'),
              initialValue: _type,
              items: [
                DropdownMenuItem(value: null, child: Text(tr(context, 'allTypes'))),
                for (final t in VehicleTypeService.ids) DropdownMenuItem(value: t, child: Text(vehicleTypeLabel(context, t))),
              ],
              onChanged: (v) => setState(() => _type = v),
            ),
          ),
          Expanded(
            child: LiveStream<List<TruckPost>>(
              stream: () => _posts,
              builder: (context, all) {
                final list = [for (final p in all) if (_filter.matches(p)) p];
                if (list.isEmpty) return EmptyState(icon: Icons.local_shipping_outlined, title: tr(context, 'noEmptyTrucks'));
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final p = list[i];
                    return AppCard(
                      key: ValueKey('truckPost_${p.id}'),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        RouteText(pickup: p.fromCity, drop: p.toCity),
                        const SizedBox(height: 6),
                        Text('${vehicleTypeLabel(context, p.vehicleType)} • ${formatNum(p.capacity)} T • ${p.vehicleNumber} • ${formatDate(p.availableDate)}',
                            style: const TextStyle(color: AppColors.muted)),
                        if (p.driverName.isNotEmpty) Text(p.driverName, style: const TextStyle(fontWeight: FontWeight.w700)),
                        if (p.note.isNotEmpty) Text(p.note, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
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
                    Text('${formatNum(r.weight)} T${r.note.isEmpty ? '' : ' • ${r.note}'}', style: const TextStyle(color: AppColors.muted)),
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
