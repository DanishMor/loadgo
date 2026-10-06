import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_control/app_control.dart';
import '../l10n/l10n.dart';
import '../services/app_control_service.dart';
import 'common.dart';

/// Wraps the app shell: shows the force-update or maintenance screen instead
/// of [child] when [AppControl] asks for it. The default never blocks.
class AppControlGate extends StatelessWidget {
  final Widget child;
  final int? currentCode;

  const AppControlGate({super.key, required this.child, this.currentCode});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppControl>(
        valueListenable: AppControlService.notifier,
        builder: (context, c, _) {
          if (VersionGate.needsUpdate(currentCode ?? AppControlService.currentCode, c.minVersionCode)) {
            return const ForceUpdateScreen();
          }
          if (c.maintenance) return MaintenanceScreen(message: c.maintenanceMessage);
          return child;
        },
      );
}

const _playUrl = 'https://play.google.com/store/apps/details?id=com.example.transport_app';

class ForceUpdateScreen extends StatelessWidget {
  const ForceUpdateScreen({super.key});

  @override
  Widget build(BuildContext context) => _BlockScreen(
        icon: Icons.system_update,
        title: tr(context, 'updateRequiredTitle'),
        body: tr(context, 'updateRequiredBody'),
        action: FilledButton(
          onPressed: () async {
            try {
              await launchUrl(Uri.parse(_playUrl), mode: LaunchMode.externalApplication);
            } catch (_) {}
          },
          child: Text(tr(context, 'updateNow')),
        ),
      );
}

class MaintenanceScreen extends StatelessWidget {
  final String message;
  const MaintenanceScreen({super.key, this.message = ''});

  @override
  Widget build(BuildContext context) => _BlockScreen(
        icon: Icons.construction,
        title: tr(context, 'maintenanceTitle'),
        body: message.trim().isEmpty ? tr(context, 'maintenanceDefault') : message,
      );
}

class _BlockScreen extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  const _BlockScreen({required this.icon, required this.title, required this.body, this.action});

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.background,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 64, color: AppColors.primary),
                  const SizedBox(height: 16),
                  Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 12),
                  Text(body, textAlign: TextAlign.center),
                  if (action != null) ...[const SizedBox(height: 24), action!],
                ],
              ),
            ),
          ),
        ),
      );
}
