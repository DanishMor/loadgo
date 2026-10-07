import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/l10n/l10n.dart';
import '../core/permissions/permission_rationale.dart';
import '../core/pricing/cities.dart';
import '../core/services/location_service.dart';
import '../core/widgets/common.dart';

/// A place text field with a city typeahead (the 64-city table that prices the
/// load) and, for the pickup, a "use my location" button (M1, M2). Anything
/// typed is accepted: the list only helps. LATER(paid): geocoding / pin on map.
class PlaceField extends StatefulWidget {
  final TextEditingController controller;
  final Icon icon;
  final String? Function(String?)? validator;

  /// Extra buttons at the end of the field (saved places ...).
  final Widget? trailing;
  final bool myLocation;

  const PlaceField({super.key, required this.controller, required this.icon, this.validator, this.trailing, this.myLocation = false});

  @override
  State<PlaceField> createState() => _PlaceFieldState();
}

class _PlaceFieldState extends State<PlaceField> {
  final _focus = FocusNode();
  bool _locating = false;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Future<void> _useLocation() async {
    if (!await PermissionRationale.ask(context, RationaleKind.location) || !mounted) return;
    setState(() => _locating = true);
    final c = await LocationService.current();
    if (!mounted) return;
    setState(() => _locating = false);
    if (c == null) return showSnack(context, tr(context, 'placeNoLocation'));
    final city = nearestCity(c.lat, c.lng);
    if (city == null) return showSnack(context, tr(context, 'placeFarFromCities'));
    widget.controller.text = city.name;
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<City>(
      textEditingController: widget.controller,
      focusNode: _focus,
      displayStringForOption: (c) => c.name,
      optionsBuilder: (v) => suggestCities(v.text),
      fieldViewBuilder: (context, controller, focus, onSubmit) => TextFormField(
        controller: controller,
        focusNode: focus,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.next,
        decoration: InputDecoration(
          prefixIcon: widget.icon,
          suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
            if (widget.myLocation)
              IconButton(
                key: const ValueKey('useMyLocation'),
                tooltip: tr(context, 'placeUseMyLocation'),
                icon: _locating
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.my_location_rounded),
                onPressed: _locating ? null : _useLocation,
              ),
            ?widget.trailing,
          ]),
        ),
        validator: widget.validator,
        inputFormatters: [LengthLimitingTextInputFormatter(100)],
      ),
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(12),
          color: AppColors.card,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240, maxWidth: 360),
            child: ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              children: [
                for (final c in options)
                  ListTile(
                    key: ValueKey('city_${c.name}'),
                    dense: true,
                    leading: const Icon(Icons.location_city_rounded, size: 18),
                    title: Text(c.name),
                    subtitle: Text(c.state),
                    onTap: () => onSelected(c),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
