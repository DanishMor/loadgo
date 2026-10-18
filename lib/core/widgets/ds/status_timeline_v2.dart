import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../theme/contrast.dart';
import '../../theme/design_tokens.dart';

/// One step of a trip: its words and, when it has happened, the time as text.
class TimelineStepV2 {
  final String label;
  final String? time;
  const TimelineStepV2(this.label, {this.time});
}

/// Steps one under the other joined by a line. Steps before [current] are done (tick),
/// [current] is the one in progress (filled dot), the rest wait (empty ring). The state
/// is also said in words for screen readers, so colour is never the only signal.
class StatusTimelineV2 extends StatelessWidget {
  final List<TimelineStepV2> steps;
  final int current;
  const StatusTimelineV2({super.key, required this.steps, required this.current});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final done = ensureContrast(c.success, c.surface);
    return Column(children: [
      for (var i = 0; i < steps.length; i++)
        Semantics(
          container: true,
          label: '${steps[i].label}, ${i < current ? tr(context, 'uxStepDone') : i == current ? tr(context, 'uxStepNow') : tr(context, 'uxStepNext')}${steps[i].time != null ? ', ${steps[i].time}' : ''}',
          excludeSemantics: true,
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(
                width: 28,
                child: Column(children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < current ? done : (i == current ? c.primary : c.surface),
                      border: Border.all(color: i <= current ? (i < current ? done : c.primary) : c.inputBorder, width: 2),
                    ),
                    child: i < current ? Icon(Icons.check_rounded, size: 16, color: c.surface) : null,
                  ),
                  if (i < steps.length - 1) Expanded(child: Container(width: 3, color: i < current ? done : c.border)),
                ]),
              ),
              const SizedBox(width: DsSpace.s3),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: DsSpace.s4),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(steps[i].label, style: (i == current ? DsType.subtitle : DsType.body).copyWith(color: i <= current ? c.textStrong : c.textMuted)),
                    if (steps[i].time != null) Text(steps[i].time!, style: DsType.caption.copyWith(color: c.textMuted)),
                  ]),
                ),
              ),
            ]),
          ),
        ),
    ]);
  }
}
