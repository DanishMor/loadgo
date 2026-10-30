import 'package:flutter/material.dart';

import '../adapters/connect_adapters.dart';
import '../l10n/l10n.dart';
import '../theme/design_tokens.dart';
import '../widgets/common.dart';
import '../widgets/ds/app_button.dart';
import '../widgets/ds/app_top_bar.dart';
import '../widgets/ds/illustrations.dart';
import '../widgets/ds/skeleton.dart';
import '../widgets/ds/status_badge.dart';
import '../vehicles/vehicle_painter.dart';
import 'photo_service.dart';
import 'photo_widgets.dart';
import 'vehicle_photos.dart';

typedef VehiclePhotoUpload = Future<VehiclePhotoRecord> Function(String vehicleId, VehiclePhotoSlot slot, PickedPhoto photo, {bool anyway});

/// E18: the driver adds the photos of one vehicle, slot by slot. Each slot opens a guide (the system camera cannot
/// carry an overlay, docs/DECISIONS.md), then the camera or the gallery; the photo is checked on the phone before
/// it is sent, and the plate is read back (OcrReader) as a hint.
class VehiclePhotosScreen extends StatefulWidget {
  final String vehicleId;
  final String vehicleNumber;

  /// The stored vehicleType, for the drawing in the guide ('14ft').
  final String vehicleType;
  final PhotoPickerSource picker;
  final OcrReader ocr;
  final Stream<List<VehiclePhotoRecord>> Function()? records;
  final Future<PhotoBadge?> Function()? badge;
  final VehiclePhotoUpload? upload;
  final DateTime Function() now;

  const VehiclePhotosScreen({
    super.key,
    required this.vehicleId,
    required this.vehicleNumber,
    this.vehicleType = '',
    this.picker = const DevicePhotoPicker(),
    this.ocr = const NoOcrReader(),
    this.records,
    this.badge,
    this.upload,
    this.now = DateTime.now,
  });

  @override
  State<VehiclePhotosScreen> createState() => _VehiclePhotosScreenState();
}

class _VehiclePhotosScreenState extends State<VehiclePhotosScreen> {
  late Stream<List<VehiclePhotoRecord>> _records = _open();
  late final Future<PhotoBadge?> _badge = (widget.badge ?? () => VehiclePhotoService.badge(widget.vehicleId))();
  final _busy = <VehiclePhotoSlot>{};

  Stream<List<VehiclePhotoRecord>> _open() => (widget.records ?? () => VehiclePhotoService.watch(widget.vehicleId))();

  static const _icons = {
    VehiclePhotoSlot.front: Icons.local_shipping_rounded,
    VehiclePhotoSlot.rear: Icons.flip_to_back_rounded,
    VehiclePhotoSlot.left: Icons.west_rounded,
    VehiclePhotoSlot.right: Icons.east_rounded,
    VehiclePhotoSlot.load: Icons.inventory_2_outlined,
    VehiclePhotoSlot.cab: Icons.airline_seat_recline_normal_rounded,
    VehiclePhotoSlot.plate: Icons.pin_outlined,
    VehiclePhotoSlot.rc: Icons.description_outlined,
  };

  String _guideKey(VehiclePhotoSlot s) => switch (s) {
        VehiclePhotoSlot.left || VehiclePhotoSlot.right => 'vpGuide_side',
        _ => 'vpGuide_${s.name}',
      };

  void _say(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _capture(VehiclePhotoSlot slot) async {
    final camera = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _GuideSheet(slot: slot, guide: tr(context, _guideKey(slot)), vehicleType: widget.vehicleType, icon: _icons[slot]!),
    );
    if (camera == null || !mounted) return;
    final photo = await widget.picker.pick(camera);
    if (photo == null || !mounted) return;
    await _send(slot, photo, anyway: false);
  }

  Future<void> _send(VehiclePhotoSlot slot, PickedPhoto photo, {required bool anyway}) async {
    setState(() => _busy.add(slot));
    try {
      await (widget.upload ?? VehiclePhotoService.upload)(widget.vehicleId, slot, photo, anyway: anyway);
      if (slot == VehiclePhotoSlot.plate) await _plateHint(photo);
    } on PhotoNotClear catch (e) {
      if (!mounted) return;
      setState(() => _busy.remove(slot));
      final choice = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(tr(context, 'vpNotClearTitle')),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final i in e.issues) Padding(padding: const EdgeInsets.only(bottom: DsSpace.s1), child: Text(tr(context, 'vpIssue_${i.name}'))),
          ]),
          actions: [
            TextButton(key: const ValueKey('vpSendAnyway'), onPressed: () => Navigator.pop(context, false), child: Text(tr(context, 'vpSendAnyway'))),
            FilledButton(key: const ValueKey('vpRetake'), onPressed: () => Navigator.pop(context, true), child: Text(tr(context, 'vpRetake'))),
          ],
        ),
      );
      if (!mounted || choice == null) return;
      if (choice) {
        await _capture(slot);
      } else {
        await _send(slot, photo, anyway: true);
      }
      return;
    } catch (_) {
      if (mounted) _say(tr(context, 'vpFailed'));
    }
    if (mounted) setState(() => _busy.remove(slot));
  }

  Future<void> _plateHint(PickedPhoto photo) async {
    try {
      final read = (await widget.ocr.read(photo.bytes, OcrKind.plate))['plate'];
      if (!mounted) return;
      switch (checkPlate(read, widget.vehicleNumber)) {
        case PlateCheck.match:
          _say(tr(context, 'vpPlateMatch'));
        case PlateCheck.mismatch:
          _say(trf(context, 'vpPlateMismatch', {'read': read!, 'number': widget.vehicleNumber}));
        case PlateCheck.unread:
          break;
      }
    } catch (_) {
      // The hint is optional; a reader that fails says nothing.
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Scaffold(
      appBar: AppTopBar(title: tr(context, 'vpTitle')),
      body: StreamBuilder<List<VehiclePhotoRecord>>(
        stream: _records,
        builder: (context, snap) {
          if (snap.hasError) {
            return EmptyState(
              icon: Icons.photo_camera_outlined,
              illustration: IllustrationKind.error,
              title: tr(context, 'vcuLoadError'),
              action: AppButton(key: const ValueKey('vpRetry'), label: tr(context, 'retry'), expand: false, onPressed: () => setState(() => _records = _open())),
            );
          }
          if (!snap.hasData) return const SkeletonList();
          final bySlot = {for (final r in snap.data!) r.slot: r};
          final approved = VehiclePhotoSlot.required.where((s) => bySlot[s]?.status == VehiclePhotoStatus.approved).length;
          return ListView(padding: const EdgeInsets.all(DsSpace.gutter), children: [
            FutureBuilder<PhotoBadge?>(
              future: _badge,
              builder: (context, b) {
                final badge = b.data;
                if (badge == null) return const SizedBox.shrink();
                final now = widget.now();
                return Padding(
                  padding: const EdgeInsets.only(bottom: DsSpace.s3),
                  child: Wrap(spacing: DsSpace.s2, runSpacing: DsSpace.s2, children: [
                    if (badge.activeAt(now)) StatusBadge(label: trf(context, 'vpBadgeUntil', {'date': formatDate(badge.until)}), tone: StatusTone.success, icon: Icons.verified_rounded),
                    if (badge.remindAt(now)) StatusBadge(key: const ValueKey('vpRenew'), label: tr(context, 'vpBadgeRenew'), tone: StatusTone.attention, icon: Icons.schedule_rounded),
                  ]),
                );
              },
            ),
            Text(tr(context, 'vpIntro'), style: DsType.body.copyWith(color: c.textStrong)),
            const SizedBox(height: DsSpace.s2),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.lock_outline_rounded, size: 18, color: c.textMuted),
              const SizedBox(width: DsSpace.s2),
              Expanded(child: Text(tr(context, 'vpPrivacy'), style: DsType.bodySmall.copyWith(color: c.textMuted))),
            ]),
            const SizedBox(height: DsSpace.s3),
            Semantics(
              liveRegion: true,
              child: Text(trf(context, 'vpProgress', {'n': approved, 'm': VehiclePhotoSlot.required.length}), key: const ValueKey('vpProgress'), style: DsType.label.copyWith(color: c.textStrong)),
            ),
            const SizedBox(height: DsSpace.s3),
            for (final slot in VehiclePhotoSlot.values)
              Padding(
                padding: const EdgeInsets.only(bottom: DsSpace.s3),
                child: _SlotTile(slot: slot, icon: _icons[slot]!, record: bySlot[slot], busy: _busy.contains(slot), onAdd: () => _capture(slot)),
              ),
          ]);
        },
      ),
    );
  }
}

class _SlotTile extends StatelessWidget {
  final VehiclePhotoSlot slot;
  final IconData icon;
  final VehiclePhotoRecord? record;
  final bool busy;
  final VoidCallback onAdd;
  const _SlotTile({required this.slot, required this.icon, required this.record, required this.busy, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final r = record;
    final name = tr(context, 'vpSlot_${slot.name}');
    final (label, tone) = switch (r?.status) {
      null => (tr(context, 'vpMissing'), StatusTone.neutral),
      VehiclePhotoStatus.pending => (tr(context, 'vpPending'), StatusTone.progress),
      VehiclePhotoStatus.approved => (tr(context, 'vpApproved'), StatusTone.success),
      VehiclePhotoStatus.rejected => (tr(context, 'vpRejected'), StatusTone.attention),
    };
    return AppCard(
      key: ValueKey('vpSlot_${slot.name}'),
      padding: const EdgeInsets.all(DsSpace.s3),
      child: Row(children: [
        if (r != null)
          PhotoImage(r.path, size: 64)
        else
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: c.chip, borderRadius: DsRadius.all(DsRadius.md)),
            child: Icon(icon, color: c.textMuted),
          ),
        const SizedBox(width: DsSpace.s3),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: DsType.subtitle.copyWith(color: c.textStrong)),
            const SizedBox(height: DsSpace.s1),
            StatusBadge(label: label, tone: tone),
            if (r?.status == VehiclePhotoStatus.rejected && r?.reason != null)
              Padding(padding: const EdgeInsets.only(top: DsSpace.s1), child: Text(tr(context, 'vpReason_${r!.reason}'), style: DsType.bodySmall.copyWith(color: c.text))),
          ]),
        ),
        if (busy)
          Semantics(label: tr(context, 'vpSending'), child: const SizedBox(width: 48, height: 48, child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2))))
        else
          IconButton(
            key: ValueKey('vpAdd_${slot.name}'),
            tooltip: trf(context, 'vpAddSlot', {'slot': name}),
            icon: Icon(r == null ? Icons.add_a_photo_outlined : Icons.restart_alt_rounded),
            onPressed: onAdd,
          ),
      ]),
    );
  }
}

/// How to take the photo: a drawn frame and one line of advice, then camera or gallery. Pops true for camera.
class _GuideSheet extends StatelessWidget {
  final VehiclePhotoSlot slot;
  final String guide;
  final String vehicleType;
  final IconData icon;
  const _GuideSheet({required this.slot, required this.guide, required this.vehicleType, required this.icon});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final showTruck = slot.exterior && slot != VehiclePhotoSlot.cab && vehicleType.isNotEmpty;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(DsSpace.gutter, 0, DsSpace.gutter, DsSpace.gutter),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text(tr(context, 'vpSlot_${slot.name}'), style: DsType.title.copyWith(color: c.textStrong)),
          const SizedBox(height: DsSpace.s3),
          ExcludeSemantics(
            child: CustomPaint(
              foregroundPainter: _FramePainter(c.accentStrong),
              child: Container(
                height: 140,
                alignment: Alignment.center,
                padding: const EdgeInsets.all(DsSpace.s4),
                child: showTruck ? VehicleTypeArt(vehicleType, width: 220) : Icon(icon, size: 56, color: c.textMuted),
              ),
            ),
          ),
          const SizedBox(height: DsSpace.s3),
          Text(guide, key: const ValueKey('vpGuide'), style: DsType.body.copyWith(color: c.text)),
          const SizedBox(height: DsSpace.s4),
          AppButton(key: const ValueKey('vpCamera'), label: tr(context, 'vpCamera'), icon: Icons.photo_camera_rounded, onPressed: () => Navigator.pop(context, true)),
          const SizedBox(height: DsSpace.s2),
          AppButton(key: const ValueKey('vpGallery'), label: tr(context, 'vpGallery'), icon: Icons.photo_library_outlined, kind: AppButtonKind.secondary, onPressed: () => Navigator.pop(context, false)),
        ]),
      ),
    );
  }
}

/// Camera-style corner marks around the guide picture.
class _FramePainter extends CustomPainter {
  final Color color;
  const _FramePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color..strokeWidth = 3..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    const l = 22.0, m = 4.0;
    for (final (x, y, dx, dy) in [(m, m, 1.0, 1.0), (size.width - m, m, -1.0, 1.0), (m, size.height - m, 1.0, -1.0), (size.width - m, size.height - m, -1.0, -1.0)]) {
      canvas.drawLine(Offset(x, y), Offset(x + l * dx, y), p);
      canvas.drawLine(Offset(x, y), Offset(x, y + l * dy), p);
    }
  }

  @override
  bool shouldRepaint(_FramePainter old) => old.color != color;
}
