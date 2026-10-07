import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/risk/risk_rules.dart';
import '../core/services/admin_service.dart';
import '../core/services/device_service.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';

/// Admin > Risk signals: new-device and high-value signals, devices shared
/// by many accounts, and a random sample of approved drivers for spot checks.
class AdminSignalsScreen extends StatelessWidget {
  const AdminSignalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr(context, 'adminSignals')),
          bottom: TabBar(tabs: [
            Tab(text: tr(context, 'signalsTab')),
            Tab(text: tr(context, 'sharedDevicesTab')),
            Tab(text: tr(context, 'randomCheckTab')),
          ]),
        ),
        body: const TabBarView(children: [_SignalsTab(), _SharedDevicesTab(), _RandomCheckTab()]),
      ),
    );
  }
}

class _SignalsTab extends StatelessWidget {
  const _SignalsTab();

  @override
  Widget build(BuildContext context) {
    return LiveStream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      stream: DeviceService.watchRiskSignals,
      builder: (context, docs) {
        if (docs.isEmpty) return EmptyState(icon: Icons.shield_outlined, title: tr(context, 'noSignals'));
        return ListView(padding: const EdgeInsets.all(16), children: [
          for (final d in docs)
            ListTile(
              key: ValueKey('signal_${d.id}'),
              leading: Icon(d.data()['type'] == 'high_value' ? Icons.payments_outlined : Icons.devices_other_rounded, color: AppColors.warning),
              title: Text('${tr(context, 'signal_${d.data()['type']}')} · ${d.data()['uid']}'),
              subtitle: Text([
                if (d.data()['amountPaise'] != null) formatPaise((d.data()['amountPaise'] as num).toInt()),
                if (d.data()['note'] != null) '${d.data()['note']}',
                if (d.data()['createdAt'] is Timestamp) formatDateTime((d.data()['createdAt'] as Timestamp).toDate()),
              ].join(' · ')),
            ),
        ]);
      },
    );
  }
}

class _SharedDevicesTab extends StatelessWidget {
  const _SharedDevicesTab();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<SharedDevice>>(
      future: DeviceService.sharedDevices(),
      builder: (context, snap) {
        if (snap.hasError) return ErrorState(error: snap.error);
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final list = snap.data!;
        if (list.isEmpty) return EmptyState(icon: Icons.devices_rounded, title: tr(context, 'noSharedDevices'));
        return ListView(padding: const EdgeInsets.all(16), children: [
          for (final d in list)
            ListTile(
              key: ValueKey('shared_${d.deviceId}'),
              title: Text(trf(context, 'accountsOnDevice', {'n': d.uids.length})),
              subtitle: Text(d.uids.join(', ')),
            ),
        ]);
      },
    );
  }
}

class _RandomCheckTab extends StatefulWidget {
  const _RandomCheckTab();

  @override
  State<_RandomCheckTab> createState() => _RandomCheckTabState();
}

class _RandomCheckTabState extends State<_RandomCheckTab> {
  List<DriverVerification> _sample = const [];
  bool _loaded = false;

  Future<void> _draw() async {
    final approved = await AdminService.watchDrivers(AdminService.approved).first;
    if (!mounted) return;
    setState(() {
      _sample = RiskRules.randomSample(approved, 5);
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      FilledButton.icon(key: const ValueKey('drawSample'), onPressed: _draw, icon: const Icon(Icons.casino_outlined), label: Text(tr(context, 'drawSample'))),
      const SizedBox(height: 8),
      if (_loaded && _sample.isEmpty) Text(tr(context, 'noDriversHere')),
      for (final d in _sample)
        ListTile(
          key: ValueKey('sample_${d.uid}'),
          title: Text(d.name.isEmpty ? d.uid : d.name),
          subtitle: Text('${d.phone} · ${d.vehicleNumber}'),
          trailing: TextButton(
            key: ValueKey('reverify_${d.uid}'),
            onPressed: () async {
              await AdminService.setStatus(d.uid, AdminService.pending);
              if (mounted) setState(() => _sample = [for (final x in _sample) if (x.uid != d.uid) x]);
            },
            child: Text(tr(context, 'sendToReverify')),
          ),
        ),
    ]);
  }
}
