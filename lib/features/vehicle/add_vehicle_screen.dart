import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants/logistics.dart';
import '../../core/models/vehicle.dart';
import '../../core/services/user_service.dart';
import '../../core/services/vehicle_service.dart';
import '../../core/widgets/common.dart';
import '../../main.dart';

/// Lets the driver pick an RC photo from camera or gallery (compressed).
Future<Uint8List?> pickRcImageFromDevice(BuildContext context) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: Text(tr(sheetContext, 'camera')),
            onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(tr(sheetContext, 'gallery')),
            onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
  if (source == null) return null;
  final file = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 70);
  return file?.readAsBytes();
}

/// Form for a driver to add a vehicle, or edit [vehicle] when given.
/// Pops with `true` once saved.
class AddVehicleScreen extends StatefulWidget {
  /// Prefill number/type from the driver's profile (used for the first vehicle).
  final bool prefillFromProfile;
  final Vehicle? vehicle;

  const AddVehicleScreen({super.key, this.prefillFromProfile = false, this.vehicle});

  /// Swappable in widget tests, where the platform picker isn't available.
  @visibleForTesting
  static Future<Uint8List?> Function(BuildContext context) pickImage = pickRcImageFromDevice;

  @override
  State<AddVehicleScreen> createState() => _AddVehicleScreenState();
}

class _AddVehicleScreenState extends State<AddVehicleScreen> {
  final _formKey = GlobalKey<FormState>();
  final _numberCtrl = TextEditingController();
  final _capacityCtrl = TextEditingController();
  final _rcCtrl = TextEditingController();
  String _type = 'Mini';
  Uint8List? _rcImage;
  bool _saving = false;

  bool get _isEdit => widget.vehicle != null;

  @override
  void initState() {
    super.initState();
    final v = widget.vehicle;
    if (v != null) {
      _numberCtrl.text = v.number;
      _capacityCtrl.text = formatNum(v.capacity);
      _rcCtrl.text = v.rcNumber;
      if (vehicleTypes.contains(v.type)) _type = v.type;
    } else if (widget.prefillFromProfile) {
      _prefill();
    }
  }

  Future<void> _pickRc() async {
    try {
      final bytes = await AddVehicleScreen.pickImage(context);
      if (bytes != null && mounted) setState(() => _rcImage = bytes);
    } catch (_) {
      if (mounted) showSnack(context, tr(context, 'somethingWrong'));
    }
  }

  Widget _rcPreview() {
    final Widget image;
    if (_rcImage != null) {
      image = Image.memory(_rcImage!, fit: BoxFit.cover);
    } else if (widget.vehicle?.rcImageUrl != null) {
      image = Image.network(
        widget.vehicle!.rcImageUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined, color: AppColors.faint),
      );
    } else {
      return OutlinedButton.icon(
        onPressed: _saving ? null : _pickRc,
        icon: const Icon(Icons.upload_file_rounded),
        label: Text(tr(context, 'uploadRc')),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(height: 160, width: double.infinity, child: image),
        ),
        TextButton.icon(
          onPressed: _saving ? null : _pickRc,
          icon: const Icon(Icons.refresh_rounded),
          label: Text(tr(context, 'changeRc')),
        ),
      ],
    );
  }

  Future<void> _prefill() async {
    try {
      final data = await UserService.getUser();
      if (!mounted || data == null) return;
      final number = data['vehicleNumber'] as String?;
      final type = (data['vehicleType'] as String?)?.replaceAll(' ', '');
      setState(() {
        if (number != null && _numberCtrl.text.isEmpty) _numberCtrl.text = number;
        if (type != null && vehicleTypes.contains(type)) _type = type;
      });
    } catch (_) {
      // Prefill is best-effort; the form still works empty.
    }
  }

  @override
  void dispose() {
    _numberCtrl.dispose();
    _capacityCtrl.dispose();
    _rcCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final capacity = num.parse(_capacityCtrl.text.trim());
      if (_isEdit) {
        await VehicleService.update(
          vehicleId: widget.vehicle!.id,
          number: _numberCtrl.text,
          type: _type,
          capacity: capacity,
          rcNumber: _rcCtrl.text,
          rcImage: _rcImage,
        );
      } else {
        await VehicleService.add(
          number: _numberCtrl.text,
          type: _type,
          capacity: capacity,
          rcNumber: _rcCtrl.text,
          rcImage: _rcImage,
        );
      }
      if (!mounted) return;
      showSnack(context, tr(context, _isEdit ? 'vehicleUpdated' : 'vehicleAdded'));
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSnack(context, tr(context, 'somethingWrong'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        scrolledUnderElevation: 0,
        title: Text(tr(context, _isEdit ? 'editVehicle' : 'addVehicle'), style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FieldLabel(tr(context, 'vehicleNumber')),
                TextFormField(
                  controller: _numberCtrl,
                  textCapitalization: TextCapitalization.characters,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.pin_outlined),
                    hintText: tr(context, 'vehicleNumberHint'),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return tr(context, 'fieldRequired');
                    return VehicleService.isValidNumber(v) ? null : tr(context, 'invalidVehicleNumber');
                  },
                ),
                const SizedBox(height: 18),
                FieldLabel(tr(context, 'vehicleType')),
                DropdownButtonFormField<String>(
                  initialValue: _type,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.local_shipping_outlined)),
                  items: [for (final t in vehicleTypes) DropdownMenuItem(value: t, child: Text(t))],
                  onChanged: (v) => setState(() => _type = v ?? _type),
                ),
                const SizedBox(height: 18),
                FieldLabel(tr(context, 'capacityTons')),
                TextFormField(
                  controller: _capacityCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.scale_outlined), hintText: 'e.g. 9'),
                  validator: (v) {
                    final n = num.tryParse(v?.trim() ?? '');
                    return (n == null || n <= 0 || n > 100) ? tr(context, 'invalidNumber') : null;
                  },
                ),
                const SizedBox(height: 18),
                FieldLabel(tr(context, 'rcNumber')),
                TextFormField(
                  controller: _rcCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.description_outlined)),
                  validator: (v) => (v == null || v.trim().length < 4) ? tr(context, 'fieldRequired') : null,
                ),
                const SizedBox(height: 18),
                FieldLabel(tr(context, 'rcPhotoOptional')),
                _rcPreview(),
                const SizedBox(height: 30),
                PrimaryButton(label: tr(context, 'save'), loading: _saving, onPressed: _save),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
