import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/l10n/l10n.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/design_tokens.dart';
import '../core/widgets/ds/app_text_field.dart';
import '../core/widgets/ds/motion.dart';

/// The top of every login page: an icon tile in the role's own colour (it pops
/// in), the heading (a header for screen readers) and one line under it.
class LoginHeader extends StatelessWidget {
  /// 'customer', 'driver' or 'transporter'.
  final String role;
  final IconData icon;
  final String title;
  final String subtitle;

  const LoginHeader({super.key, required this.role, required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final accent = RoleAccents.of(context).forRole(role, c.primary);
    return Column(
      children: [
        const SizedBox(height: DsSpace.s4),
        PopIn(
          child: Container(
            key: ValueKey('loginIcon_$role'),
            width: 82,
            height: 82,
            decoration: BoxDecoration(color: accent.withValues(alpha: 0.14), borderRadius: DsRadius.all(DsRadius.xl)),
            child: Icon(icon, size: 45, color: accent),
          ),
        ),
        const SizedBox(height: DsSpace.s6),
        FadeSlideIn(
          delay: const Duration(milliseconds: 100),
          child: Semantics(header: true, child: Text(title, textAlign: TextAlign.center, style: DsType.headline.copyWith(fontSize: 28, color: c.text))),
        ),
        const SizedBox(height: DsSpace.s2),
        FadeSlideIn(
          delay: const Duration(milliseconds: 180),
          child: Text(subtitle, textAlign: TextAlign.center, style: DsType.body.copyWith(color: c.textMuted)),
        ),
      ],
    );
  }
}

/// The mobile-number field: label, flag and +91 in front, 10 digits only, and
/// the same messages as before for a missing or wrong number (Indian mobile
/// numbers start with 6 to 9).
class PhoneFormField extends StatelessWidget {
  final TextEditingController controller;
  const PhoneFormField({super.key, required this.controller});

  static String? validate(BuildContext context, String? value) {
    final phone = value?.trim() ?? '';
    if (phone.isEmpty) return tr(context, 'required');
    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(phone)) return tr(context, 'invalidMobile');
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AppTextFormField(
      fieldKey: const ValueKey('phoneField'),
      label: tr(context, 'mobile'),
      controller: controller,
      hint: tr(context, 'mobileHint'),
      keyboardType: TextInputType.phone,
      textInputAction: TextInputAction.done,
      maxLength: 10,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      autofillHints: const [AutofillHints.telephoneNumberNational],
      prefix: const Padding(
        padding: EdgeInsetsDirectional.only(start: DsSpace.s4, end: DsSpace.s2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('🇮🇳', style: DsStyle.t20w400),
            SizedBox(width: DsSpace.s2),
            Directionality(textDirection: TextDirection.ltr, child: Text('+91', style: DsStyle.w600)),
          ],
        ),
      ),
      validator: (v) => validate(context, v),
    );
  }
}

/// "or" between two ways to continue.
class OrDivider extends StatelessWidget {
  const OrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Row(
      children: [
        Expanded(child: Divider(color: c.border)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: DsSpace.s3),
          child: Text(tr(context, 'or'), style: DsType.caption.copyWith(color: c.textMuted, fontWeight: FontWeight.w600)),
        ),
        Expanded(child: Divider(color: c.border)),
      ],
    );
  }
}
