import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/models/repeat.dart';
import '../core/services/repeat_service.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';
import 'post_load_screen.dart';

/// Favourite and blocked drivers of this customer.
class MyDriversScreen extends StatefulWidget {
  const MyDriversScreen({super.key});

  @override
  State<MyDriversScreen> createState() => _MyDriversScreenState();
}

class _MyDriversScreenState extends State<MyDriversScreen> {
  late final Stream<List<FavouriteDriver>> _favs = RepeatService.watchFavourites().asBroadcastStream();
  late final Stream<List<BlockedDriver>> _blocked = RepeatService.watchBlocked().asBroadcastStream();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr(context, 'favouriteDrivers')),
          bottom: TabBar(tabs: [
            Tab(text: tr(context, 'favouriteDrivers')),
            Tab(text: tr(context, 'blockedDrivers')),
          ]),
        ),
        body: TabBarView(children: [
          LiveStream<List<FavouriteDriver>>(
            stream: () => _favs,
            builder: (context, list) {
              if (list.isEmpty) return EmptyState(icon: Icons.favorite_border_rounded, title: tr(context, 'favouritesNone'));
              return ListView(padding: const EdgeInsets.all(20), children: [
                for (final f in list)
                  Card(
                    child: ListTile(
                      key: ValueKey('fav_${f.driverId}'),
                      title: Text(f.name.isEmpty ? f.driverId : f.name),
                      subtitle: Text(f.vehicleNumber),
                      onTap: () => Navigator.of(context)
                          .push(MaterialPageRoute<bool>(builder: (_) => PostLoadScreen(invitedDriverId: f.driverId))),
                      trailing: IconButton(
                        key: ValueKey('unfav_${f.driverId}'),
                        tooltip: tr(context, 'removeFromList'),
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => RepeatService.removeFavourite(f.driverId),
                      ),
                    ),
                  ),
              ]);
            },
          ),
          LiveStream<List<BlockedDriver>>(
            stream: () => _blocked,
            builder: (context, list) {
              if (list.isEmpty) return EmptyState(icon: Icons.block_rounded, title: tr(context, 'blockedNone'), subtitle: tr(context, 'blockNote'));
              return ListView(padding: const EdgeInsets.all(20), children: [
                Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(tr(context, 'blockNote'))),
                for (final b in list)
                  Card(
                    child: ListTile(
                      key: ValueKey('blocked_${b.driverId}'),
                      title: Text(b.name.isEmpty ? b.driverId : b.name),
                      trailing: TextButton(
                        key: ValueKey('unblock_${b.driverId}'),
                        onPressed: () => RepeatService.unblockDriver(b.driverId),
                        child: Text(tr(context, 'unblockDriver')),
                      ),
                    ),
                  ),
              ]);
            },
          ),
        ]),
      ),
    );
  }
}
