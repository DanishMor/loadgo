import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/load.dart';
import '../services/load_service.dart';
import 'common.dart';
import 'live_stream.dart';
import 'load_card.dart';

/// One load opened by its id (a shared link or a search hit). [action] builds
/// the button under the card (drivers: Accept); it is only offered while the
/// load is open.
class LoadByIdScreen extends StatelessWidget {
  final String loadId;
  final Widget Function(Load load)? action;

  /// Test hook; defaults to the live load.
  final Stream<Load?> Function()? stream;

  const LoadByIdScreen({super.key, required this.loadId, this.action, this.stream});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'gsSharedLoad'))),
      body: LiveDoc<Load>(
        stream: stream ?? () => LoadService.watchById(loadId),
        builder: (context, load) {
          if (load == null) {
            return EmptyState(key: const ValueKey('loadGone'), icon: Icons.inventory_2_outlined, title: tr(context, 'gsLoadUnavailable'));
          }
          return ListView(padding: const EdgeInsets.all(20), children: [
            LoadCard(key: ValueKey('sharedLoad_${load.id}'), load: load, showStatus: true, action: load.isOpen ? action?.call(load) : null),
          ]);
        },
      ),
    );
  }
}
