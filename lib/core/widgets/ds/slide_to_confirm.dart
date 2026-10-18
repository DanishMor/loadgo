import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../theme/design_tokens.dart';
import 'haptics.dart';

/// "Slide to confirm" for the actions that should not happen by accident: booking a
/// truck, accepting a load. Drag the round handle to the end. People who use a screen
/// reader or a switch cannot drag, so the whole control is also a button: double tap
/// confirms. After [onConfirmed] the control stays on "Done" until [resetKey] changes.
class SlideToConfirm extends StatefulWidget {
  final String label;
  final VoidCallback onConfirmed;
  final bool enabled;
  final Object? resetKey;

  const SlideToConfirm({super.key, required this.label, required this.onConfirmed, this.enabled = true, this.resetKey});

  @override
  State<SlideToConfirm> createState() => _SlideToConfirmState();
}

class _SlideToConfirmState extends State<SlideToConfirm> {
  static const _thumb = 56.0;
  double _pos = 0; // 0..1 of the way
  bool _done = false;

  @override
  void didUpdateWidget(SlideToConfirm old) {
    super.didUpdateWidget(old);
    if (old.resetKey != widget.resetKey) {
      _pos = 0;
      _done = false;
    }
  }

  void _confirm() {
    if (_done || !widget.enabled) return;
    setState(() {
      _done = true;
      _pos = 1;
    });
    Haptics.success();
    widget.onConfirmed();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final on = widget.enabled && !_done;
    final bg = widget.enabled ? c.primary : c.chip;
    final fg = widget.enabled ? c.onPrimary : c.textHint;
    return Semantics(
      button: true,
      enabled: widget.enabled && !_done,
      label: widget.label,
      hint: tr(context, 'uxSlideHint'),
      onTap: on ? _confirm : null,
      excludeSemantics: true,
      child: LayoutBuilder(builder: (context, box) {
        final maxX = (box.maxWidth - _thumb - 8).clamp(1.0, double.infinity);
        final x = 4 + _pos * maxX;
        return GestureDetector(
          onHorizontalDragUpdate: on
              ? (d) => setState(() => _pos = (_pos + (rtl ? -d.delta.dx : d.delta.dx) / maxX).clamp(0.0, 1.0))
              : null,
          onHorizontalDragEnd: on
              ? (_) {
                  if (_pos >= 0.9) {
                    _confirm();
                  } else {
                    setState(() => _pos = 0);
                  }
                }
              : null,
          child: Container(
            key: const ValueKey('slideTrack'),
            width: double.infinity,
            height: DsSpace.tapBig,
            decoration: BoxDecoration(color: bg, borderRadius: DsRadius.all(DsRadius.pill)),
            child: Stack(alignment: Alignment.center, children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: _thumb + DsSpace.s3),
                child: Text(_done ? tr(context, 'uxSlideDone') : widget.label, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: DsType.subtitle.copyWith(color: fg)),
              ),
              AnimatedPositionedDirectional(
                duration: DsMotion.duration(context, DsMotion.fast),
                start: x,
                top: 4,
                child: Container(
                  key: const ValueKey('slideThumb'),
                  width: _thumb,
                  height: _thumb,
                  decoration: BoxDecoration(color: c.surface, shape: BoxShape.circle),
                  child: Icon(_done ? Icons.check_rounded : Icons.chevron_right_rounded, size: 32, color: widget.enabled ? c.primary : c.textHint),
                ),
              ),
            ]),
          ),
        );
      }),
    );
  }
}
