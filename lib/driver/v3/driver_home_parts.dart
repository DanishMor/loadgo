import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/adapters/connect_adapters.dart' show DemandCell;
import '../../core/home/driver_home_logic.dart';
import '../../core/l10n/l10n.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/ds/app_button.dart';

/// E22: the driver's own daily goal in rupees, kept on the phone (no server read or write).
class DailyGoalStore {
  DailyGoalStore._();

  static const key = 'driver_daily_goal_rupees';
  static const max = 200000;

  static Future<int?> load() async {
    try {
      final v = (await SharedPreferences.getInstance()).getInt(key);
      return v != null && v > 0 && v <= max ? v : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(int? rupees) async {
    try {
      final p = await SharedPreferences.getInstance();
      if (rupees == null) {
        await p.remove(key);
      } else {
        await p.setInt(key, rupees.clamp(1, max));
      }
    } catch (_) {}
  }
}

/// Asks for a daily goal in whole rupees. Returns the goal, 0 to clear it, or null when dismissed.
Future<int?> askDailyGoal(BuildContext context, int? current) => showDialog<int>(
      context: context,
      builder: (_) => _GoalDialog(current: current),
    );

class _GoalDialog extends StatefulWidget {
  final int? current;
  const _GoalDialog({this.current});

  @override
  State<_GoalDialog> createState() => _GoalDialogState();
}

class _GoalDialogState extends State<_GoalDialog> {
  late final _ctrl = TextEditingController(text: widget.current?.toString() ?? '');
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _save() {
    final v = int.tryParse(_ctrl.text.trim());
    if (v == null || v < 1 || v > DailyGoalStore.max) {
      setState(() => _error = tr(context, 'invalidNumber'));
      return;
    }
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(tr(context, 'd3GoalTitle')),
        content: TextField(
          key: const ValueKey('d3GoalField'),
          controller: _ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
          decoration: InputDecoration(prefixText: '₹ ', errorText: _error, helperText: tr(context, 'd3GoalHelp')),
          onSubmitted: (_) => _save(),
        ),
        actions: [
          if (widget.current != null) TextButton(key: const ValueKey('d3GoalClear'), onPressed: () => Navigator.pop(context, 0), child: Text(tr(context, 'd3GoalClear'))),
          FilledButton(key: const ValueKey('d3GoalSave'), onPressed: _save, child: Text(tr(context, 'hlDone'))),
        ],
      );
}

/// Expanding rings around a dot while the driver is online and looking for loads. Still (one ring) with
/// reduce-motion or LowEndMode, and nothing animates while offline.
class RadarPulse extends StatefulWidget {
  final bool active;
  final Color color;
  final double size;
  const RadarPulse({super.key, required this.active, required this.color, this.size = 56});

  @override
  State<RadarPulse> createState() => _RadarPulseState();
}

class _RadarPulseState extends State<RadarPulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

  void _sync() {
    final run = widget.active && !DsMotion.reduced(context);
    if (run && !_c.isAnimating) _c.repeat();
    if (!run && _c.isAnimating) _c.stop();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(RadarPulse old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: RepaintBoundary(
          child: SizedBox.square(
            dimension: widget.size,
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) => CustomPaint(painter: _PulsePainter(widget.active ? (_c.isAnimating ? _c.value : 0.6) : null, widget.color)),
            ),
          ),
        ),
      );
}

class _PulsePainter extends CustomPainter {
  /// 0..1 phase of the outer ring, or null when offline (dot only).
  final double? t;
  final Color color;
  _PulsePainter(this.t, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    canvas.drawCircle(c, r * 0.22, Paint()..color = color.withValues(alpha: t == null ? 0.5 : 1));
    final phase = t;
    if (phase == null) return;
    for (final p in [phase, (phase + 0.5) % 1]) {
      canvas.drawCircle(c, r * (0.25 + 0.75 * p), Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color.withValues(alpha: (1 - p) * 0.8));
    }
  }

  @override
  bool shouldRepaint(_PulsePainter old) => old.t != t || old.color != color;
}

/// Today's earnings against the driver's own goal, as a ring. Without a goal: the amount and "Set a goal".
class EarningsRing extends StatelessWidget {
  final num todayRupees;
  final int? goalRupees;
  final VoidCallback onSetGoal;
  final Color color;
  final Color track;
  const EarningsRing({super.key, required this.todayRupees, required this.goalRupees, required this.onSetGoal, required this.color, required this.track});

  @override
  Widget build(BuildContext context) {
    final share = goalShare(todayRupees, goalRupees);
    final label = goalRupees == null
        ? trf(context, 'd3TodayNoGoal', {'amount': formatRupees(todayRupees)})
        : trf(context, 'd3TodayOfGoal', {'amount': formatRupees(todayRupees), 'goal': formatRupees(goalRupees!)});
    return Semantics(
      label: label,
      button: true,
      excludeSemantics: true,
      child: InkWell(
        key: const ValueKey('d3Ring'),
        customBorder: const CircleBorder(),
        onTap: onSetGoal,
        child: SizedBox.square(
          dimension: 112,
          child: CustomPaint(
            painter: _RingPainter(share, color, track),
            child: Padding(
              padding: const EdgeInsets.all(DsSpace.s4),
              child: FittedBox(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(formatRupees(todayRupees), style: DsType.title.copyWith(color: color)),
                  Text(goalRupees == null ? tr(context, 'd3SetGoal') : '${(share * 100).round()}%', style: DsType.caption.copyWith(color: color)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double share;
  final Color color;
  final Color track;
  _RingPainter(this.share, this.color, this.track);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final ring = rect.deflate(5);
    canvas.drawArc(ring, 0, math.pi * 2, false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..color = track);
    if (share > 0) {
      canvas.drawArc(ring, -math.pi / 2, math.pi * 2 * share, false, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round
        ..color = color);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.share != share || old.color != color || old.track != track;
}

/// Papers of the driver's trucks: all good, some running out, or some expired (tap opens the vehicles).
class PaperHealthCard extends StatelessWidget {
  final PaperHealth health;
  final VoidCallback onOpen;
  const PaperHealthCard({super.key, required this.health, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final (icon, color, text) = health.expired > 0
        ? (Icons.error_outline_rounded, c.error, trf(context, 'd3PapersExpired', {'n': health.expired}))
        : health.expiring > 0
            ? (Icons.schedule_rounded, c.warning, trf(context, 'd3PapersSoon', {'n': health.expiring}))
            : (Icons.verified_rounded, c.success, tr(context, 'd3PapersOk'));
    return AppCard(
      key: const ValueKey('d3Papers'),
      onTap: onOpen,
      child: Row(children: [
        Icon(icon, color: color),
        const SizedBox(width: DsSpace.s3),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr(context, 'd3Papers'), style: DsType.subtitle.copyWith(color: c.textStrong)),
            Text(text, style: DsType.bodySmall.copyWith(color: c.textMuted)),
          ]),
        ),
        const Icon(Icons.chevron_right_rounded),
      ]),
    );
  }
}

/// Level (from delivered trips) with progress to the next one, and the delivery streak.
class LevelStreakCard extends StatelessWidget {
  final int delivered;
  final int streak;
  const LevelStreakCard({super.key, required this.delivered, required this.streak});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final level = DriverLevel.of(delivered);
    final next = level.next;
    return AppCard(
      key: const ValueKey('d3Level'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: DsSpace.s3, runSpacing: DsSpace.s1, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(tr(context, 'd3Level_${level.name}'), style: DsType.title.copyWith(color: c.textStrong)),
          if (streak > 0)
            Text.rich(
              key: const ValueKey('d3Streak'),
              TextSpan(children: [
                WidgetSpan(alignment: PlaceholderAlignment.middle, child: Icon(Icons.local_fire_department_rounded, color: c.warning, size: 20)),
                TextSpan(text: ' ${trf(context, 'd3Streak', {'n': streak})}'),
              ]),
              style: DsType.label.copyWith(color: c.text),
            ),
        ]),
        const SizedBox(height: DsSpace.s2),
        Semantics(
          label: next == null ? tr(context, 'd3LevelTop') : trf(context, 'd3LevelNext', {'n': next.from - delivered, 'level': tr(context, 'd3Level_${next.name}')}),
          child: ExcludeSemantics(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              ClipRRect(
                borderRadius: DsRadius.all(DsRadius.pill),
                child: LinearProgressIndicator(value: level.progress(delivered), minHeight: 8, color: c.primary, backgroundColor: c.tint),
              ),
              const SizedBox(height: DsSpace.s1),
              Text(
                next == null ? tr(context, 'd3LevelTop') : trf(context, 'd3LevelNext', {'n': next.from - delivered, 'level': tr(context, 'd3Level_${next.name}')}),
                style: DsType.caption.copyWith(color: c.textMuted),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Busiest areas near the driver (DemandFeed). Nothing at all when the feed has no answer.
class DemandStrip extends StatelessWidget {
  final List<DemandCell> cells;
  const DemandStrip({super.key, required this.cells});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    if (cells.isEmpty) return const SizedBox.shrink();
    return Column(key: const ValueKey('d3Demand'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Semantics(header: true, child: Text(tr(context, 'd3Demand'), style: DsType.subtitle.copyWith(color: c.textStrong))),
      const SizedBox(height: DsSpace.s2),
      Wrap(spacing: DsSpace.s2, runSpacing: DsSpace.s2, children: [
        for (final d in cells)
          Chip(
            avatar: Icon(Icons.trending_up_rounded, size: 18, color: c.primary),
            label: Text(trf(context, 'd3DemandCell', {'area': d.area, 'n': d.openLoads})),
          ),
      ]),
    ]);
  }
}

/// A row of big quick-action buttons.
class QuickActions extends StatelessWidget {
  final List<(String key, IconData icon, String label, VoidCallback onTap)> actions;
  const QuickActions({super.key, required this.actions});

  @override
  Widget build(BuildContext context) => Wrap(spacing: DsSpace.s2, runSpacing: DsSpace.s2, children: [
        for (final (k, icon, label, onTap) in actions) AppButton(key: ValueKey(k), label: label, icon: icon, kind: AppButtonKind.secondary, onPressed: onTap),
      ]);
}
