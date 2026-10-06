import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/driver_network.dart';
import '../models/load.dart';
import '../services/backend.dart';
import '../services/chat_service.dart';
import '../services/network_service.dart';
import '../services/rate_limit_service.dart';
import '../widgets/common.dart';
import 'network_logic.dart';

/// Lets a driver send a load card to a connection or a group (D14, CH7).
Future<void> showShareToNetwork(BuildContext context, Load load) async {
  if (!SharedLoad.canShare(load)) {
    showSnack(context, tr(context, 'netOnlyPublic'));
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => _ShareSheet(load: load),
  );
}

class _ShareSheet extends StatelessWidget {
  final Load load;
  const _ShareSheet({required this.load});

  Future<void> _send(BuildContext context, String kind, String id) async {
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    String say(String key) => tr(context, key);
    try {
      await NetworkService.send(kind, id, senderName: await NetworkService.myName(), loadCard: SharedLoad.fromLoad(load));
      nav.pop();
      messenger.showSnackBar(SnackBar(content: Text(say('netShared'))));
    } on RateLimitException catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(trf(context, 'rateLimited', {'m': e.minutesLeft}))));
    } on ChatSendException {
      messenger.showSnackBar(SnackBar(content: Text(say('somethingWrong'))));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(say('somethingWrong'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = Backend.uid ?? '';
    return SafeArea(
      child: StreamBuilder<List<DriverLink>>(
        stream: NetworkService.watchLinks(),
        builder: (context, links) => StreamBuilder<List<DriverGroup>>(
          stream: NetworkService.watchGroups(),
          builder: (context, groups) {
            final conns = [for (final l in links.data ?? const <DriverLink>[]) if (l.connected) l];
            final gs = groups.data ?? const <DriverGroup>[];
            return ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                Text(tr(context, 'netShareTo'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 8),
                if (conns.isEmpty && gs.isEmpty) Padding(padding: const EdgeInsets.all(12), child: Text(tr(context, 'netShareNothing'), style: TextStyle(color: AppColors.muted))),
                for (final g in gs)
                  ListTile(
                    key: ValueKey('shareTo_group_${g.id}'),
                    leading: const Icon(Icons.groups_rounded),
                    title: Text(g.name),
                    onTap: () => _send(context, 'group', g.id),
                  ),
                for (final l in conns)
                  ListTile(
                    key: ValueKey('shareTo_link_${l.id}'),
                    leading: const Icon(Icons.person_rounded),
                    title: Text(l.otherName(me)),
                    onTap: () => _send(context, 'link', l.id),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
