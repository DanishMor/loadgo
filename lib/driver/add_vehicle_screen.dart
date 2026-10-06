import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../core/constants/logistics.dart';
import '../core/models/vehicle.dart';
import '../core/services/user_service.dart';
import '../core/services/vehicle_service.dart';
import '../core/widgets/common.dart';
import '../core/l10n/l10n.dart';
import '../core/services/vehicle_type_service.dart';
import '../core/widgets/logistics_labels.dart';

/// Lets the driver pick an RC photo from camera or gallery (compressed).
Future<Uint8List?> pickRcImageFromDevice(BuildContext context) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    showDragHandle: true,
    backgroundColor: AppColors.card,
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
  final _lengthCtrl = TextEditingController();
  final _widthCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();
  String? _fuel;
  String? _bodyType;
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
      _type = v.type;
      final p = v.profile;
      if (p.lengthM != null) _lengthCtrl.text = '${p.lengthM}';
      if (p.widthM != null) _widthCtrl.text = '${p.widthM}';
      if (p.heightM != null) _heightCtrl.text = '${p.heightM}';
      _fuel = p.fuel;
      _bodyType = p.bodyType;
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
        errorBuilder: (_, _, _) => Icon(Icons.broken_image_outlined, color: AppColors.faint),
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
        if (type != null && VehicleTypeService.byId(type) != null) _type = type;
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
    _lengthCtrl.dispose();
    _widthCtrl.dispose();
    _heightCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final capacity = num.parse(_capacityCtrl.text.trim());
      double? dim(TextEditingController c) => double.tryParse(c.text.trim());
      final profile = VehicleProfile(
        lengthM: dim(_lengthCtrl),
        widthM: dim(_widthCtrl),
        heightM: dim(_heightCtrl),
        fuel: _fuel,
        bodyType: _bodyType,
      );
      if (_isEdit) {
        await VehicleService.update(
          vehicleId: widget.vehicle!.id,
          number: _numberCtrl.text,
          type: _type,
          capacity: capacity,
          rcNumber: _rcCtrl.text,
          rcImage: _rcImage,
          profile: profile,
        );
      } else {
        await VehicleService.add(
          number: _numberCtrl.text,
          type: _type,
          capacity: capacity,
          rcNumber: _rcCtrl.text,
          rcImage: _rcImage,
          profile: profile,
        );
      }
      if (!mounted) return;
      showSnack(context, tr(context, _isEdit ? 'vehicleUpdated' : 'vehicleAdded'));
      Navigator.of(context).pop(true);
    } on DuplicateVehicleException {
      if (!mounted) return;
      setState(() => _saving = false);
      showSnack(context, tr(context, 'duplicateVehicle'));
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
                  }, inputFormatters: [LengthLimitingTextInputFormatter(100)]),
                const SizedBox(height: 18),
                FieldLabel(tr(context, 'vehicleType')),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _type,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.local_shipping_outlined)),
                  items: vehicleTypeItems(context, keep: _type),
                  onChanged: (v) => setState(() => _type = v ?? _type),
                ),
                if (VehicleTypeService.byId(_type) case final info?)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 4),
                    child: Text(vehicleTypeRange(context, info), style: TextStyle(color: AppColors.muted, fontSize: 12)),
                  ),
                const SizedBox(height: 18),
                FieldLabel(tr(context, 'capacityTons')),
                TextFormField(
                  controller: _capacityCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(prefixIcon: const Icon(Icons.scale_outlined), hintText: '${tr(context, 'exampleShort')} 9'),
                  validator: (v) {
                    final n = num.tryParse(v?.trim() ?? '');
                    return (n == null || n <= 0 || n > 100) ? tr(context, 'invalidNumber') : null;
                  }, inputFormatters: [LengthLimitingTextInputFormatter(100)]),
                const SizedBox(height: 18),
                FieldLabel(tr(context, 'rcNumber')),
                TextFormField(
                  controller: _rcCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.description_outlined)),
                  validator: (v) => (v == null || v.trim().length < 4) ? tr(context, 'fieldRequired') : null, inputFormatters: [LengthLimitingTextInputFormatter(100)]),
                const SizedBox(height: 18),
                FieldLabel(tr(context, 'vehicleDimensions')),
                Row(children: [
                  for (final (key, ctrl, label) in [
                    ('vehLength', _lengthCtrl, 'lengthM'),
                    ('vehWidth', _widthCtrl, 'widthM'),
                    ('vehHeight', _heightCtrl, 'heightM'),
                  ])
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: TextFormField(
                          key: ValueKey(key),
                          controller: ctrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(labelText: tr(context, label)),
                          validator: (v) {
                            final t = v?.trim() ?? '';
                            if (t.isEmpty) return null;
                            return VehicleProfile.validDimension(double.tryParse(t)) ? null : tr(context, 'invalidNumber');
                          }, inputFormatters: [LengthLimitingTextInputFormatter(100)]),
                      ),
                    ),
                ]),
                const SizedBox(height: 18),
                FieldLabel(tr(context, 'fuelType')),
                DropdownButtonFormField<String?>(
                  isExpanded: true,
                  key: const ValueKey('vehFuel'),
                  initialValue: _fuel,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.local_gas_station_outlined)),
                  items: [
                    DropdownMenuItem(value: null, child: Text(tr(context, 'notSpecified'))),
                    for (final f in FuelType.all) DropdownMenuItem(value: f, child: Text(tr(context, 'fuel_$f'))),
                  ],
                  onChanged: (v) => setState(() => _fuel = v),
                ),
                const SizedBox(height: 18),
                FieldLabel(tr(context, 'bodyTypeLabel')),
                DropdownButtonFormField<String?>(
                  isExpanded: true,
                  key: const ValueKey('vehBody'),
                  initialValue: _bodyType,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.view_in_ar_outlined)),
                  items: [
                    DropdownMenuItem(value: null, child: Text(tr(context, 'notSpecified'))),
                    for (final b in BodyType.all) DropdownMenuItem(value: b, child: Text(tr(context, 'body_$b'))),
                  ],
                  onChanged: (v) => setState(() => _bodyType = v),
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
