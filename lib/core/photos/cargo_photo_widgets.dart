import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/design_tokens.dart';
import '../widgets/common.dart';
import '../widgets/ds/app_button.dart';
import '../widgets/live_stream.dart' show ErrorState;
import 'cargo_photos.dart';
import 'photo_service.dart';
import 'photo_widgets.dart';
import 'vehicle_photos.dart' show PhotoNotClear;

typedef CargoPhotoUpload = Future<CargoPhotoRecord> Function(String loadId, CargoSlot slot, PickedPhoto photo, {bool anyway});

/// E19: the shipper's goods photos on the bid room (up to three). While the load is open ([editable]) photos can be
/// added from the camera or the gallery (checked on the phone first) and taken off; afterwards the card only shows them.
class CargoPhotosCard extends StatefulWidget {
  final String loadId;
  final bool editable;
  final PhotoPickerSource picker;
  final Stream<List<CargoPhotoRecord>> Function()? records;
  final CargoPhotoUpload? upload;
  final Future<void> Function(String loadId, CargoSlot slot)? remove;

  const CargoPhotosCard({super.key, required this.loadId, this.editable = false, this.picker = const DevicePhotoPicker(), this.records, this.upload, this.remove});

  @override
  State<CargoPhotosCard> createState() => _CargoPhotosCardState();
}

class _CargoPhotosCardState extends State<CargoPhotosCard> {
  late Stream<List<CargoPhotoRecord>> _records = _open();
  bool _busy = false;

  Stream<List<CargoPhotoRecord>> _open() => (widget.records ?? () => CargoPhotoService.watch(widget.loadId))();

  void _say(String key) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(context, key))));
  }

  Future<void> _add(CargoSlot slot, bool camera) async {
    final photo = await widget.picker.pick(camera);
    if (photo == null || !mounted) return;
    await _send(slot, photo, camera, anyway: false);
  }

  Future<void> _send(CargoSlot slot, PickedPhoto photo, bool camera, {required bool anyway}) async {
    setState(() => _busy = true);
    try {
      await (widget.upload ?? CargoPhotoService.upload)(widget.loadId, slot, photo, anyway: anyway);
    } on PhotoNotClear catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      final retake = await askRetakeOrSend(context, e.issues);
      if (!mounted || retake == null) return;
      if (retake) {
        await _add(slot, camera);
      } else {
        await _send(slot, photo, camera, anyway: true);
      }
      return;
    } on PhotoRejected catch (e) {
      _say(e.reason == 'too_big' ? 'photoTooBig' : e.reason == 'type' ? 'photoWrongType' : 'photoFailed');
    } catch (_) {
      _say('photoFailed');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _remove(CargoSlot slot) async {
    setState(() => _busy = true);
    try {
      await (widget.remove ?? CargoPhotoService.remove)(widget.loadId, slot);
    } catch (_) {
      _say('photoFailed');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return AppCard(
      child: StreamBuilder<List<CargoPhotoRecord>>(
        stream: _records,
        builder: (context, snap) {
          final list = snap.data ?? const <CargoPhotoRecord>[];
          final free = widget.editable ? CargoPhotoService.freeSlot(list) : null;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Semantics(header: true, child: Text(tr(context, 'cgTitle'), style: DsType.subtitle.copyWith(color: c.textStrong)))),
              if (snap.hasData) Text(trf(context, 'cgCount', {'n': list.length}), key: const ValueKey('cgCount'), style: DsType.caption.copyWith(color: c.textMuted)),
            ]),
            if (widget.editable) ...[
              const SizedBox(height: DsSpace.s1),
              Text(tr(context, 'cgHelp'), style: DsType.bodySmall.copyWith(color: c.textMuted)),
            ],
            const SizedBox(height: DsSpace.s3),
            if (snap.hasError)
              ErrorState(
                compact: true,
                error: snap.error,
                onRetry: () => setState(() => _records = _open()),
              )
            else if (!snap.hasData)
              const Center(child: Padding(padding: EdgeInsets.all(DsSpace.s3), child: CircularProgressIndicator()))
            else if (list.isEmpty && !widget.editable)
              Text(tr(context, 'cgEmpty'), key: const ValueKey('cgEmpty'), style: DsType.body.copyWith(color: c.textMuted))
            else
              Wrap(spacing: DsSpace.s3, runSpacing: DsSpace.s3, children: [
                for (final r in list)
                  Stack(key: ValueKey('cgPhoto_${r.slot.name}'), clipBehavior: Clip.none, children: [
                    Semantics(image: true, label: trf(context, 'cgPhoto', {'n': r.slot.index + 1}), child: PhotoImage(r.path, size: 96)),
                    if (widget.editable)
                      PositionedDirectional(
                        top: -DsSpace.s3,
                        end: -DsSpace.s3,
                        child: IconButton(
                          key: ValueKey('cgRemove_${r.slot.name}'),
                          tooltip: tr(context, 'cgRemove'),
                          onPressed: _busy ? null : () => _remove(r.slot),
                          icon: const Icon(Icons.cancel_rounded),
                        ),
                      ),
                  ]),
              ]),
            if (free != null && snap.hasData) ...[
              const SizedBox(height: DsSpace.s3),
              Wrap(spacing: DsSpace.s2, runSpacing: DsSpace.s2, children: [
                AppButton(key: const ValueKey('cgCamera'), label: tr(context, 'photoCamera'), kind: AppButtonKind.secondary, icon: Icons.photo_camera_outlined, loading: _busy, onPressed: _busy ? null : () => _add(free, true)),
                AppButton(key: const ValueKey('cgGallery'), label: tr(context, 'photoGallery'), kind: AppButtonKind.tertiary, icon: Icons.photo_library_outlined, onPressed: _busy ? null : () => _add(free, false)),
              ]),
            ],
          ]);
        },
      ),
    );
  }
}

/// E19: for a driver on a load card: an icon that opens the goods photos. Nothing is read until it is tapped
/// (one read of at most three records, then one download per picture).
class CargoPhotosButton extends StatelessWidget {
  final String loadId;
  final Future<List<CargoPhotoRecord>> Function(String loadId)? list;
  const CargoPhotosButton({super.key, required this.loadId, this.list});

  void _open(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (context) => PhotoGridSheet(
          titleKey: 'cgTitle',
          emptyKey: 'cgEmpty',
          future: (list ?? CargoPhotoService.list)(loadId),
          tile: (context, r) => (key: ValueKey('cgSheet_${r.slot.name}'), path: r.path, label: trf(context, 'cgPhoto', {'n': r.slot.index + 1})),
        ),
      );

  @override
  Widget build(BuildContext context) => IconButton(
        key: ValueKey('cgView_$loadId'),
        tooltip: tr(context, 'cgView'),
        icon: const Icon(Icons.photo_library_outlined),
        onPressed: () => _open(context),
      );
}
