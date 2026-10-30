import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/design_tokens.dart';
import '../widgets/ds/status_badge.dart';
import 'photo_widgets.dart';
import 'vehicle_photos.dart';

/// E18d: badge reads kept for ten minutes, at most 100 vehicles, so a bid room that rebuilds costs one read per
/// vehicle shown, not one per frame.
class PhotoBadgeCache {
  PhotoBadgeCache._();

  static const ttl = Duration(minutes: 10);
  static const maxEntries = 100;
  static final _entries = <String, (DateTime, Future<PhotoBadge?>)>{};

  static Future<PhotoBadge?> get(String vehicleId, {Future<PhotoBadge?> Function(String)? load, DateTime? now}) {
    final at = now ?? DateTime.now();
    final hit = _entries[vehicleId];
    if (hit != null && at.difference(hit.$1) < ttl) return hit.$2;
    if (_entries.length >= maxEntries) _entries.remove(_entries.keys.first);
    final f = (load ?? VehiclePhotoService.badge)(vehicleId);
    _entries.remove(vehicleId);
    _entries[vehicleId] = (at, f);
    return f;
  }

  static int get length => _entries.length;
  static void clear() => _entries.clear();
}

/// "Photo-verified" on a bid card while the vehicle's badge is valid; a tap shows its approved outside photos.
/// Nothing at all for a vehicle without a valid badge (or an empty id from an old offer).
class VehiclePhotoBadge extends StatefulWidget {
  final String vehicleId;
  final Future<PhotoBadge?> Function(String)? load;
  final Future<List<VehiclePhotoRecord>> Function(String)? photos;
  final DateTime Function() now;
  const VehiclePhotoBadge(this.vehicleId, {super.key, this.load, this.photos, this.now = DateTime.now});

  @override
  State<VehiclePhotoBadge> createState() => _VehiclePhotoBadgeState();
}

class _VehiclePhotoBadgeState extends State<VehiclePhotoBadge> {
  late final Future<PhotoBadge?> _badge = widget.vehicleId.isEmpty ? Future.value(null) : PhotoBadgeCache.get(widget.vehicleId, load: widget.load, now: widget.now());

  void _show() => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => _PhotosSheet(future: (widget.photos ?? VehiclePhotoService.approvedExterior)(widget.vehicleId)),
      );

  @override
  Widget build(BuildContext context) => FutureBuilder<PhotoBadge?>(
        future: _badge,
        builder: (context, snap) {
          final b = snap.data;
          if (b == null || !b.activeAt(widget.now())) return const SizedBox.shrink();
          return Semantics(
            button: true,
            label: tr(context, 'vpBadge'),
            excludeSemantics: true,
            child: InkWell(
              key: ValueKey('vpBadge_${widget.vehicleId}'),
              borderRadius: DsRadius.all(DsRadius.pill),
              onTap: _show,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Align(widthFactor: 1, child: StatusBadge(label: tr(context, 'vpBadge'), tone: StatusTone.success, icon: Icons.verified_rounded)),
              ),
            ),
          );
        },
      );
}

class _PhotosSheet extends StatelessWidget {
  final Future<List<VehiclePhotoRecord>> future;
  const _PhotosSheet({required this.future});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(DsSpace.gutter, 0, DsSpace.gutter, DsSpace.gutter),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text(tr(context, 'vpBadge'), style: DsType.title.copyWith(color: c.textStrong)),
          const SizedBox(height: DsSpace.s3),
          FutureBuilder<List<VehiclePhotoRecord>>(
            future: future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) return const Center(child: Padding(padding: EdgeInsets.all(DsSpace.s4), child: CircularProgressIndicator()));
              final list = snap.data ?? const [];
              if (list.isEmpty) return Text(tr(context, 'vcuLoadError'), style: DsType.body.copyWith(color: c.textMuted));
              return Wrap(spacing: DsSpace.s3, runSpacing: DsSpace.s3, children: [
                for (final r in list)
                  Semantics(
                    label: tr(context, 'vpSlot_${r.slot.name}'),
                    image: true,
                    child: Column(key: ValueKey('vpSheet_${r.slot.name}'), mainAxisSize: MainAxisSize.min, children: [
                      PhotoImage(r.path, size: 132),
                      const SizedBox(height: DsSpace.s1),
                      ExcludeSemantics(child: Text(tr(context, 'vpSlot_${r.slot.name}'), style: DsType.bodySmall.copyWith(color: c.text))),
                    ]),
                  ),
              ]);
            },
          ),
        ]),
      ),
    );
  }
}

/// For the driver's vehicle list: "Take fresh photos" in the badge's last two weeks or after it ran out.
class VehiclePhotoRenewChip extends StatelessWidget {
  final String vehicleId;
  final Future<PhotoBadge?> Function(String)? load;
  final DateTime Function() now;
  const VehiclePhotoRenewChip(this.vehicleId, {super.key, this.load, this.now = DateTime.now});

  @override
  Widget build(BuildContext context) => FutureBuilder<PhotoBadge?>(
        future: PhotoBadgeCache.get(vehicleId, load: load, now: now()),
        builder: (context, snap) {
          final b = snap.data;
          if (b == null) return const SizedBox.shrink();
          final t = now();
          return b.remindAt(t)
              ? StatusBadge(key: ValueKey('vpRenew_$vehicleId'), label: tr(context, 'vpBadgeRenew'), tone: StatusTone.attention, icon: Icons.schedule_rounded)
              : StatusBadge(label: tr(context, 'vpBadge'), tone: StatusTone.success, icon: Icons.verified_rounded);
        },
      );
}
