import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../features/features.dart';
import '../l10n/l10n.dart';
import '../services/connectivity_service.dart';
import '../theme/design_tokens.dart';
import '../widgets/common.dart';
import '../widgets/ds/app_button.dart';
import '../widgets/feature_gate.dart';
import 'photo_service.dart';

/// Takes a photo from the camera or the gallery (already made smaller).
abstract class PhotoPickerSource {
  Future<PickedPhoto?> pick(bool camera);
}

class DevicePhotoPicker implements PhotoPickerSource {
  const DevicePhotoPicker();

  @override
  Future<PickedPhoto?> pick(bool camera) async {
    // The picker scales the picture to 1600 px and compresses it: a phone photo of 8 MB becomes a few hundred KB.
    final file = await ImagePicker().pickImage(source: camera ? ImageSource.camera : ImageSource.gallery, maxWidth: 1600, imageQuality: 75);
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    return PickedPhoto(bytes, _mime(file.mimeType, file.name), localPath: file.path.isEmpty ? null : file.path);
  }

  static String _mime(String? given, String name) {
    if (given != null && given.startsWith('image/')) return given;
    final n = name.toLowerCase();
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.webp')) return 'image/webp';
    if (n.endsWith('.heic')) return 'image/heic';
    return 'image/jpeg';
  }
}

/// A photo read from Storage with the person's sign-in (never from a link).
/// The last few are kept in memory so a list does not read them again and again.
class PhotoImage extends StatefulWidget {
  final String path;
  final double size;
  final StorageGateway? gateway;
  const PhotoImage(this.path, {super.key, this.size = 72, this.gateway});

  static final Map<String, Uint8List> _cache = {};

  @visibleForTesting
  static void clearCache() => _cache.clear();

  @override
  State<PhotoImage> createState() => _PhotoImageState();
}

class _PhotoImageState extends State<PhotoImage> {
  late Future<Uint8List?> _data = _load();

  Future<Uint8List?> _load() async {
    final hit = PhotoImage._cache[widget.path];
    if (hit != null) return hit;
    final bytes = await (widget.gateway ?? PhotoService.gateway).get(widget.path);
    if (bytes != null) {
      if (PhotoImage._cache.length >= 20) PhotoImage._cache.remove(PhotoImage._cache.keys.first);
      PhotoImage._cache[widget.path] = bytes;
    }
    return bytes;
  }

  @override
  void didUpdateWidget(PhotoImage old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) _data = _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return FutureBuilder<Uint8List?>(
      future: _data,
      builder: (context, snap) {
        Widget child;
        if (snap.connectionState != ConnectionState.done) {
          child = const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)));
        } else if (snap.hasError || snap.data == null) {
          child = Icon(Icons.broken_image_outlined, color: c.textMuted);
        } else {
          final bytes = snap.data!;
          child = InkWell(
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) => Dialog(child: InteractiveViewer(child: Image.memory(bytes, fit: BoxFit.contain))),
            ),
            child: Image.memory(bytes, fit: BoxFit.cover, cacheWidth: 400, errorBuilder: (_, _, _) => Icon(Icons.broken_image_outlined, color: c.textMuted)),
          );
        }
        return ClipRRect(
          borderRadius: DsRadius.all(DsRadius.md),
          child: Container(width: widget.size, height: widget.size, color: c.chip, child: child),
        );
      },
    );
  }
}

/// "Add photo" with progress, retry and a place on the phone when offline (F29).
/// Shown only while the `photoUploads` switch is on.
class PhotoAttach extends StatefulWidget {
  final PhotoTarget target;

  /// Called with the stored photo (not when it was queued).
  final ValueChanged<UploadedPhoto>? onUploaded;
  final PhotoPickerSource picker;

  /// A different title than the kind's (for the views of a truck).
  final String? titleKey;

  const PhotoAttach({super.key, required this.target, this.onUploaded, this.picker = const DevicePhotoPicker(), this.titleKey});

  @override
  State<PhotoAttach> createState() => _PhotoAttachState();
}

enum _Phase { idle, sending, done, failed, queued }

class _PhotoAttachState extends State<PhotoAttach> {
  _Phase _phase = _Phase.idle;
  double _progress = 0;
  PickedPhoto? _last;
  UploadedPhoto? _stored;
  String? _problemKey;

  Future<void> _choose() async {
    final camera = await showModalBottomSheet<bool>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(key: const ValueKey('photoCamera'), leading: const Icon(Icons.photo_camera_outlined), title: Text(tr(c, 'photoCamera')), onTap: () => Navigator.pop(c, true)),
          ListTile(key: const ValueKey('photoGallery'), leading: const Icon(Icons.photo_library_outlined), title: Text(tr(c, 'photoGallery')), onTap: () => Navigator.pop(c, false)),
        ]),
      ),
    );
    if (camera == null || !mounted) return;
    try {
      final photo = await widget.picker.pick(camera);
      if (photo != null) await _send(photo);
    } catch (_) {
      if (mounted) setState(() => _phase = _Phase.failed);
    }
  }

  Future<void> _send(PickedPhoto photo) async {
    setState(() {
      _phase = _Phase.sending;
      _progress = 0;
      _last = photo;
      _problemKey = null;
    });
    try {
      final r = await PhotoService.upload(widget.target, photo, onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      });
      if (!mounted) return;
      setState(() {
        _phase = _Phase.done;
        _stored = r;
      });
      widget.onUploaded?.call(r);
    } on PhotoRejected catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.failed;
        _problemKey = e.reason == 'too_big' ? 'photoTooBig' : (e.reason == 'type' ? 'photoWrongType' : 'photoFailed');
        _last = null;
      });
    } catch (e) {
      // Offline: keep it on the phone and send it later. Otherwise show the message with Retry.
      final queued = !ConnectivityService.online.value && await PhotoQueue.add(widget.target, photo);
      if (!mounted) return;
      setState(() => _phase = queued ? _Phase.queued : _Phase.failed);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FeatureGate(
      featureKey: FeatureKey.photoUploads,
      child: AppCard(
        key: ValueKey('photoAttach_${widget.target.kind.name}${widget.target.view == null ? '' : '_${widget.target.view}'}'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr(context, widget.titleKey ?? 'photoKind_${widget.target.kind.name}'), style: DsType.title.copyWith(color: context.ds.text)),
          const SizedBox(height: DsSpace.s2),
          if (_phase == _Phase.sending) ...[
            LinearProgressIndicator(key: const ValueKey('photoProgress'), value: _progress > 0 ? _progress : null),
            const SizedBox(height: DsSpace.s1),
            Text(tr(context, 'photoUploading'), style: DsType.caption.copyWith(color: context.ds.textMuted)),
          ] else ...[
            if (_phase == _Phase.done && _stored != null)
              Row(children: [
                PhotoImage(_stored!.path),
                const SizedBox(width: DsSpace.s3),
                Expanded(child: Text(tr(context, 'photoDone'), key: const ValueKey('photoDone'), style: DsType.body.copyWith(color: context.ds.success))),
              ]),
            if (_phase == _Phase.queued) Text(tr(context, 'photoQueued'), key: const ValueKey('photoQueued'), style: DsType.caption.copyWith(color: context.ds.textMuted)),
            if (_phase == _Phase.failed) ...[
              Text(tr(context, _problemKey ?? 'photoFailed'), key: const ValueKey('photoFailed'), style: DsType.caption.copyWith(color: context.ds.error)),
              if (_last != null)
                AppButton(key: const ValueKey('photoRetry'), label: tr(context, 'retry'), kind: AppButtonKind.tertiary, expand: false, onPressed: () => _send(_last!)),
            ],
            const SizedBox(height: DsSpace.s2),
            AppButton(key: const ValueKey('photoAdd'), label: tr(context, 'photoAdd'), icon: Icons.add_a_photo_outlined, kind: AppButtonKind.secondary, expand: false, onPressed: _choose),
          ],
        ]),
      ),
    );
  }
}

/// Sends the photos that waited for the network (call when the phone comes back online).
Future<int> flushPhotoQueue() => PhotoQueue.flush(_readFile);

Future<Uint8List?> _readFile(String path) async {
  try {
    return await XFile(path).readAsBytes();
  } catch (_) {
    return null;
  }
}
