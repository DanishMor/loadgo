import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/l10n/l10n.dart';
import '../core/matching/load_ranker.dart';
import '../core/services/match_service.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';

/// Routes the driver wants matching loads for. Loads on these routes rank
/// higher in "Recommended for you".
class FavouriteRoutesScreen extends StatefulWidget {
  const FavouriteRoutesScreen({super.key});

  @override
  State<FavouriteRoutesScreen> createState() => _FavouriteRoutesScreenState();
}

class _FavouriteRoutesScreenState extends State<FavouriteRoutesScreen> {
  final _pickup = TextEditingController();
  final _drop = TextEditingController();

  @override
  void dispose() {
    _pickup.dispose();
    _drop.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    if (_pickup.text.trim().length < 2 || _drop.text.trim().length < 2) return;
    try {
      final ok = await MatchService.addFavourite(_pickup.text, _drop.text);
      if (!mounted) return;
      showSnack(context, tr(context, ok ? 'routeSaved' : 'routesFull'));
      if (ok) {
        _pickup.clear();
        _drop.clear();
      }
    } catch (_) {
      if (mounted) showSnack(context, tr(context, 'somethingWrong'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'favouriteRoutes'))),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Expanded(
              child: TextField(
                key: const ValueKey('favPickup'),
                controller: _pickup,
                decoration: InputDecoration(labelText: tr(context, 'pickupLocation')), inputFormatters: [LengthLimitingTextInputFormatter(100)]),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                key: const ValueKey('favDrop'),
                controller: _drop,
                decoration: InputDecoration(labelText: tr(context, 'dropLocation')), inputFormatters: [LengthLimitingTextInputFormatter(100)]),
            ),
            IconButton.filled(key: const ValueKey('favAdd'), tooltip: tr(context, 'a11yAdd'), onPressed: _add, icon: const Icon(Icons.add_rounded)),
          ]),
        ),
        Expanded(
          child: LiveStream<List<FavouriteRoute>>(
            stream: MatchService.watchFavourites,
            builder: (context, routes) {
              if (routes.isEmpty) {
                return EmptyState(icon: Icons.star_outline_rounded, title: tr(context, 'noFavouriteRoutes'));
              }
              return ListView(children: [
                for (final r in routes)
                  ListTile(
                    key: ValueKey('fav_${r.id}'),
                    leading: const Icon(Icons.star_rounded, color: AppColors.warning),
                    title: Text('${r.pickup} → ${r.drop}'),
                    trailing: IconButton(tooltip: tr(context, 'a11yDelete'), 
                      key: ValueKey('favDelete_${r.id}'),
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () => MatchService.removeFavourite(r.id),
                    ),
                  ),
              ]);
            },
          ),
        ),
      ]),
    );
  }
}
