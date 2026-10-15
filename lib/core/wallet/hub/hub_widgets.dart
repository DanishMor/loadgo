import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../security/app_lock.dart';
import '../../security/secure_screen.dart';
import '../../theme/design_tokens.dart';
import '../../widgets/common.dart';
import '../../widgets/error_boundary.dart';
import '../../widgets/live_stream.dart';
import '../../widgets/ds/app_top_bar.dart';
import '../../widgets/ds/money_text.dart';
import '../../widgets/ds/skeleton.dart';
import 'hub_models.dart';

/// What a hub body needs to know: whether amounts are hidden and which load
/// round it is (changes on pull to refresh, so streams re-subscribe).
class HubView {
  final bool hidden;
  final int round;

  /// Starts a new round (streams re-subscribe). Used by pull to refresh.
  final VoidCallback reload;
  const HubView(this.hidden, this.round, this.reload);

  /// For RefreshIndicator: reload, then wait a moment so the spinner is seen.
  Future<void> refresh() async {
    reload();
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
}

/// The frame of an earnings and accounts screen (F9): top bar with the role
/// line and the hide-amounts eye (amounts start hidden), the offline banner,
/// the error boundary, and a private-screen guard (no screenshots when on).
class HubFrame extends StatefulWidget {
  final String role;
  final Widget Function(BuildContext context, HubView view) builder;
  const HubFrame({super.key, required this.role, required this.builder});

  @override
  State<HubFrame> createState() => _HubFrameState();
}

class _HubFrameState extends State<HubFrame> {
  bool _hidden = true;
  int _round = 0;

  @override
  Widget build(BuildContext context) {
    return SecureScope(
      child: AppLockGate(
        child: Scaffold(
        appBar: AppTopBar(
          title: tr(context, 'hubTitle'),
          role: widget.role,
          actions: [MoneyVisibilityButton(hidden: _hidden, onChanged: (v) => setState(() => _hidden = v))],
        ),
        body: SafeArea(
          child: Column(children: [
            const OfflineBanner(),
            Expanded(
              child: ErrorBoundary(
                onRetry: () => setState(() => _round++),
                builder: (context) => widget.builder(context, HubView(_hidden, _round, () => setState(() => _round++))),
              ),
            ),
          ]),
        ),
      ),
    ));
  }
}

/// A scrolling column with pull to refresh. [onRefresh] re-subscribes.
class HubList extends StatelessWidget {
  final List<Widget> children;
  final Future<void> Function()? onRefresh;
  const HubList({super.key, required this.children, this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(DsSpace.gutter, DsSpace.s3, DsSpace.gutter, DsSpace.s8),
      children: children,
    );
    return onRefresh == null ? list : RefreshIndicator(onRefresh: onRefresh!, child: list);
  }
}

/// The skeleton shown while the first data arrives.
class HubLoading extends StatelessWidget {
  const HubLoading({super.key});

  @override
  Widget build(BuildContext context) => const SkeletonList(count: 3);
}

/// The big card with the main figure.
class HubBalanceCard extends StatelessWidget {
  final String label;
  final int paise;
  final bool hidden;
  final String? caption;
  final Key? valueKey;
  const HubBalanceCard({super.key, required this.label, required this.paise, required this.hidden, this.caption, this.valueKey});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: DsType.caption.copyWith(color: c.textMuted)),
        const SizedBox(height: DsSpace.s1),
        KeyedSubtree(key: valueKey, child: MoneyText(paise, size: MoneySize.display, hidden: hidden)),
        if (caption != null) ...[
          const SizedBox(height: DsSpace.s1),
          Text(caption!, style: DsType.caption.copyWith(color: c.textMuted)),
        ],
      ]),
    );
  }
}

/// A small labelled figure; put several in a [HubFigures].
class HubFigure extends StatelessWidget {
  final String label;
  final int paise;
  final bool hidden;
  final bool signed;
  final Key? valueKey;
  const HubFigure({super.key, required this.label, required this.paise, required this.hidden, this.signed = false, this.valueKey});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: DsType.caption.copyWith(color: c.textMuted)),
      KeyedSubtree(key: valueKey, child: MoneyText(paise, size: MoneySize.body, hidden: hidden, signed: signed)),
    ]);
  }
}

/// Figures side by side; they wrap onto more lines at large text instead of overflowing.
class HubFigures extends StatelessWidget {
  final List<Widget> figures;
  const HubFigures({super.key, required this.figures});

  @override
  Widget build(BuildContext context) => AppCard(
        child: Wrap(spacing: DsSpace.s6, runSpacing: DsSpace.s3, children: figures),
      );
}

/// A section heading.
class HubHeading extends StatelessWidget {
  final String text;
  const HubHeading(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: DsSpace.s5, bottom: DsSpace.s2),
        child: Semantics(header: true, child: Text(text, style: DsType.title.copyWith(color: context.ds.text))),
      );
}

/// Text on the left and an amount on the right. When the text is large or the
/// screen narrow the amount drops under the text instead of overflowing.
class HubSplit extends StatelessWidget {
  final Widget left;
  final Widget right;
  const HubSplit({super.key, required this.left, required this.right});

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    return LayoutBuilder(builder: (context, box) {
      if (scale > 1.3 || box.maxWidth < 260) {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [left, const SizedBox(height: DsSpace.s1), right]);
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: left), const SizedBox(width: DsSpace.s2), right]);
    });
  }
}

/// "Paisa kab milega": the steps money goes through, with counts and amounts.
/// Steps with nothing in them are dimmed but kept, so the road is always visible.
class HubStageList extends StatelessWidget {
  final List<HubStage> stages;
  final bool hidden;
  const HubStageList({super.key, required this.stages, required this.hidden});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return AppCard(
      child: Column(children: [
        for (var i = 0; i < stages.length; i++)
          Padding(
            key: ValueKey('stage_${stages[i].key}'),
            padding: const EdgeInsets.symmetric(vertical: DsSpace.s2),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: stages[i].count > 0 ? c.primary : c.chip,
                child: Text('${i + 1}', style: DsStyle.w700.copyWith(fontSize: 12, color: stages[i].count > 0 ? c.onPrimary : c.textMuted)),
              ),
              const SizedBox(width: DsSpace.s3),
              Expanded(
                child: HubSplit(
                  left: Text(tr(context, stages[i].key), style: DsType.body.copyWith(color: stages[i].count > 0 ? c.text : c.textMuted)),
                  right: MoneyText(stages[i].paise, size: MoneySize.small, hidden: hidden),
                ),
              ),
            ]),
          ),
      ]),
    );
  }
}

/// A ledger-like row: title, optional subtitle and an amount.
class HubRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final int paise;
  final bool hidden;
  final bool signed;
  const HubRow({super.key, required this.title, this.subtitle, required this.paise, required this.hidden, this.signed = true});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DsSpace.s2),
      child: HubSplit(
        left: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: DsType.body.copyWith(color: c.text)),
          if (subtitle != null) Text(subtitle!, style: DsType.caption.copyWith(color: c.textMuted)),
        ]),
        right: MoneyText(paise, size: MoneySize.small, hidden: hidden, signed: signed),
      ),
    );
  }
}

/// The small grey note that no real money moves yet.
class HubRecordsOnly extends StatelessWidget {
  const HubRecordsOnly({super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: DsSpace.s4),
        child: Text(tr(context, 'recordsOnly'), style: DsType.caption.copyWith(color: context.ds.textMuted)),
      );
}
