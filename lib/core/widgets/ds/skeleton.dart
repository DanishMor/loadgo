import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../theme/design_tokens.dart';

/// Wraps a tree of [SkeletonBox]es and makes it pulse gently while a soft
/// highlight drifts across each box (E9 shimmer). With "remove animations" or
/// Low-end mode it stays still. One controller for the whole tree, so a long
/// list of grey placeholders costs the same as one.
class Skeleton extends StatefulWidget {
  final Widget child;
  const Skeleton({super.key, required this.child});

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  late final Animation<double> _opacity = Tween<double>(begin: 0.7, end: 1).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut));

  /// Starts or stops the pulse to match "remove animations" / Low-end mode. Runs
  /// on every build, and a theme change (which Low-end mode causes) rebuilds us.
  void _sync(BuildContext context) {
    Theme.of(context);
    if (DsMotion.reduced(context)) {
      if (_c.isAnimating || _c.value != 1) {
        _c.stop();
        _c.value = 1;
      }
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _sync(context);
    final still = DsMotion.reduced(context);
    return _ShimmerScope(
      notifier: still ? null : _c,
      child: FadeTransition(opacity: _opacity, child: widget.child),
    );
  }
}

/// Hands the skeleton's controller to its boxes; null while motion is reduced.
class _ShimmerScope extends InheritedNotifier<Animation<double>> {
  const _ShimmerScope({required super.notifier, required super.child});

  static double? of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_ShimmerScope>()?.notifier?.value;
}

/// A grey block standing in for text, an image or a button while data loads.
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;

  const SkeletonBox({super.key, this.width, this.height = 16, this.radius = DsRadius.sm});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final v = _ShimmerScope.of(context);
    final highlight = Color.lerp(c.chip, c.surface, 0.6)!;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: v == null ? c.chip : null,
        // The highlight band moves from one edge to the other as the controller runs.
        gradient: v == null ? null : LinearGradient(begin: Alignment(-3 + 4 * v, 0), end: Alignment(-1 + 4 * v, 0), colors: [c.chip, highlight, c.chip]),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// A placeholder for a card: a title line, two shorter lines and a badge.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(DsSpace.s4),
      decoration: BoxDecoration(color: c.surface, borderRadius: DsRadius.all(DsRadius.lg), border: Border.all(color: c.border)),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(height: 20, width: 200),
          SizedBox(height: DsSpace.s3),
          SkeletonBox(height: 14),
          SizedBox(height: DsSpace.s2),
          SkeletonBox(height: 14, width: 140),
          SizedBox(height: DsSpace.s4),
          SkeletonBox(height: 24, width: 88, radius: DsRadius.pill),
        ],
      ),
    );
  }
}

/// A list of [count] placeholder cards, the stand-in for a loading list.
/// Announced to screen readers as "Loading".
class SkeletonList extends StatelessWidget {
  final int count;
  final EdgeInsetsGeometry padding;
  final WidgetBuilder? itemBuilder;

  const SkeletonList({super.key, this.count = 4, this.padding = const EdgeInsets.all(DsSpace.gutter), this.itemBuilder});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: tr(context, 'dsLoading'),
      liveRegion: true,
      child: ExcludeSemantics(
        child: Skeleton(
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            padding: padding,
            child: Column(
              children: [
                for (var i = 0; i < count; i++) ...[
                  if (i > 0) const SizedBox(height: DsSpace.s3),
                  itemBuilder?.call(context) ?? const SkeletonCard(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
