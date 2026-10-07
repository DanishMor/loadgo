import 'package:flutter/material.dart';

import '../core/analytics/spending_summary.dart';
import '../core/l10n/l10n.dart';
import '../core/models/booking.dart';
import '../core/services/booking_service.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';
import '../core/widgets/mini_bars.dart';

/// "04/2026" for a `yyyy-MM` key (the same in every language).
String monthLabel(String key) {
  final p = key.split('-');
  return '${p[1]}/${p[0]}';
}

/// Profile > My spending: what the customer paid per month, cargo and route.
class SpendingScreen extends StatefulWidget {
  final StreamFactory<List<Booking>> bookings;
  final DateTime Function() now;

  const SpendingScreen({super.key, this.bookings = BookingService.watchForCustomer, this.now = DateTime.now});

  @override
  State<SpendingScreen> createState() => _SpendingScreenState();
}

class _SpendingScreenState extends State<SpendingScreen> {
  String? _month;

  Widget _lines(List<SpendLine> lines, String keyPrefix) {
    final peak = lines.fold<int>(0, (m, l) => l.paise > m ? l.paise : m);
    return Column(children: [
      for (var i = 0; i < lines.length; i++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(lines[i].label, overflow: TextOverflow.ellipsis)),
              Text(formatPaise(lines[i].paise), key: ValueKey('${keyPrefix}_$i'), style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 3),
            LinearProgressIndicator(value: peak == 0 ? 0 : lines[i].paise / peak, minHeight: 4, color: AppColors.primary, backgroundColor: AppColors.border),
            Text(trf(context, 'ehResults', {'n': lines[i].trips}), style: TextStyle(fontSize: 11, color: AppColors.faint)),
          ]),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'ehSpendTitle'))),
      body: LiveStream<List<Booking>>(
        stream: widget.bookings,
        builder: (context, list) {
          final s = SpendingSummary.from(list, widget.now());
          final key = _month ?? s.months.last.key;
          final m = s.forMonth(key);
          final selected = s.months.indexWhere((e) => e.key == key);
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
            children: [
              Text(tr(context, 'ehLastMonths'), style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.title)),
              const SizedBox(height: 10),
              MiniBars(
                keyPrefix: 'spendBar',
                highlight: selected < 0 ? null : selected,
                bars: [for (final e in s.months) MiniBar(monthLabel(e.key).substring(0, 2), e.paise, '${monthLabel(e.key)}: ${formatPaise(e.paise)}')],
              ),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 4, children: [
                for (final e in s.months)
                  ChoiceChip(
                    key: ValueKey('spendMonth_${e.key}'),
                    label: Text(monthLabel(e.key)),
                    selected: e.key == key,
                    onSelected: (_) => setState(() => _month = e.key),
                  ),
              ]),
              const SizedBox(height: 16),
              AppCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(trf(context, 'ehSpentIn', {'month': monthLabel(key)}), style: TextStyle(color: AppColors.muted)),
                  const SizedBox(height: 4),
                  Text(formatPaise(m.totalPaise), key: const ValueKey('spendTotal'), style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.title)),
                  Text(trf(context, 'ehResults', {'n': m.trips}), style: TextStyle(color: AppColors.muted)),
                ]),
              ),
              const SizedBox(height: 16),
              if (m.isEmpty)
                EmptyState(icon: Icons.receipt_long_outlined, title: tr(context, 'ehNoSpend'))
              else ...[
                Text(tr(context, 'ehByCargo'), style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.title)),
                const SizedBox(height: 6),
                _lines(m.byCargo, 'spendCargo'),
                const SizedBox(height: 16),
                Text(tr(context, 'ehByRoute'), style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.title)),
                const SizedBox(height: 6),
                _lines(m.byRoute, 'spendRoute'),
              ],
            ],
          );
        },
      ),
    );
  }
}
