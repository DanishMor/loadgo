import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../constants/logistics.dart';
import '../l10n/l10n.dart';
import '../models/booking.dart';
import '../widgets/common.dart';
import '../widgets/live_stream.dart';
import '../widgets/logistics_labels.dart';
import 'trip_history.dart';

/// Trip history of either role with status, date and vehicle filters and a
/// CSV share. [bookings] is the role's own stream; [onOpen] opens a trip.
class TripHistoryScreen extends StatefulWidget {
  final StreamFactory<List<Booking>> bookings;
  final ValueChanged<String> onOpen;

  /// Shares the CSV text. Default: the system share sheet.
  final Future<void> Function(String csv, String subject)? share;

  /// Asks for a date range. Default: the Material range picker.
  final Future<DateTimeRange?> Function(BuildContext context, DateTimeRange? current)? pickRange;

  const TripHistoryScreen({super.key, required this.bookings, required this.onOpen, this.share, this.pickRange});

  @override
  State<TripHistoryScreen> createState() => _TripHistoryScreenState();
}

class _TripHistoryScreenState extends State<TripHistoryScreen> {
  TripHistoryFilter _filter = const TripHistoryFilter();

  String _statusKey(HistoryStatus s) => switch (s) {
        HistoryStatus.delivered => 'ehDelivered',
        HistoryStatus.cancelled => 'ehCancelled',
        HistoryStatus.active => 'ehActive',
      };

  void _toggleStatus(HistoryStatus s) {
    final next = {..._filter.statuses};
    if (!next.add(s)) next.remove(s);
    setState(() => _filter = _filter.copyWith(statuses: next));
  }

  void _toggleVehicle(String v) {
    final next = {..._filter.vehicles};
    if (!next.add(v)) next.remove(v);
    setState(() => _filter = _filter.copyWith(vehicles: next));
  }

  Future<void> _pickRange() async {
    final f = _filter;
    final current = f.from != null && f.to != null ? DateTimeRange(start: f.from!, end: f.to!) : null;
    final picked = await (widget.pickRange ??
        (c, cur) => showDateRangePicker(context: c, firstDate: DateTime(2024), lastDate: DateTime.now().add(const Duration(days: 365)), initialDateRange: cur))(context, current);
    if (picked != null && mounted) setState(() => _filter = _filter.copyWith(from: picked.start, to: picked.end));
  }

  Future<void> _share(List<Booking> shown) async {
    final csv = TripHistoryFilter.toCsv(shown);
    final subject = tr(context, 'ehCsvSubject');
    try {
      if (widget.share != null) {
        await widget.share!(csv, subject);
      } else {
        await SharePlus.instance.share(ShareParams(text: csv, subject: subject));
      }
    } catch (_) {
      if (mounted) showSnack(context, tr(context, 'cannotOpenLink'));
    }
  }

  Widget _filters(List<Booking> all) {
    final vehicles = TripHistoryFilter.vehicleNumbers(all);
    final range = _filter.from != null && _filter.to != null ? '${formatDate(_filter.from)} - ${formatDate(_filter.to)}' : tr(context, 'ehAnyDate');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 8, runSpacing: 4, children: [
        for (final s in HistoryStatus.values)
          FilterChip(
            key: ValueKey('hist_${s.name}'),
            label: Text(tr(context, _statusKey(s))),
            selected: _filter.statuses.contains(s),
            onSelected: (_) => _toggleStatus(s),
          ),
        ActionChip(
          key: const ValueKey('hist_range'),
          avatar: const Icon(Icons.date_range_rounded, size: 18),
          label: Text(range),
          onPressed: _pickRange,
        ),
        if (!_filter.isEmpty)
          ActionChip(
            key: const ValueKey('hist_clear'),
            label: Text(tr(context, 'clear')),
            onPressed: () => setState(() => _filter = const TripHistoryFilter()),
          ),
      ]),
      if (vehicles.length > 1) ...[
        const SizedBox(height: 8),
        Text(tr(context, 'ehVehicles'), style: TextStyle(color: AppColors.muted, fontSize: 12)),
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final v in vehicles)
            FilterChip(
              key: ValueKey('hist_vehicle_$v'),
              label: Text(v),
              selected: _filter.vehicles.contains(v),
              onSelected: (_) => _toggleVehicle(v),
            ),
        ]),
      ],
    ]);
  }

  Widget _card(Booking b) {
    final paise = b.billAmountPaise;
    return AppCard(
      key: ValueKey('hist_${b.id}'),
      onTap: () => widget.onOpen(b.id),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            RouteText(pickup: b.pickup, drop: b.drop, fontSize: 15),
            const SizedBox(height: 4),
            Text('${formatDate(historyDate(b))} · ${bookingStatusLabel(context, b.status)}', style: TextStyle(color: AppColors.muted, fontSize: 13)),
            if (b.vehicleNumber.isNotEmpty) Text(b.vehicleNumber, style: TextStyle(color: AppColors.faint, fontSize: 12)),
          ]),
        ),
        const SizedBox(width: 8),
        Text(
          paise == null ? tr(context, 'budgetNegotiable') : formatPaise(paise),
          style: TextStyle(fontWeight: FontWeight.w800, color: b.status == BookingStatus.cancelled ? AppColors.muted : AppColors.success),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LiveStream<List<Booking>>(
      stream: widget.bookings,
      builder: (context, all) {
        final shown = _filter.apply(all);
        return Scaffold(
          appBar: AppBar(
            title: Text(tr(context, 'ehHistoryTitle')),
            actions: [
              IconButton(
                key: const ValueKey('hist_share'),
                tooltip: tr(context, 'ehShareCsv'),
                onPressed: shown.isEmpty ? null : () => _share(shown),
                icon: const Icon(Icons.ios_share_rounded),
              ),
            ],
          ),
          body: all.isEmpty
              ? EmptyState(icon: Icons.history_rounded, title: tr(context, 'ehNoTrips'))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
                  children: [
                    _filters(all),
                    const SizedBox(height: 12),
                    Text(trf(context, 'ehResults', {'n': shown.length}), key: const ValueKey('hist_count'), style: TextStyle(color: AppColors.muted)),
                    const SizedBox(height: 8),
                    if (shown.isEmpty)
                      EmptyState(
                        icon: Icons.filter_alt_off_outlined,
                        title: tr(context, 'ehNoMatch'),
                        action: TextButton(onPressed: () => setState(() => _filter = const TripHistoryFilter()), child: Text(tr(context, 'clear'))),
                      )
                    else
                      for (final b in shown) ...[_card(b), const SizedBox(height: 10)],
                  ],
                ),
        );
      },
    );
  }
}
