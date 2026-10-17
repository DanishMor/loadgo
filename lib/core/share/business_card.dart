import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import '../app_info.dart';
import '../l10n/l10n.dart';
import '../services/user_service.dart';
import '../theme/design_tokens.dart';
import '../widgets/common.dart';
import '../widgets/ds/app_button.dart';
import '../widgets/ds/app_top_bar.dart';
import '../widgets/ds/status_badge.dart';

/// What goes on a business card (G24). Built from the person's own profile; nothing is stored and nothing is added.
/// The phone number is on the card only when the person turns it on, every time.
class BusinessCardData {
  final String name;
  final String city;
  final List<String> routes;
  final List<String> vehicleTypes;
  final int vehicleCount;
  final bool verified;
  final String phone;

  const BusinessCardData({required this.name, this.city = '', this.routes = const [], this.vehicleTypes = const [], this.vehicleCount = 0, this.verified = false, this.phone = ''});

  static const maxRoutes = 4;
  static const maxTypes = 4;

  static List<String> _strings(Object? v, int max) =>
      v is List ? [for (final e in v) if (e is String && e.trim().isNotEmpty) e.trim().length > 40 ? e.trim().substring(0, 40) : e.trim()].take(max).toList() : const [];

  /// Company for a transporter, driver name for a driver, else the plain name. Every field is read defensively.
  factory BusinessCardData.fromUser(Map<String, dynamic>? u) {
    final m = u ?? const <String, dynamic>{};
    String s(Object? v) => v is String ? v.trim() : '';
    final fleet = m['fleet'] is Map ? Map<String, dynamic>.from(m['fleet'] as Map) : const <String, dynamic>{};
    final name = [s(m['companyName']), s(m['driverName']), s(m['name'])].firstWhere((x) => x.isNotEmpty, orElse: () => '');
    final count = fleet['vehicleCount'];
    return BusinessCardData(
      name: name.length > 60 ? name.substring(0, 60) : name,
      city: s(fleet['officeCity']),
      routes: _strings(fleet['routes'], maxRoutes),
      vehicleTypes: _strings(fleet['vehicleTypes'], maxTypes),
      vehicleCount: count is int && count > 0 && count < 100000 ? count : 0,
      verified: m['verified'] == true,
      phone: s(m['phone']),
    );
  }

  bool get isEmpty => name.isEmpty;

  /// A plain-text version, for the apps that do not take a picture.
  String asText(String Function(int n) fleetLabel) {
    final b = StringBuffer(name);
    if (city.isNotEmpty) b.write('\n$city');
    if (vehicleCount > 0) b.write('\n${fleetLabel(vehicleCount)}');
    if (routes.isNotEmpty) b.write('\n${routes.join(', ')}');
    if (vehicleTypes.isNotEmpty) b.write('\n${vehicleTypes.join(', ')}');
    if (phone.isNotEmpty) b.write('\n$phone');
    b.write('\n${AppInfo.name}');
    return b.toString();
  }
}

/// The card itself, a fixed 340 wide picture so the shared image looks the same on every phone.
class BusinessCardView extends StatelessWidget {
  final BusinessCardData data;
  final bool showPhone;
  const BusinessCardView({super.key, required this.data, this.showPhone = false});

  @override
  Widget build(BuildContext context) {
    final c = DsColors.of(Brightness.light); // always light: it is a picture that others see
    return Container(
      width: 340,
      padding: const EdgeInsets.all(DsSpace.s5),
      decoration: BoxDecoration(color: c.surface, borderRadius: DsRadius.all(DsRadius.lg), border: Border.all(color: c.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: c.primary, borderRadius: DsRadius.all(DsRadius.md)),
            child: Icon(Icons.local_shipping_rounded, color: c.onPrimary),
          ),
          const SizedBox(width: DsSpace.s3),
          Expanded(child: Text(data.name, style: DsType.title.copyWith(color: c.textStrong))),
        ]),
        if (data.verified)
          Padding(
            padding: const EdgeInsets.only(top: DsSpace.s2),
            child: StatusBadge(label: trf(context, 'bizVerified', {'app': AppInfo.name}), tone: StatusTone.success, icon: Icons.verified_rounded),
          ),
        const SizedBox(height: DsSpace.s3),
        if (data.city.isNotEmpty) _line(c, Icons.place_outlined, data.city),
        if (data.vehicleCount > 0) _line(c, Icons.local_shipping_outlined, trf(context, 'bizFleet', {'n': data.vehicleCount})),
        if (data.vehicleTypes.isNotEmpty) _line(c, Icons.category_outlined, data.vehicleTypes.join(', ')),
        if (data.routes.isNotEmpty) _line(c, Icons.alt_route_rounded, data.routes.join(', ')),
        if (showPhone && data.phone.isNotEmpty) _line(c, Icons.phone_outlined, data.phone),
        const SizedBox(height: DsSpace.s3),
        Text('${AppInfo.name} • ${tr(context, 'bizOnApp')}', style: DsType.caption.copyWith(color: c.textMuted)),
      ]),
    );
  }

  Widget _line(DsColors c, IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: DsSpace.s1),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: c.textMuted),
          const SizedBox(width: DsSpace.s2),
          Expanded(child: Text(text, style: DsType.body.copyWith(color: c.text))),
        ]),
      );
}

/// G24: preview, the phone switch (off), and Share as a picture or, if that fails, as text. Behind `bizCard`.
class BusinessCardScreen extends StatefulWidget {
  /// Tests give the profile directly.
  final Map<String, dynamic>? profile;

  /// Tests replace sharing.
  final Future<void> Function(Uint8List png, String text)? onShare;

  const BusinessCardScreen({super.key, this.profile, this.onShare});

  @override
  State<BusinessCardScreen> createState() => _BusinessCardScreenState();
}

class _BusinessCardScreenState extends State<BusinessCardScreen> {
  final _key = GlobalKey();
  bool _phone = false;
  bool _busy = false;
  late final Future<Map<String, dynamic>?> _profile = widget.profile != null ? Future.value(widget.profile) : UserService.getUser();

  Future<Uint8List?> _png() async {
    final boundary = _key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes?.buffer.asUint8List();
  }

  Future<void> _share(BusinessCardData d) async {
    setState(() => _busy = true);
    try {
      final text = BusinessCardData(name: d.name, city: d.city, routes: d.routes, vehicleTypes: d.vehicleTypes, vehicleCount: d.vehicleCount, verified: d.verified, phone: _phone ? d.phone : '')
          .asText((n) => trf(context, 'bizFleet', {'n': n}));
      final png = await _png();
      if (widget.onShare != null) {
        await widget.onShare!(png ?? Uint8List(0), text);
      } else if (png != null) {
        await SharePlus.instance.share(ShareParams(files: [XFile.fromData(png, mimeType: 'image/png', name: 'load20_card.png')], text: text));
      } else {
        await SharePlus.instance.share(ShareParams(text: text));
      }
    } catch (_) {
      if (mounted) showSnack(context, tr(context, 'bizShareFailed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Scaffold(
      appBar: AppTopBar(title: tr(context, 'bizTitle')),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _profile,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          final d = BusinessCardData.fromUser(snap.hasError ? null : snap.data);
          if (d.isEmpty) return Center(child: Padding(padding: const EdgeInsets.all(DsSpace.s6), child: Text(tr(context, 'bizNoProfile'), textAlign: TextAlign.center, style: DsType.body.copyWith(color: c.textMuted))));
          return ListView(padding: const EdgeInsets.all(DsSpace.s4), children: [
            Center(child: RepaintBoundary(key: _key, child: BusinessCardView(data: d, showPhone: _phone))),
            const SizedBox(height: DsSpace.s3),
            SwitchListTile(
              key: const ValueKey('bizPhoneSwitch'),
              contentPadding: EdgeInsets.zero,
              title: Text(tr(context, 'bizShowPhone')),
              subtitle: Text(tr(context, 'bizShowPhoneHint'), style: DsType.caption.copyWith(color: c.textMuted)),
              value: _phone,
              onChanged: d.phone.isEmpty ? null : (v) => setState(() => _phone = v),
            ),
            const SizedBox(height: DsSpace.s2),
            AppButton(key: const ValueKey('bizShare'), label: tr(context, 'bizShare'), icon: Icons.share_rounded, loading: _busy, onPressed: () => _share(d)),
          ]);
        },
      ),
    );
  }
}
