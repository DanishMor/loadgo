import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../../theme/design_tokens.dart';
import 'haptics.dart';

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

/// E9: a spring as a [Curve], for sheets, cards and hero flights. Soft: at most
/// one small overshoot (damping ratio about 0.8), settled by the end.
class SpringCurve extends Curve {
  final SpringDescription spring;

  /// Seconds of spring time mapped onto 0..1 of the animation.
  final double span;
  const SpringCurve({this.spring = const SpringDescription(mass: 1, stiffness: 380, damping: 30), this.span = 0.6});

  static const gentle = SpringCurve();

  @override
  double transformInternal(double t) => SpringSimulation(spring, 0, 1, 0).x(t * span);
}

/// E9: the animation budget every screen keeps (docs/MOTION.md). Entrance
/// motion is finished within [entrance]; at most [looping] repeating animation
/// runs at a time (a skeleton or a radar pulse); a success moment stays under
/// [success]. test/motion_budget_test.dart checks the code against it.
class MotionBudget {
  MotionBudget._();
  static const entrance = Duration(milliseconds: 700);
  static const success = Duration(milliseconds: 600);
  static const looping = 1;
}

/// E9: the restrained "done" moment: a tick in a soft circle pops in once with
/// one success haptic, and a screen reader hears [label]. With reduced motion
/// it is simply there (the haptic still marks the moment).
class SuccessMoment extends StatefulWidget {
  final String label;
  final double size;
  const SuccessMoment({super.key, required this.label, this.size = 72});

  /// Pop duration, inside [MotionBudget.success].
  static const duration = Duration(milliseconds: 420);

  @override
  State<SuccessMoment> createState() => _SuccessMomentState();
}

class _SuccessMomentState extends State<SuccessMoment> {
  @override
  void initState() {
    super.initState();
    Haptics.on(HapticEvent.success);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Semantics(
      liveRegion: true,
      label: widget.label,
      excludeSemantics: true,
      child: PopIn(
        duration: SuccessMoment.duration,
        from: 0.8,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(color: c.successBg, shape: BoxShape.circle),
          child: Icon(Icons.check_rounded, size: widget.size * 0.55, color: c.success),
        ),
      ),
    );
  }
}

/// E9: a Hero that flies between two screens, or stays put when motion is reduced.
class DsHeroTag extends StatelessWidget {
  final Object tag;
  final Widget child;
  const DsHeroTag({super.key, required this.tag, required this.child});

  @override
  Widget build(BuildContext context) => DsMotion.reduced(context) ? child : Hero(tag: tag, child: Material(type: MaterialType.transparency, child: child));
}
