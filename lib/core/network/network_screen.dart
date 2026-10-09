import '../errors/error_text.dart';
import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/driver_network.dart';
import '../services/backend.dart';
import '../services/location_service.dart';
import '../services/network_service.dart';
import '../widgets/common.dart';
import '../widgets/live_stream.dart';
import 'network_chat_screen.dart';
import 'network_logic.dart';

/// Driver network: nearby drivers (D11) with a location privacy mode and an
/// expiring share (CH13, CH14), connections (D12) and groups (D13).
class NetworkScreen extends StatelessWidget {
  const NetworkScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr(context, 'netTitle')),
          bottom: TabBar(tabs: [
            Tab(key: const ValueKey('netTabNearby'), text: tr(context, 'netNearby')),
            Tab(key: const ValueKey('netTabConnections'), text: tr(context, 'netConnections')),
            Tab(key: const ValueKey('netTabGroups'), text: tr(context, 'netGroups')),
          ]),
        ),
        body: const TabBarView(children: [_NearbyTab(), _ConnectionsTab(), _GroupsTab()]),
      ),
    );
  }
}

String _modeLabel(BuildContext context, String mode) => tr(context, switch (mode) {
      LocationMode.nearby => 'modeNearby',
      LocationMode.connections => 'modeConnections',
      LocationMode.tripMembers => 'modeTrip',
      _ => 'modeHidden',
    });

class _NearbyTab extends StatefulWidget {
  const _NearbyTab();
  @override
  State<_NearbyTab> createState() => _NearbyTabState();
}

class _NearbyTabState extends State<_NearbyTab> {
  Coordinates? _here;
  bool _located = false;
  int _hours = 8;
  Stream<List<DriverPresence>>? _nearby;
  final _requested = <String>{};

  @override
  void initState() {
    super.initState();
    _locate();
  }

  Future<void> _locate() async {
    final p = await LocationService.current();
    if (!mounted) return;
    setState(() {
      _here = p;
      _located = true;
      if (p != null) _nearby = NetworkService.watchNearby(p.lat, p.lng);
    });
  }

  Future<void> _setMode(String mode) async {
    try {
      if (LocationMode.publishes(mode) && _here == null) {
        showSnack(context, tr(context, 'netNeedLocation'));
        return;
      }
      await NetworkService.setLocationMode(mode: mode, name: await NetworkService.myName(), lat: _here?.lat, lng: _here?.lng, hours: _hours);
    } catch (error) {
      if (mounted) showSnack(context, errorText(context, error));
    }
  }

  Future<void> _connect(DriverPresence d) async {
    try {
      await NetworkService.requestConnection(otherUid: d.uid, myName: await NetworkService.myName(), otherName: d.name);
      if (mounted) {
        setState(() => _requested.add(d.uid));
        showSnack(context, tr(context, 'netRequested'));
      }
    } catch (error) {
      if (mounted) showSnack(context, errorText(context, error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = Backend.uid ?? '';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AppCard(
          child: StreamBuilder<({String mode, DateTime? until})>(
            stream: NetworkService.watchMyMode(),
            builder: (context, snap) {
              final mode = snap.data?.mode ?? LocationMode.hidden;
              final until = snap.data?.until;
              final active = LocationMode.publishes(mode) && until != null && until.isAfter(DateTime.now());
              final current = active || !LocationMode.publishes(mode) ? mode : LocationMode.hidden;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr(context, 'netPrivacy'), style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final m in LocationMode.all)
                      ChoiceChip(
                        key: ValueKey('mode_$m'),
                        label: Text(_modeLabel(context, m)),
                        selected: current == m,
                        onSelected: (_) => _setMode(m),
                      ),
                  ]),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, children: [
                    for (final h in shareDurationsHours)
                      ChoiceChip(
                        key: ValueKey('hours_$h'),
                        label: Text(trf(context, 'netShareHours', {'n': h})),
                        selected: _hours == h,
                        onSelected: (_) => setState(() => _hours = h),
                      ),
                  ]),
                  if (active) ...[
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(child: Text(trf(context, 'netSharingUntil', {'when': formatDateTime(until)}), style: TextStyle(color: AppColors.muted, fontSize: 12))),
                      TextButton(key: const ValueKey('netStop'), onPressed: NetworkService.stopSharing, child: Text(tr(context, 'netStop'))),
                    ]),
                  ],
                  const SizedBox(height: 4),
                  Text(tr(context, 'netPrivacyNote'), style: TextStyle(color: AppColors.faint, fontSize: 11)),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        if (_located && _here == null)
          Padding(padding: const EdgeInsets.all(16), child: Text(tr(context, 'netNeedLocation'), style: TextStyle(color: AppColors.muted)))
        else if (_nearby != null)
          StreamBuilder<List<DriverLink>>(
            stream: NetworkService.watchLinks(),
            builder: (context, links) => StreamBuilder<List<DriverPresence>>(
              stream: _nearby,
              builder: (context, snap) {
                if (snap.hasError) return ErrorState(error: snap.error);
                final linked = {for (final l in links.data ?? const <DriverLink>[]) l.otherUid(me)};
                final list = nearbyDrivers(snap.data ?? const [], lat: _here!.lat, lng: _here!.lng, myUid: me, now: DateTime.now());
                if (list.isEmpty) return Padding(padding: const EdgeInsets.all(16), child: Text(tr(context, 'netNoNearby'), style: TextStyle(color: AppColors.muted)));
                return Column(children: [
                  for (final e in list)
                    ListTile(
                      key: ValueKey('nearby_${e.driver.uid}'),
                      contentPadding: EdgeInsets.zero,
                      leading: const CircleAvatar(child: Icon(Icons.local_shipping_outlined)),
                      title: Text(e.driver.name),
                      subtitle: Text(trf(context, 'netAway', {'km': e.km.round()})),
                      trailing: linked.contains(e.driver.uid) || _requested.contains(e.driver.uid)
                          ? Text(tr(context, 'netRequested'), style: TextStyle(color: AppColors.muted, fontSize: 12))
                          : OutlinedButton(key: ValueKey('connect_${e.driver.uid}'), onPressed: () => _connect(e.driver), child: Text(tr(context, 'netConnect'))),
                    ),
                ]);
              },
            ),
          )
        else
          const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
      ],
    );
  }
}

class _ConnectionsTab extends StatelessWidget {
  const _ConnectionsTab();

  @override
  Widget build(BuildContext context) {
    final me = Backend.uid ?? '';
    return LiveStream<List<DriverLink>>(
      stream: NetworkService.watchLinks,
      builder: (context, links) {
        if (links.isEmpty) return EmptyState(icon: Icons.group_outlined, title: tr(context, 'netNoConnections'));
        final incoming = [for (final l in links) if (l.incomingFor(me)) l];
        final rest = [for (final l in links) if (!l.incomingFor(me)) l];
        return ListView(padding: const EdgeInsets.all(16), children: [
          if (incoming.isNotEmpty) ...[
            Text(tr(context, 'netIncoming'), style: const TextStyle(fontWeight: FontWeight.w800)),
            for (final l in incoming)
              ListTile(
                key: ValueKey('request_${l.id}'),
                contentPadding: EdgeInsets.zero,
                title: Text(l.requesterName),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  TextButton(key: ValueKey('decline_${l.id}'), onPressed: () => NetworkService.remove(l.id), child: Text(tr(context, 'netDecline'))),
                  FilledButton(key: ValueKey('accept_${l.id}'), onPressed: () => NetworkService.accept(l.id), child: Text(tr(context, 'netAccept'))),
                ]),
              ),
            const Divider(),
          ],
          for (final l in rest)
            ListTile(
              key: ValueKey('link_${l.id}'),
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(child: Icon(Icons.person_rounded)),
              title: Text(l.otherName(me)),
              subtitle: l.connected ? null : Text(tr(context, 'netWaiting')),
              onTap: l.connected
                  ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NetworkChatScreen(kind: 'link', id: l.id, title: l.otherName(me))))
                  : null,
              trailing: PopupMenuButton<String>(
                key: ValueKey('linkMenu_${l.id}'),
                onSelected: (_) => NetworkService.remove(l.id),
                itemBuilder: (c) => [PopupMenuItem(value: 'end', child: Text(tr(c, 'netEnd')))],
              ),
            ),
        ]);
      },
    );
  }
}

class _GroupsTab extends StatelessWidget {
  const _GroupsTab();

  Future<void> _create(BuildContext context) async {
    final name = TextEditingController();
    var kind = groupKinds.first;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(tr(c, 'netNewGroup')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(key: const ValueKey('groupName'), controller: name, maxLength: 40, decoration: InputDecoration(labelText: tr(c, 'netGroupName'))),
            Wrap(spacing: 8, children: [
              for (final k in groupKinds)
                ChoiceChip(key: ValueKey('kind_$k'), label: Text(_kindLabel(c, k)), selected: kind == k, onSelected: (_) => set(() => kind = k)),
            ]),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.of(c).pop(false), child: Text(tr(c, 'cancel'))),
            FilledButton(key: const ValueKey('groupCreate'), onPressed: () => Navigator.of(c).pop(name.text.trim().isNotEmpty), child: Text(tr(c, 'save'))),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await NetworkService.createGroup(name: name.text, kind: kind);
      if (context.mounted) showSnack(context, tr(context, 'netGroupMade'));
    } catch (error) {
      if (context.mounted) showSnack(context, errorText(context, error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('newGroup'),
        onPressed: () => _create(context),
        icon: const Icon(Icons.add_rounded),
        label: Text(tr(context, 'netNewGroup')),
      ),
      body: LiveStream<List<DriverGroup>>(
        stream: NetworkService.watchGroups,
        builder: (context, groups) {
          if (groups.isEmpty) return EmptyState(icon: Icons.groups_outlined, title: tr(context, 'netNoGroups'));
          return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 88), children: [
            for (final g in groups)
              ListTile(
                key: ValueKey('group_${g.id}'),
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(child: Icon(Icons.groups_rounded)),
                title: Text(g.name),
                subtitle: Text('${_kindLabel(context, g.kind)} · ${trf(context, 'netMembers', {'n': g.memberIds.length})}'),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => GroupScreen(group: g))),
              ),
          ]);
        },
      ),
    );
  }
}

String _kindLabel(BuildContext context, String kind) => tr(context, switch (kind) {
      'route' => 'gkRoute',
      'convoy' => 'gkConvoy',
      'fleet' => 'gkFleet',
      _ => 'gkTrip',
    });

/// One group: chat plus members (owner adds connected drivers).
class GroupScreen extends StatelessWidget {
  final DriverGroup group;
  const GroupScreen({super.key, required this.group});

  @override
  Widget build(BuildContext context) {
    final me = Backend.uid ?? '';
    return StreamBuilder<List<DriverGroup>>(
      stream: NetworkService.watchGroups(),
      builder: (context, snap) {
        if (snap.hasError) return ErrorState(error: snap.error);
        final live = (snap.data ?? const <DriverGroup>[]).where((g) => g.id == group.id);
        final g = live.isEmpty ? group : live.first;
        final owner = g.ownerId == me;
        return Scaffold(
          appBar: AppBar(
            title: Text(g.name),
            actions: [
              if (owner)
                IconButton(key: const ValueKey('addMember'), tooltip: tr(context, 'netAddMember'), icon: const Icon(Icons.person_add_alt_1_rounded), onPressed: () => _add(context, g)),
              PopupMenuButton<String>(
                key: const ValueKey('groupMenu'),
                onSelected: (v) async {
                  final nav = Navigator.of(context);
                  if (v == 'delete') await NetworkService.deleteGroup(g.id);
                  if (v == 'leave') await NetworkService.removeMember(g, me);
                  nav.pop();
                },
                itemBuilder: (c) => [PopupMenuItem(value: owner ? 'delete' : 'leave', child: Text(tr(c, owner ? 'netDeleteGroup' : 'netLeave')))],
              ),
            ],
          ),
          body: NetworkChatBody(kind: 'group', id: g.id),
        );
      },
    );
  }

  Future<void> _add(BuildContext context, DriverGroup g) async {
    final links = await NetworkService.watchLinks().first;
    final me = Backend.uid ?? '';
    final free = [for (final l in links) if (l.connected && !g.memberIds.contains(l.otherUid(me))) l];
    if (!context.mounted) return;
    if (free.isEmpty) {
      showSnack(context, tr(context, 'netNoOneToAdd'));
      return;
    }
    final pick = await showModalBottomSheet<DriverLink>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          for (final l in free) ListTile(key: ValueKey('add_${l.otherUid(me)}'), title: Text(l.otherName(me)), onTap: () => Navigator.of(c).pop(l)),
        ]),
      ),
    );
    if (pick == null) return;
    try {
      await NetworkService.addMember(g, pick.otherUid(me));
    } catch (error) {
      if (context.mounted) showSnack(context, errorText(context, error));
    }
  }
}
