import '../errors/error_text.dart';
import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../services/device_service.dart';
import '../widgets/common.dart';
import '../widgets/live_stream.dart';

/// Settings > My devices: where the account is signed in, trust / revoke a
/// device, and "log out everywhere".
class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  String? _mine;

  @override
  void initState() {
    super.initState();
    DeviceService.deviceId().then((id) {
      if (mounted) setState(() => _mine = id);
    });
  }

  Future<void> _run(Future<void> Function() f) async {
    try {
      await f();
    } catch (error) {
      if (mounted) showSnack(context, errorText(context, error));
    }
  }

  Future<void> _everywhere() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr(c, 'logOutEverywhere')),
        content: Text(tr(c, 'logOutEverywhereConfirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr(c, 'cancel'))),
          FilledButton(key: const ValueKey('everywhereConfirm'), onPressed: () => Navigator.pop(c, true), child: Text(tr(c, 'logOutEverywhere'))),
        ],
      ),
    );
    if (ok == true) {
      await _run(DeviceService.logOutEverywhere);
      if (mounted) showSnack(context, tr(context, 'loggedOutEverywhere'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'myDevices'))),
      body: LiveStream<List<UserDevice>>(
        stream: DeviceService.watchMine,
        builder: (context, devices) => ListView(padding: const EdgeInsets.all(16), children: [
          if (devices.isEmpty) Text(tr(context, 'noDevices')),
          for (final d in devices)
            AppCard(
              key: ValueKey('device_${d.id}'),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text('${d.label}${d.id == _mine ? ' · ${tr(context, 'thisDevice')}' : ''}', style: const TextStyle(fontWeight: FontWeight.w800))),
                  if (d.revoked)
                    StatusChip(label: tr(context, 'deviceRevoked'), color: Colors.redAccent)
                  else if (d.trusted)
                    StatusChip(label: tr(context, 'deviceTrusted'), color: AppColors.success)
                  else
                    StatusChip(label: tr(context, 'deviceNew'), color: AppColors.warning),
                ]),
                if (d.lastSeenAt != null) Text(formatDateTime(d.lastSeenAt!), style: TextStyle(color: AppColors.muted, fontSize: 12)),
                if (!d.revoked)
                  Row(children: [
                    if (!d.trusted) TextButton(key: ValueKey('trust_${d.id}'), onPressed: () => _run(() => DeviceService.trust(d.id)), child: Text(tr(context, 'deviceTrust'))),
                    if (d.id != _mine) TextButton(key: ValueKey('revoke_${d.id}'), onPressed: () => _run(() => DeviceService.revoke(d.id)), child: Text(tr(context, 'deviceRevoke'))),
                  ]),
              ]),
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const ValueKey('logOutEverywhere'),
            onPressed: _everywhere,
            icon: const Icon(Icons.devices_other_rounded),
            label: Text(tr(context, 'logOutEverywhere')),
          ),
        ]),
      ),
    );
  }
}
