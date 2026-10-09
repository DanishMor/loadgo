import '../core/errors/error_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/analytics/admin_trends.dart';
import '../core/analytics/trip_stats.dart';
import '../core/l10n/l10n.dart';
import '../core/models/booking.dart';
import '../core/services/admin_console_service.dart';
import '../core/widgets/common.dart';

/// Admin > Analytics: bookings per day, GMV record, cancellation rate, top
/// routes, active drivers and pickup cities, for 7 / 30 / 90 days, with a CSV
/// copy. Worked out from the newest 1000 bookings.
class AdminTrendsSection extends StatefulWidget {
  /// Injectable for tests.
  final Future<List<Booking>> Function()? load;
  final DateTime Function()? clock;

  const AdminTrendsSection({super.key, this.load, this.clock});

  @override
  State<AdminTrendsSection> createState() => _AdminTrendsSectionState();
}

class _AdminTrendsSectionState extends State<AdminTrendsSection> {
  late final Future<List<Booking>> _bookings = (widget.load ?? AdminConsoleService.recentBookings)();
  int _days = 30;

  Widget _stat(String label, String value, {Key? key}) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 12, color: AppColors.muted)),
          Text(value, key: key, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        ]),
      );

  /// Vertical bars, one per day; the tallest fills the height.
  Widget _dailyBars(AdminTrends t) {
    final peak = t.daily.fold<int>(0, (m, d) => d.bookings > m ? d.bookings : m);
    return SizedBox(
      height: 90,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (final d in t.daily)
          Expanded(
            child: Tooltip(
              message: '${formatDate(d.day)}: ${d.bookings}',
              child: Container(
                key: ValueKey('bar_${d.day.month}_${d.day.day}'),
                margin: const EdgeInsets.symmetric(horizontal: 0.5),
                height: peak == 0 ? 2 : 2 + 86 * d.bookings / peak,
                color: d.bookings == 0 ? AppColors.border : AppColors.primary,
              ),
            ),
          ),
      ]),
    );
  }

  Widget _hBars(List<(String, int)> rows, {String keyPrefix = 'row'}) {
    final peak = rows.fold<int>(0, (m, r) => r.$2 > m ? r.$2 : m);
    return Column(children: [
      for (final r in rows)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            SizedBox(width: 120, child: Text(r.$1, maxLines: 1, overflow: TextOverflow.ellipsis)),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(widthFactor: peak == 0 ? 0 : r.$2 / peak, child: Container(height: 12, color: AppColors.primary)),
              ),
            ),
            const SizedBox(width: 8),
            Text('${r.$2}', key: ValueKey('${keyPrefix}_${r.$1}'), style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Booking>>(
      future: _bookings,
      builder: (context, snap) {
        if (snap.hasError) return Text(errorText(context, snap.error));
        if (!snap.hasData) return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
        final t = AdminTrends.from(snap.data!, now: (widget.clock ?? DateTime.now)(), days: _days);
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(tr(context, 'adminTrends'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
            TextButton.icon(
              key: const ValueKey('trendsCsv'),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: t.toCsv()));
                if (context.mounted) showSnack(context, tr(context, 'csvCopied'));
              },
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: Text(tr(context, 'txnCopyCsv')),
            ),
          ]),
          SegmentedButton<int>(
            key: const ValueKey('trendRange'),
            segments: [
              ButtonSegment(value: 7, label: Text(tr(context, 'trendRange_7'))),
              ButtonSegment(value: 30, label: Text(tr(context, 'txnPeriod_30'))),
              ButtonSegment(value: 90, label: Text(tr(context, 'txnPeriod_90'))),
            ],
            selected: {_days},
            onSelectionChanged: (v) => setState(() => _days = v.first),
          ),
          const SizedBox(height: 12),
          if (t.bookings == 0)
            Padding(padding: const EdgeInsets.all(12), child: Text(tr(context, 'trendNone'), key: const ValueKey('trendNone'), style: TextStyle(color: AppColors.muted)))
          else ...[
            AppCard(
              child: Column(children: [
                Row(children: [
                  _stat(tr(context, 'trendBookings'), '${t.bookings}', key: const ValueKey('trendBookings')),
                  _stat(tr(context, 'trendCancelRate'), t.cancellationRate == null ? '-' : percentText(t.cancellationRate!), key: const ValueKey('trendCancelRate')),
                  _stat(tr(context, 'trendActiveDrivers'), '${t.activeDrivers}', key: const ValueKey('trendActiveDrivers')),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  _stat(tr(context, 'trendGmv'), formatPaise(t.gmvPaise), key: const ValueKey('trendGmv')),
                  _stat(tr(context, 'trendDelivered'), formatPaise(t.deliveredPaise), key: const ValueKey('trendDeliveredValue')),
                ]),
              ]),
            ),
            const SizedBox(height: 12),
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr(context, 'trendDaily'), style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                _dailyBars(t),
              ]),
            ),
            const SizedBox(height: 12),
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr(context, 'trendTopRoutes'), style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                _hBars([for (final r in t.topRoutes) (r.route, r.count)], keyPrefix: 'route'),
              ]),
            ),
            const SizedBox(height: 12),
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr(context, 'trendCities'), style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                _hBars([for (final c in t.cities) (c.city, c.count)], keyPrefix: 'city'),
              ]),
            ),
          ],
        ]);
      },
    );
  }
}
