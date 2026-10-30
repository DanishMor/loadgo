import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/design_tokens.dart';

/// A labelled text input. The label sits above the box (never a floating label
/// that jumps at 2.0x text), then the box with a 3:1 border and a 2 px focus
/// ring, then one line of help or error text. The look comes from the theme.
class AppTextField extends StatelessWidget {
  final String label;
  final TextEditingController? controller;
  final String? hint;
  final String? helper;

  /// When set the field shows the error colour and this text.
  final String? error;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final int? maxLength;
  final int minLines;
  final int maxLines;
  final bool obscure;
  final bool enabled;
  final bool autofocus;
  final String? prefixText;
  final Widget? suffix;
  final IconData? prefixIcon;

  /// Any widget in front of the text (a flag and +91). Wins over [prefixIcon].
  final Widget? prefix;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Iterable<String>? autofillHints;
  final FocusNode? focusNode;
  final Key? fieldKey;

  const AppTextField({
    super.key,
    required this.label,
    this.controller,
    this.hint,
    this.helper,
    this.error,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.maxLength,
    this.minLines = 1,
    this.maxLines = 1,
    this.obscure = false,
    this.enabled = true,
    this.autofocus = false,
    this.prefixText,
    this.suffix,
    this.prefixIcon,
    this.prefix,
    this.onChanged,
    this.onSubmitted,
    this.autofillHints,
    this.focusNode,
    this.fieldKey,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final hasError = error != null && error!.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: DsSpace.s2),
          child: Text(label, style: DsType.label.copyWith(color: c.textStrong)),
        ),
        TextField(
          key: fieldKey,
          controller: controller,
          focusNode: focusNode,
          enabled: enabled,
          autofocus: autofocus,
          obscureText: obscure,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          inputFormatters: inputFormatters,
          maxLength: maxLength,
          minLines: obscure ? 1 : minLines,
          maxLines: obscure ? 1 : maxLines,
          autofillHints: autofillHints,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          style: DsType.body.copyWith(color: c.text),
          decoration: InputDecoration(
            hintText: hint,
            counterText: '',
            prefixText: prefixText,
            prefixStyle: DsType.body.copyWith(color: c.textStrong),
            prefixIcon: prefix ?? (prefixIcon == null ? null : Icon(prefixIcon, color: c.textMuted)),
            suffixIcon: suffix,
            errorText: null,
            enabledBorder: hasError ? _border(c.error, 2) : null,
            focusedBorder: hasError ? _border(c.error, 2) : null,
          ),
        ),
        if (hasError || (helper != null && helper!.isNotEmpty))
          Padding(
            padding: const EdgeInsets.only(top: DsSpace.s1),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasError) ...[Icon(Icons.error_outline_rounded, size: 16, color: c.error), const SizedBox(width: DsSpace.s1)],
                Expanded(child: Text(hasError ? error! : helper!, style: DsType.caption.copyWith(color: hasError ? c.error : c.textMuted))),
              ],
            ),
          ),
      ],
    );
  }

  OutlineInputBorder _border(Color color, double w) => OutlineInputBorder(borderRadius: DsRadius.all(DsRadius.md), borderSide: BorderSide(color: color, width: w));
}

/// [AppTextField] inside a `Form`: it runs [validator] on `formKey.currentState!.validate()`
/// and shows the message under the box with the error icon. The text is read from
/// [controller], so setting the controller from code works too.
class AppTextFormField extends FormField<String> {
  AppTextFormField({
    super.key,
    required String label,
    required TextEditingController controller,
    String? hint,
    String? helper,
    Widget? prefix,
    String? prefixText,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    List<TextInputFormatter>? inputFormatters,
    int? maxLength,
    FormFieldValidator<String>? validator,
    super.autovalidateMode,
    Iterable<String>? autofillHints,
    ValueChanged<String>? onSubmitted,
    Key? fieldKey,
    bool autofocus = false,
  }) : super(
          initialValue: controller.text,
          validator: validator == null ? null : (_) => validator(controller.text),
          builder: (state) => AppTextField(
            fieldKey: fieldKey,
            label: label,
            controller: controller,
            hint: hint,
            helper: helper,
            prefix: prefix,
            prefixText: prefixText,
            keyboardType: keyboardType,
            textInputAction: textInputAction,
            inputFormatters: inputFormatters,
            maxLength: maxLength,
            autofillHints: autofillHints,
            autofocus: autofocus,
            error: state.errorText,
            onChanged: (v) {
              state.didChange(v);
            },
            onSubmitted: onSubmitted,
          ),
        );
}
