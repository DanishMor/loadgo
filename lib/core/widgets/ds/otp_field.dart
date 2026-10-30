import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/l10n.dart';
import '../../theme/design_tokens.dart';
import 'haptics.dart';

/// A one-time-code input: [length] boxes (6 by default), one real text field
/// underneath. Because it is one field the phone's SMS code suggestion, paste,
/// backspace and the number pad all work, and the next box lights up by itself
/// as digits go in ("auto-advance"). Digits are always left to right, also in
/// Urdu and Kashmiri.
///
/// [fieldKey] goes on the inner text field (tests type into it).
class OtpField extends StatefulWidget {
  final TextEditingController? controller;
  final int length;
  final ValueChanged<String>? onChanged;

  /// Called once when the last box is filled.
  final ValueChanged<String>? onCompleted;
  final bool error;
  final bool autofocus;
  final bool enabled;
  final Key? fieldKey;

  const OtpField({
    super.key,
    this.controller,
    this.length = 6,
    this.onChanged,
    this.onCompleted,
    this.error = false,
    this.autofocus = false,
    this.enabled = true,
    this.fieldKey,
  });

  @override
  State<OtpField> createState() => _OtpFieldState();
}

class _OtpFieldState extends State<OtpField> {
  late final TextEditingController _own = TextEditingController();
  late final FocusNode _focus = FocusNode();
  TextEditingController get _c => widget.controller ?? _own;
  String _last = '';

  @override
  void initState() {
    super.initState();
    _last = _c.text;
    _c.addListener(_changed);
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _c.removeListener(_changed);
    _own.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _changed() {
    final t = _c.text;
    if (t == _last) return;
    _last = t;
    setState(() {});
    widget.onChanged?.call(t);
    if (t.length == widget.length) {
      Haptics.tap();
      widget.onCompleted?.call(t);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final text = _c.text;
    final active = _focus.hasFocus ? text.length.clamp(0, widget.length - 1) : -1;
    final label = trf(context, 'dsOtpLabel', {'n': text.length, 'm': widget.length});

    Widget box(int i) {
      final filled = i < text.length;
      final isActive = i == active && widget.enabled;
      final color = widget.error ? c.error : (isActive ? c.focus : (filled ? c.primary : c.inputBorder));
      return Expanded(
        child: Padding(
          padding: EdgeInsets.only(left: i == 0 ? 0 : DsSpace.s2),
          child: AnimatedContainer(
            duration: DsMotion.duration(context, DsMotion.fast),
            constraints: const BoxConstraints(minHeight: 56),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: DsRadius.all(DsRadius.md),
              border: Border.all(color: color, width: isActive || widget.error ? 2 : 1),
            ),
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.3,
              child: Text(filled ? text[i] : '', style: DsType.number.copyWith(fontSize: 24, fontWeight: FontWeight.w700, color: c.text)),
            ),
          ),
        ),
      );
    }

    return Semantics(
      container: true,
      textField: true,
      label: label,
      child: ExcludeSemantics(
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            children: [
              Row(children: [for (var i = 0; i < widget.length; i++) box(i)]),
              // The real field: invisible, but it gets the taps, the keyboard and the paste.
              Positioned.fill(
                child: Opacity(
                  opacity: 0,
                  child: TextField(
                    key: widget.fieldKey,
                    controller: _c,
                    focusNode: _focus,
                    enabled: widget.enabled,
                    autofocus: widget.autofocus,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    showCursor: false,
                    enableInteractiveSelection: false,
                    maxLength: widget.length,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(widget.length)],
                    decoration: const InputDecoration(counterText: '', border: InputBorder.none, fillColor: Colors.transparent),
                    style: DsType.body.copyWith(fontSize: 1, color: Colors.transparent),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A seconds-left counter for "resend in 42 s". The screen owns one and calls
/// [start]; widgets listen to it.
class CountdownController extends ChangeNotifier {
  int _left = 0;
  Timer? _timer;

  int get secondsLeft => _left;
  bool get running => _left > 0;

  void start(int seconds) {
    _timer?.cancel();
    _left = seconds;
    notifyListeners();
    if (seconds <= 0) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      _left--;
      if (_left <= 0) {
        _left = 0;
        t.cancel();
      }
      notifyListeners();
    });
  }

  void stop() {
    _timer?.cancel();
    _left = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// "Resend in 42 s" while counting, "Resend code" when it may be pressed.
class OtpResendButton extends StatelessWidget {
  final CountdownController countdown;
  final bool busy;
  final VoidCallback onPressed;

  /// The key of the button itself (tests and screens that look for it).
  final Key? buttonKey;

  const OtpResendButton({super.key, required this.countdown, required this.onPressed, this.busy = false, this.buttonKey});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: countdown,
      builder: (context, _) {
        final waiting = countdown.running;
        return TextButton(
          key: buttonKey,
          onPressed: waiting || busy ? null : onPressed,
          child: Text(waiting ? trf(context, 'resendIn', {'s': countdown.secondsLeft}) : tr(context, 'resendOtp')),
        );
      },
    );
  }
}
