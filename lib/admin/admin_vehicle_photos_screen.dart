import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/photos/photo_widgets.dart';
import '../core/photos/vehicle_photos.dart';
import '../core/theme/design_tokens.dart';
import '../core/widgets/common.dart';
import '../core/widgets/ds/app_button.dart';
import '../core/widgets/ds/app_top_bar.dart';
import '../core/widgets/ds/illustrations.dart';
import '../core/widgets/ds/skeleton.dart';
import '../core/widgets/ds/status_badge.dart';

typedef VehiclePhotoReview = Future<void> Function(String vehicleId, VehiclePhotoSlot slot, {required bool approve, String? reason});

/// E18c: vehicles with photos waiting for a verifier (at most 50 records, oldest first). The rules let only super
/// and verifier admins list them.
class AdminVehiclePhotosScreen extends StatefulWidget {
  final Stream<Map<String, List<VehiclePhotoRecord>>> Function()? queue;

  /// Opens one vehicle; tests replace it.
  final Widget Function(String vehicleId)? review;

  const AdminVehiclePhotosScreen({super.key, this.queue, this.review});

  @override
  State<AdminVehiclePhotosScreen> createState() => _AdminVehiclePhotosScreenState();
}

class _AdminVehiclePhotosScreenState extends State<AdminVehiclePhotosScreen> {
  late Stream<Map<String, List<VehiclePhotoRecord>>> _queue = _open();

  Stream<Map<String, List<VehiclePhotoRecord>>> _open() => (widget.queue ?? VehiclePhotoService.pendingQueue)();

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Scaffold(
      appBar: AppTopBar(title: tr(context, 'vpaTitle')),
      body: StreamBuilder<Map<String, List<VehiclePhotoRecord>>>(
        stream: _queue,
        builder: (context, snap) {
          if (snap.hasError) {
            return EmptyState(
              icon: Icons.photo_camera_outlined,
              illustration: IllustrationKind.error,
              title: tr(context, 'vcuLoadError'),
              action: AppButton(key: const ValueKey('vpaRetry'), label: tr(context, 'retry'), expand: false, onPressed: () => setState(() => _queue = _open())),
            );
          }
          if (!snap.hasData) return const SkeletonList();
          final groups = snap.data!;
          if (groups.isEmpty) return EmptyState(icon: Icons.photo_library_outlined, illustration: IllustrationKind.emptyBox, title: tr(context, 'vpaEmpty'));
          final ids = groups.keys.toList();
          return ListView.separated(
            padding: const EdgeInsets.all(DsSpace.gutter),
            itemCount: ids.length,
            separatorBuilder: (_, _) => const SizedBox(height: DsSpace.s3),
            itemBuilder: (context, i) {
              final id = ids[i], records = groups[id]!;
              return AppCard(
                key: ValueKey('vpaVehicle_$id'),
                padding: const EdgeInsets.all(DsSpace.s3),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => (widget.review ?? (id) => AdminVehiclePhotoReview(vehicleId: id))(id))),
                child: Row(children: [
                  PhotoImage(records.first.path, size: 56),
                  const SizedBox(width: DsSpace.s3),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(id, maxLines: 1, overflow: TextOverflow.ellipsis, style: DsType.subtitle.copyWith(color: c.textStrong)),
                      const SizedBox(height: DsSpace.s1),
                      Text(trf(context, 'vpaWaiting', {'n': records.length}), style: DsType.bodySmall.copyWith(color: c.textMuted)),
                    ]),
                  ),
                  Icon(Icons.chevron_right_rounded, color: c.textMuted),
                ]),
              );
            },
          );
        },
      ),
    );
  }
}

/// One vehicle: every photo large, approve or reject with a reason, then the badge once all required photos pass.
class AdminVehiclePhotoReview extends StatefulWidget {
  final String vehicleId;
  final Stream<List<VehiclePhotoRecord>> Function()? records;
  final Future<PhotoBadge?> Function()? badge;
  final Future<String?> Function()? number;
  final VehiclePhotoReview? review;
  final Future<void> Function(String vehicleId, DateTime now)? grant;
  final DateTime Function() now;

  const AdminVehiclePhotoReview({super.key, required this.vehicleId, this.records, this.badge, this.number, this.review, this.grant, this.now = DateTime.now});

  @override
  State<AdminVehiclePhotoReview> createState() => _AdminVehiclePhotoReviewState();
}

class _AdminVehiclePhotoReviewState extends State<AdminVehiclePhotoReview> {
  late Stream<List<VehiclePhotoRecord>> _records = _open();
  late Future<PhotoBadge?> _badge = _loadBadge();
  late final Future<String?> _number = (widget.number ?? () => VehiclePhotoService.vehicleNumber(widget.vehicleId))();
  final _busy = <VehiclePhotoSlot>{};
  bool _granting = false;

  Stream<List<VehiclePhotoRecord>> _open() => (widget.records ?? () => VehiclePhotoService.watch(widget.vehicleId))();
  Future<PhotoBadge?> _loadBadge() => (widget.badge ?? () => VehiclePhotoService.badge(widget.vehicleId))();

  void _say(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _review(VehiclePhotoSlot slot, bool approve) async {
    String? reason;
    if (!approve) {
      reason = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (context) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: DsSpace.s3),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: DsSpace.gutter),
                child: Text(tr(context, 'vpaRejectWhy'), style: DsType.title.copyWith(color: context.ds.textStrong)),
              ),
              for (final r in vehiclePhotoReasons)
                ListTile(key: ValueKey('vpaReason_$r'), title: Text(tr(context, 'vpReason_$r')), onTap: () => Navigator.pop(context, r)),
            ]),
          ),
        ),
      );
      if (reason == null || !mounted) return;
    }
    setState(() => _busy.add(slot));
    try {
      await (widget.review ?? VehiclePhotoService.review)(widget.vehicleId, slot, approve: approve, reason: reason);
      if (mounted) _say(tr(context, 'statusUpdated'));
    } catch (_) {
      if (mounted) _say(tr(context, 'vpFailed'));
    }
    if (mounted) setState(() => _busy.remove(slot));
  }

  Future<void> _grant() async {
    final now = widget.now();
    setState(() => _granting = true);
    try {
      await (widget.grant ?? VehiclePhotoService.grantBadge)(widget.vehicleId, now);
      if (mounted) _say(trf(context, 'vpaGranted', {'date': formatDate(now.add(PhotoBadge.validFor))}));
      _badge = _loadBadge();
    } catch (_) {
      if (mounted) _say(tr(context, 'vpFailed'));
    }
    if (mounted) setState(() => _granting = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Scaffold(
      appBar: AppTopBar(title: tr(context, 'vpaTitle')),
      body: StreamBuilder<List<VehiclePhotoRecord>>(
        stream: _records,
        builder: (context, snap) {
          if (snap.hasError) {
            return EmptyState(
              icon: Icons.photo_camera_outlined,
              illustration: IllustrationKind.error,
              title: tr(context, 'vcuLoadError'),
              action: AppButton(key: const ValueKey('vpaRetry'), label: tr(context, 'retry'), expand: false, onPressed: () => setState(() => _records = _open())),
            );
          }
          if (!snap.hasData) return const SkeletonList();
          final records = snap.data!;
          final ready = readyForBadge(records);
          return ListView(padding: const EdgeInsets.all(DsSpace.gutter), children: [
            Text(widget.vehicleId, style: DsType.title.copyWith(color: c.textStrong)),
            FutureBuilder<String?>(
              future: _number,
              builder: (context, n) => n.data == null
                  ? const SizedBox.shrink()
                  : Text(trf(context, 'vpaNumber', {'number': n.data!}), key: const ValueKey('vpaNumber'), style: DsType.body.copyWith(color: c.text)),
            ),
            FutureBuilder<PhotoBadge?>(
              future: _badge,
              builder: (context, b) => b.data == null || !b.data!.activeAt(widget.now())
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: DsSpace.s2),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: StatusBadge(label: trf(context, 'vpBadgeUntil', {'date': formatDate(b.data!.until)}), tone: StatusTone.success, icon: Icons.verified_rounded),
                      ),
                    ),
            ),
            const SizedBox(height: DsSpace.s3),
            if (records.isEmpty) Text(tr(context, 'vpaEmpty'), style: DsType.body.copyWith(color: c.textMuted)),
            for (final r in records)
              Padding(
                padding: const EdgeInsets.only(bottom: DsSpace.s3),
                child: _ReviewCard(record: r, busy: _busy.contains(r.slot), onReview: (approve) => _review(r.slot, approve)),
              ),
            const SizedBox(height: DsSpace.s2),
            AppButton(
              key: const ValueKey('vpaGrant'),
              label: tr(context, 'vpaGrant'),
              icon: Icons.verified_rounded,
              loading: _granting,
              onPressed: ready && !_granting ? _grant : null,
            ),
            if (!ready)
              Padding(
                padding: const EdgeInsets.only(top: DsSpace.s2),
                child: Text(tr(context, 'vpaGrantNeed'), key: const ValueKey('vpaGrantNeed'), style: DsType.bodySmall.copyWith(color: c.textMuted)),
              ),
          ]);
        },
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final VehiclePhotoRecord record;
  final bool busy;
  final ValueChanged<bool> onReview;
  const _ReviewCard({required this.record, required this.busy, required this.onReview});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final r = record;
    final (label, tone) = switch (r.status) {
      VehiclePhotoStatus.pending => (tr(context, 'vpPending'), StatusTone.progress),
      VehiclePhotoStatus.approved => (tr(context, 'vpApproved'), StatusTone.success),
      VehiclePhotoStatus.rejected => (tr(context, 'vpRejected'), StatusTone.attention),
    };
    return AppCard(
      key: ValueKey('vpaSlot_${r.slot.name}'),
      padding: const EdgeInsets.all(DsSpace.s3),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(tr(context, 'vpSlot_${r.slot.name}'), style: DsType.subtitle.copyWith(color: c.textStrong))),
          StatusBadge(label: label, tone: tone),
        ]),
        const SizedBox(height: DsSpace.s2),
        Center(child: PhotoImage(r.path, size: 200)),
        if (r.status == VehiclePhotoStatus.rejected && r.reason != null)
          Padding(padding: const EdgeInsets.only(top: DsSpace.s2), child: Text(tr(context, 'vpReason_${r.reason}'), style: DsType.bodySmall.copyWith(color: c.text))),
        const SizedBox(height: DsSpace.s3),
        if (busy)
          const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)))
        else
          Wrap(spacing: DsSpace.s2, runSpacing: DsSpace.s2, children: [
            AppButton(key: ValueKey('vpaApprove_${r.slot.name}'), label: tr(context, 'vpaApprove'), icon: Icons.check_rounded, expand: false, onPressed: r.status == VehiclePhotoStatus.approved ? null : () => onReview(true)),
            AppButton(key: ValueKey('vpaReject_${r.slot.name}'), label: tr(context, 'vpaReject'), icon: Icons.close_rounded, kind: AppButtonKind.secondary, expand: false, onPressed: r.status == VehiclePhotoStatus.rejected ? null : () => onReview(false)),
          ]),
      ]),
    );
  }
}
