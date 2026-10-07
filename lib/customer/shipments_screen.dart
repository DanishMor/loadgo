import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/enterprise/shipment_timeline.dart';
import '../core/enterprise/validators.dart';
import '../core/l10n/l10n.dart';
import '../core/models/enterprise.dart';
import '../core/models/handover.dart';
import '../core/services/handover_service.dart';
import '../core/models/risk.dart';
import '../core/services/enterprise_service.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';
import '../core/widgets/logistics_labels.dart';
import 'trade_hub_picker.dart';

String legStageLabel(BuildContext context, LegStage s) => tr(context, switch (s) {
      LegStage.posted => 'stepPosted',
      LegStage.assigned => 'stepAssigned',
      LegStage.inTransit => 'stepInTransit',
      LegStage.delivered => 'stepDelivered',
      LegStage.cancelled => 'legCancelled',
    });

String shipmentKindLabel(BuildContext context, String kind) => tr(context, kind == Shipment.import ? 'shipImport' : 'shipExport');

/// Customer's two-leg import/export shipments.
class ShipmentsScreen extends StatelessWidget {
  const ShipmentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'shipments'))),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('newShipment'),
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NewShipmentScreen())),
        icon: const Icon(Icons.add_rounded),
        label: Text(tr(context, 'newShipment')),
      ),
      body: LiveStream<List<Shipment>>(
        stream: EnterpriseService.watchShipments,
        builder: (context, list) {
          if (list.isEmpty) return EmptyState(icon: Icons.sync_alt_rounded, title: tr(context, 'noShipments'));
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final s = list[i];
              return ListTile(
                key: ValueKey('shipment_${s.id}'),
                title: Text('${s.origin} → ${s.hub} → ${s.destination}'),
                subtitle: Text([shipmentKindLabel(context, s.kind), s.containerNumber].where((e) => e.isNotEmpty).join(' · ')),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ShipmentDetailScreen(shipment: s))),
              );
            },
          );
        },
      ),
    );
  }
}

class NewShipmentScreen extends StatefulWidget {
  const NewShipmentScreen({super.key});

  @override
  State<NewShipmentScreen> createState() => _NewShipmentScreenState();
}

class _NewShipmentScreenState extends State<NewShipmentScreen> {
  final _form = GlobalKey<FormState>();
  String _kind = Shipment.export;
  final _origin = TextEditingController();
  final _hub = TextEditingController();
  final _destination = TextEditingController();
  final _cargo = TextEditingController(text: 'General');
  final _weight = TextEditingController();
  final _container = TextEditingController();
  final _seal = TextEditingController();
  String _vehicleType = '20ft';
  DateTime _date1 = DateTime.now().add(const Duration(days: 1));
  DateTime _date2 = DateTime.now().add(const Duration(days: 3));
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_origin, _hub, _destination, _cargo, _weight, _container, _seal]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickHub() async {
    final h = await pickTradeHub(context);
    if (h != null) setState(() => _hub.text = h.place);
  }

  Future<void> _pickDate(bool first) async {
    final d = await showDatePicker(
      context: context,
      initialDate: first ? _date1 : _date2,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null) setState(() => first ? _date1 = d : _date2 = d);
  }

  String? _required(String? v) => (v == null || v.trim().length < 2) ? tr(context, 'fieldRequired') : null;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await EnterpriseService.createTwoLeg(
        kind: _kind,
        origin: _origin.text,
        hub: _hub.text,
        destination: _destination.text,
        cargoType: _cargo.text.trim().isEmpty ? 'General' : _cargo.text.trim(),
        weight: num.parse(_weight.text.trim()),
        vehicleType: _vehicleType,
        leg1Date: _date1,
        leg2Date: _date2.isBefore(_date1) ? _date1 : _date2,
        containerNumber: _container.text,
        sealNumber: _seal.text,
      );
      if (!mounted) return;
      showSnack(context, tr(context, 'shipCreated'));
      Navigator.of(context).pop();
    } on AccountRestrictedException {
      if (!mounted) return;
      setState(() => _busy = false);
      showSnack(context, tr(context, 'accountRestricted'));
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      showSnack(context, tr(context, 'somethingWrong'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'newShipment'))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _form,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SegmentedButton<String>(
              key: const ValueKey('shipKind'),
              segments: [
                ButtonSegment(value: Shipment.export, label: Text(tr(context, 'shipExport'))),
                ButtonSegment(value: Shipment.import, label: Text(tr(context, 'shipImport'))),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
            const SizedBox(height: 12),
            TextFormField(
                key: const ValueKey('shipOrigin'),
                controller: _origin,
                decoration: InputDecoration(labelText: tr(context, 'shipOrigin')),
                validator: _required, inputFormatters: [LengthLimitingTextInputFormatter(100)]),
            TextFormField(
              key: const ValueKey('shipHub'),
              controller: _hub,
              decoration: InputDecoration(
                labelText: tr(context, 'shipHub'),
                suffixIcon: IconButton(
                  key: const ValueKey('pickHub'),
                  tooltip: tr(context, 'pickPortIcd'),
                  icon: const Icon(Icons.directions_boat_rounded),
                  onPressed: _pickHub,
                ),
              ),
              validator: _required, inputFormatters: [LengthLimitingTextInputFormatter(100)]),
            TextFormField(
                key: const ValueKey('shipDestination'),
                controller: _destination,
                decoration: InputDecoration(labelText: tr(context, 'shipDestination')),
                validator: _required, inputFormatters: [LengthLimitingTextInputFormatter(100)]),
            TextFormField(controller: _cargo, decoration: InputDecoration(labelText: tr(context, 'cargoType')), inputFormatters: [LengthLimitingTextInputFormatter(100)]),
            TextFormField(
              key: const ValueKey('shipWeight'),
              controller: _weight,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: tr(context, 'weightTons')),
              validator: (v) {
                final n = num.tryParse(v?.trim() ?? '');
                return (n == null || n <= 0 || n > 100) ? tr(context, 'invalidNumber') : null;
              }, inputFormatters: [LengthLimitingTextInputFormatter(10)]),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _vehicleType,
              decoration: InputDecoration(labelText: tr(context, 'vehicleTypeNeeded')),
              items: vehicleTypeItems(context, keep: _vehicleType),
              onChanged: (v) => setState(() => _vehicleType = v ?? _vehicleType),
            ),
            TextFormField(
              key: const ValueKey('shipContainer'),
              controller: _container,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(labelText: tr(context, 'containerNumber')),
              validator: (v) => (v ?? '').trim().isEmpty || isValidContainerNumber(normaliseContainer(v!)) ? null : tr(context, 'containerInvalid'), inputFormatters: [LengthLimitingTextInputFormatter(30)]),
            TextFormField(
              key: const ValueKey('shipSeal'),
              controller: _seal,
              decoration: InputDecoration(labelText: tr(context, 'sealNumber')),
              validator: (v) => (v ?? '').trim().isEmpty || isValidSealNumber(v!) ? null : tr(context, 'sealInvalid'), inputFormatters: [LengthLimitingTextInputFormatter(30)]),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_rounded),
              title: Text(trf(context, 'legDate', {'n': 1})),
              trailing: Text(formatDate(_date1)),
              onTap: () => _pickDate(true),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_rounded),
              title: Text(trf(context, 'legDate', {'n': 2})),
              trailing: Text(formatDate(_date2)),
              onTap: () => _pickDate(false),
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const ValueKey('shipSubmit'),
              onPressed: _busy ? null : _submit,
              child: Text(tr(context, 'newShipment')),
            ),
          ]),
        ),
      ),
    );
  }
}

/// The eight-step timeline of a shipment.
class ShipmentDetailScreen extends StatelessWidget {
  final Shipment shipment;
  const ShipmentDetailScreen({super.key, required this.shipment});

  @override
  Widget build(BuildContext context) {
    final s = shipment;
    return Scaffold(
      appBar: AppBar(title: Text('${shipmentKindLabel(context, s.kind)} · ${s.containerNumber.isEmpty ? s.id : s.containerNumber}')),
      body: FutureBuilder<ShipmentLegs>(
        future: EnterpriseService.legsOf(s),
        builder: (context, snap) {
          if (snap.hasError) return ErrorState(error: snap.error);
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final legs = snap.data!;
          return ListView(padding: const EdgeInsets.all(16), children: [
            Text('${s.origin} → ${s.hub} → ${s.destination}', style: const TextStyle(fontWeight: FontWeight.w800)),
            if (s.sealNumber.isNotEmpty) Text('${tr(context, 'sealNumber')}: ${s.sealNumber}'),
            if (legs.complete)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: StatusChip(label: tr(context, 'shipComplete'), color: AppColors.success),
              ),
            StreamBuilder<Handover?>(
              stream: HandoverService.watch(s.id),
              builder: (context, h) {
                final v = h.data;
                if (v == null) return const SizedBox.shrink();
                final key = v.complete ? (v.sealMatches ? 'hoDone' : 'hoSealDiffers') : 'hoLeg1Done';
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('${tr(context, 'hoTitle')}: ${tr(context, key)}', key: const ValueKey('shipmentHandover'), style: TextStyle(color: v.complete && !v.sealMatches ? AppColors.warning : AppColors.muted)),
                );
              },
            ),
            const SizedBox(height: 12),
            for (final (i, step) in legs.timeline.indexed)
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (i % 4 == 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: Text(
                      '${trf(context, 'legLabel', {'n': step.leg})}: ${step.leg == 1 ? '${s.origin} → ${s.hub}' : '${s.hub} → ${s.destination}'}',
                      style: TextStyle(color: AppColors.muted),
                    ),
                  ),
                ListTile(
                  key: ValueKey('step_${step.leg}_${step.stage.name}'),
                  dense: true,
                  leading: Icon(
                    switch (step.state) {
                      TimelineState.done => Icons.check_circle_rounded,
                      TimelineState.current => Icons.radio_button_checked_rounded,
                      TimelineState.cancelled => Icons.cancel_rounded,
                      TimelineState.pending => Icons.radio_button_unchecked_rounded,
                    },
                    color: switch (step.state) {
                      TimelineState.done => AppColors.success,
                      TimelineState.current => AppColors.primary,
                      TimelineState.cancelled => Colors.redAccent,
                      TimelineState.pending => AppColors.muted,
                    },
                  ),
                  title: Text(legStageLabel(context, step.stage)),
                ),
              ]),
          ]);
        },
      ),
    );
  }
}

