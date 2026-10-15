import 'package:flutter/material.dart';

import '../../theme/design_tokens.dart';

/// Fades its child in while it slides up a few pixels, once, when it first
/// appears. Give each item of a list a growing [delay] (see [staggerDelay]) to
/// let them arrive one after the other. With "remove animations" or Low-end
/// mode the child is simply there at once: no timer, no controller running.
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;
  final double offset;

  const FadeSlideIn({super.key, required this.child, this.delay = Duration.zero, this.duration = DsMotion.slow, this.offset = 16});

  /// 60 ms per position, at most 6 steps, so a long list does not make people wait.
  static Duration staggerDelay(int index) => Duration(milliseconds: 60 * (index > 6 ? 6 : index));

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  AnimationController? _c;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (DsMotion.reduced(context)) return; // shown at once
    final c = _c = AnimationController(vsync: this, duration: widget.duration);
    if (widget.delay == Duration.zero) {
      c.forward();
    } else {
      Future<void>.delayed(widget.delay, () {
        if (mounted) c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null) return widget.child;
    final curve = CurvedAnimation(parent: c, curve: DsMotion.standard);
    return AnimatedBuilder(
      animation: curve,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: curve.value,
        child: Transform.translate(offset: Offset(0, (1 - curve.value) * widget.offset), child: child),
      ),
    );
  }
}

/// A short "pop": scales up from [from] to 1 with a soft overshoot. For a
/// ticked circle, a badge that just changed, a logo on the splash screen.
class PopIn extends StatefulWidget {
  final Widget child;
  final double from;
  final Duration duration;

  const PopIn({super.key, required this.child, this.from = 0.6, this.duration = DsMotion.slow});

  @override
  State<PopIn> createState() => _PopInState();
}

class _PopInState extends State<PopIn> with SingleTickerProviderStateMixin {
  AnimationController? _c;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (DsMotion.reduced(context)) return;
    _c = AnimationController(vsync: this, duration: widget.duration)..forward();
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null) return widget.child;
    final curve = CurvedAnimation(parent: c, curve: Curves.easeOutBack);
    return AnimatedBuilder(
      animation: curve,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: c.value.clamp(0.0, 1.0),
        child: Transform.scale(scale: widget.from + (1 - widget.from) * curve.value, child: child),
      ),
    );
  }
}
