import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/l10n/l10n.dart';
import '../core/models/risk.dart';
import '../core/models/truck_board.dart';
import '../core/models/vehicle.dart';
import '../core/services/truck_board_service.dart';
import '../core/services/vehicle_service.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';
import '../core/widgets/logistics_labels.dart';

String _errorKey(Object e) {
  if (e is AccountRestrictedException) return 'accountRestricted';
  if (e is TruckBoardException) {
    return switch (e.reason) {
      'driver_not_verified' => 'truckNeedVerified',
      'route' => 'invalidRoute',
      'date' => 'truckDateInvalid',
      'vehicle' => 'truckVehicleInvalid',
      _ => 'truckRequestInvalid',
    };
  }
  return 'somethingWrong';
}

/// Driver > Empty trucks: post "free from A to B on a date", see my posts
/// and the requests customers sent for them.
class EmptyTrucksScreen extends StatefulWidget {
  const EmptyTrucksScreen({super.key});

  @override
  State<EmptyTrucksScreen> createState() => _EmptyTrucksScreenState();
}

class _EmptyTrucksScreenState extends State<EmptyTrucksScreen> {
  final _from = TextEditingController();
  final _to = TextEditingController();
  final _note = TextEditingController();
  DateTime? _date;
  List<Vehicle> _vehicles = const [];
  String? _vehicleId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    VehicleService.fetchMyActive().then((v) {
      if (mounted) {
        setState(() {
          _vehicles = v;
          _vehicleId = v.isEmpty ? null : v.first.id;
        });
      }
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final d = await showDatePicker(context: context, initialDate: _date ?? today, firstDate: today, lastDate: today.add(const Duration(days: TruckPost.maxDaysAhead)));
    if (d != null && mounted) setState(() => _date = d);
  }

  Future<void> _post() async {
    final vehicle = _vehicles.where((v) => v.id == _vehicleId).firstOrNull;
    if (vehicle == null) return showSnack(context, tr(context, 'truckVehicleInvalid'));
    if (_date == null) return showSnack(context, tr(context, 'truckDateInvalid'));
    setState(() => _busy = true);
    try {
      await TruckBoardService.post(vehicle: vehicle, fromCity: _from.text, toCity: _to.text, date: _date!, note: _note.text);
      _from.clear();
      _to.clear();
      _note.clear();
      if (mounted) showSnack(context, tr(context, 'truckPosted'));
    } catch (e) {
      if (mounted) showSnack(context, tr(context, _errorKey(e)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Color _color(String s) => s == TruckRequest.pending ? AppColors.warning : (s == TruckRequest.accepted ? AppColors.success : AppColors.faint);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(backgroundColor: AppColors.background, title: Text(tr(context, 'emptyTrucks'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 30), children: [
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr(context, 'postEmptyTruck'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            DropdownButtonFormField<String>(
              isExpanded: true,
              key: const ValueKey('truckVehicle'),
              initialValue: _vehicleId,
              hint: Text(tr(context, 'chooseVehicle')),
              items: [for (final v in _vehicles) DropdownMenuItem(value: v.id, child: Text('${v.number} • ${vehicleTypeLabel(context, v.type)}'))],
              onChanged: (v) => setState(() => _vehicleId = v),
            ),
            TextField(key: const ValueKey('truckFrom'), controller: _from, decoration: InputDecoration(labelText: tr(context, 'routeFrom')), inputFormatters: [LengthLimitingTextInputFormatter(100)]),
            TextField(key: const ValueKey('truckTo'), controller: _to, decoration: InputDecoration(labelText: tr(context, 'routeTo')), inputFormatters: [LengthLimitingTextInputFormatter(100)]),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const ValueKey('truckDate'),
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today_rounded),
              label: Text(_date == null ? tr(context, 'availableOn') : formatDate(_date)),
            ),
            TextField(key: const ValueKey('truckNote'), controller: _note, maxLength: 200, decoration: InputDecoration(labelText: tr(context, 'noteOptional'))),
            FilledButton(key: const ValueKey('truckPost'), onPressed: _busy ? null : _post, child: Text(tr(context, 'postEmptyTruck'))),
          ]),
        ),
        const SizedBox(height: 16),
        Text(tr(context, 'requestsForMe'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        LiveStream<List<TruckRequest>>(
          stream: TruckBoardService.watchRequestsForDriver,
          compact: true,
          builder: (context, list) => Column(children: [
            if (list.isEmpty) Padding(padding: const EdgeInsets.all(12), child: Text(tr(context, 'noRequests'))),
            for (final r in list)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: AppCard(
                  key: ValueKey('driverRequest_${r.id}'),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: RouteText(pickup: r.pickup, drop: r.drop)),
                      StatusChip(label: tr(context, 'request_${r.status}'), color: _color(r.status)),
                    ]),
                    Text('${r.customerName.isEmpty ? '' : '${r.customerName} • '}${formatNum(r.weight)} T${r.note.isEmpty ? '' : ' • ${r.note}'}', style: TextStyle(color: AppColors.muted)),
                    if (r.status == TruckRequest.pending)
                      Row(children: [
                        TextButton(key: ValueKey('decline_${r.id}'), onPressed: () => TruckBoardService.answer(r, accept: false), child: Text(tr(context, 'decline'))),
                        FilledButton(key: ValueKey('accept_${r.id}'), onPressed: () => TruckBoardService.answer(r, accept: true), child: Text(tr(context, 'accept'))),
                      ]),
                  ]),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 16),
        Text(tr(context, 'myEmptyTrucks'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        LiveStream<List<TruckPost>>(
          stream: TruckBoardService.watchMyPosts,
          compact: true,
          builder: (context, list) => Column(children: [
            for (final p in list)
              ListTile(
                key: ValueKey('myPost_${p.id}'),
                contentPadding: EdgeInsets.zero,
                title: Text('${p.fromCity} → ${p.toCity}'),
                subtitle: Text('${p.vehicleNumber} • ${formatDate(p.availableDate)}'),
                trailing: p.status == TruckPost.open
                    ? TextButton(key: ValueKey('closePost_${p.id}'), onPressed: () => TruckBoardService.closePost(p.id), child: Text(tr(context, 'closePost')))
                    : StatusChip(label: tr(context, 'postClosed'), color: AppColors.faint),
              ),
          ]),
        ),
      ]),
    );
  }
}
