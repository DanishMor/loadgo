import 'package:flutter/material.dart';

import '../../core/announcement/announcement.dart';
import '../../core/assistant/sahayak_screen.dart';
import '../../core/constants/logistics.dart';
import '../../core/features/features.dart';
import '../../core/l10n/l10n.dart';
import '../../core/l10n/language_widgets.dart';
import '../../core/models/booking.dart';
import '../../core/models/load.dart';
import '../../core/notifications/notifications_screen.dart';
import '../../core/pilot/payment_nudge_card.dart';
import '../../core/pilot/waitlist.dart';
import '../../core/services/auth_helpers.dart' show maskPhone;
import '../../core/services/backend.dart';
import '../../core/services/booking_service.dart';
import '../../core/services/features_service.dart';
import '../../core/services/load_service.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/ds/app_button.dart';
import '../../core/widgets/ds/route_ribbon.dart';
import '../../core/widgets/ds/status_badge.dart';
import '../../core/widgets/live_stream.dart';
import '../../core/widgets/logistics_labels.dart';
import '../../core/widgets/role_tour_card.dart';
import 'booking_wizard_model.dart';

/// A route the customer booked before, shown as a chip on the new home.
class RecentRoute {
  final String pickup;
  final String drop;
  const RecentRoute(this.pickup, this.drop);

  /// The newest distinct routes of [loads] (newest first), at most [max].
  static List<RecentRoute> from(Iterable<Load> loads, {int max = 4}) {
    final seen = <String>{};
    final out = <RecentRoute>[];
    for (final l in loads) {
      final key = '${l.pickup.trim().toLowerCase()}|${l.drop.trim().toLowerCase()}';
      if (l.pickup.trim().length < 2 || l.drop.trim().length < 2 || !seen.add(key)) continue;
      out.add(RecentRoute(l.pickup.trim(), l.drop.trim()));
      if (out.length >= max) break;
    }
    return out;
  }
}

/// U18: the new customer home. One big way to book, the three modes in a line each, what is happening now (a trip, or
/// loads waiting for a driver), the recent routes, the trust points, and the rest of the older tools under "More".
class CustomerHomeV2 extends StatelessWidget {
  final VoidCallback onBook;
  final void Function(WizardDraft draft) onBookFrom;
  final ValueChanged<String> onOpenBooking;
  final ValueChanged<String> onOpenLoad;
  final VoidCallback onOpenTrips;
  final List<Widget> more;

  /// Tests give the data instead of the live streams.
  final Stream<List<Booking>> Function()? bookings;
  final Stream<List<Load>> Function()? loads;
  final SahayakActions? sahayak;

  const CustomerHomeV2({
    super.key,
    required this.onBook,
    required this.onBookFrom,
    required this.onOpenBooking,
    required this.onOpenLoad,
    required this.onOpenTrips,
    this.more = const [],
    this.bookings,
    this.loads,
    this.sahayak,
  });

  Widget _modeLine(BuildContext context, IconData icon, String title, String hint) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DsSpace.s1),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 20, color: DsHero.on),
        const SizedBox(width: DsSpace.s3),
        Expanded(
          child: Text.rich(TextSpan(children: [
            TextSpan(text: '$title  ', style: DsType.label.copyWith(color: DsHero.on)),
            TextSpan(text: hint, style: DsType.bodySmall.copyWith(color: DsHero.on.withValues(alpha: 0.85))),
          ])),
        ),
      ]),
    );
  }

  Widget _trust(BuildContext context, IconData icon, String key) {
    final c = context.ds;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DsSpace.s1),
      child: Row(children: [
        Icon(icon, size: 20, color: c.success),
        const SizedBox(width: DsSpace.s3),
        Expanded(child: Text(tr(context, key), style: DsType.bodySmall.copyWith(color: c.text))),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final phone = Backend.currentUser?.phoneNumber ?? '';
    final who = phone.isNotEmpty ? maskPhone(phone) : tr(context, 'customer');
    final bidOn = FeaturesService.isOn(FeatureKey.dispatchV2);
    return SafeArea(
      child: ListView(padding: const EdgeInsets.all(DsSpace.gutter), children: [
        Row(children: [
          CircleAvatar(radius: 24, backgroundColor: c.tint, child: Icon(Icons.person_rounded, color: c.primary)),
          const SizedBox(width: DsSpace.s3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr(context, 'welcomeBack'), style: DsType.bodySmall.copyWith(color: c.textMuted)),
              Text(who, maxLines: 1, overflow: TextOverflow.ellipsis, style: DsType.title.copyWith(color: c.textStrong)),
            ]),
          ),
          IconButton(tooltip: tr(context, 'language'), onPressed: () => showLanguageSelector(context), icon: const Icon(Icons.language_rounded)),
          if (sahayak != null) SahayakButton(role: 'customer', actions: sahayak!),
          NotificationBell(onOpenBooking: onOpenBooking),
        ]),
        const SizedBox(height: DsSpace.s4),
        const AnnouncementBanner(role: 'customer'),
        const WaitlistOpenCard(),
        const PaymentNudgeCard(target: 'customer'),
        const RoleTourCard(role: RoleTour.customer),
        // The one big action.
        Container(
          key: const ValueKey('homeHero'),
          padding: const EdgeInsets.all(DsSpace.s5),
          decoration: BoxDecoration(gradient: const LinearGradient(colors: DsHero.colors, begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: DsRadius.all(DsRadius.xl)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr(context, 'hvBookBig'), style: DsType.headline.copyWith(color: DsHero.on)),
            const SizedBox(height: DsSpace.s1),
            Text(tr(context, 'hvHeroSub'), style: DsType.bodySmall.copyWith(color: DsHero.on.withValues(alpha: 0.85))),
            const SizedBox(height: DsSpace.s4),
            _modeLine(context, Icons.bolt_rounded, tr(context, 'wzModeInstant'), tr(context, 'wzModeInstantHint')),
            if (bidOn) _modeLine(context, Icons.gavel_rounded, tr(context, 'wzModeBid'), tr(context, 'wzModeBidHint')),
            _modeLine(context, Icons.event_rounded, tr(context, 'wzModeSchedule'), tr(context, 'wzModeScheduleHint')),
            const SizedBox(height: DsSpace.s4),
            AppButton(key: const ValueKey('homeBook'), label: tr(context, 'hvBookBig'), big: true, icon: Icons.local_shipping_rounded, onPressed: onBook),
          ]),
        ),
        const SizedBox(height: DsSpace.s4),
        // What is happening now.
        LiveStream<List<Booking>>(
          compact: true,
          stream: bookings ?? () => BookingService.watchForCustomer(),
          builder: (context, list) {
            final active = [for (final b in list) if (b.status != BookingStatus.delivered && b.status != BookingStatus.cancelled) b];
            if (active.isEmpty) return const SizedBox.shrink();
            final b = active.first;
            return Padding(
              padding: const EdgeInsets.only(bottom: DsSpace.s3),
              child: AppCard(
                key: const ValueKey('homeActiveTrip'),
                onTap: () => onOpenBooking(b.id),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Expanded(child: Text(tr(context, 'hvTrip'), style: DsType.title.copyWith(color: c.textStrong))),
                    StatusBadge(label: bookingStatusLabel(context, b.status), tone: StatusTone.progress),
                  ]),
                  const SizedBox(height: DsSpace.s3),
                  RouteRibbon(from: b.pickup, to: b.drop),
                  const SizedBox(height: DsSpace.s3),
                  AppButton(key: const ValueKey('homeOpenTrip'), label: tr(context, 'hvOpen'), kind: AppButtonKind.secondary, onPressed: () => onOpenBooking(b.id)),
                ]),
              ),
            );
          },
        ),
        LiveStream<List<Load>>(
          compact: true,
          stream: loads ?? LoadService.watchMine,
          builder: (context, list) {
            final waiting = [for (final l in list) if (l.isOpen) l];
            final recent = RecentRoute.from(list);
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (waiting.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: DsSpace.s3),
                  child: AppCard(
                    key: const ValueKey('homeWaiting'),
                    onTap: () => onOpenLoad(waiting.first.id),
                    child: Row(children: [
                      Icon(Icons.hourglass_top_rounded, color: c.warning),
                      const SizedBox(width: DsSpace.s3),
                      Expanded(child: Text(trf(context, 'hvWaitingLoads', {'n': waiting.length}), style: DsType.subtitle.copyWith(color: c.textStrong))),
                      TextButton(onPressed: () => onOpenLoad(waiting.first.id), child: Text(tr(context, 'hvOpen'))),
                    ]),
                  ),
                ),
              if (recent.isNotEmpty) ...[
                Text(tr(context, 'wzRecent'), style: DsType.label.copyWith(color: c.textMuted)),
                const SizedBox(height: DsSpace.s2),
                Wrap(spacing: DsSpace.s2, runSpacing: DsSpace.s2, children: [
                  for (final r in recent)
                    ActionChip(
                      key: ValueKey('recent_${r.pickup}_${r.drop}'),
                      avatar: const Icon(Icons.history_rounded, size: 18),
                      label: Text('${r.pickup} → ${r.drop}'),
                      onPressed: () => onBookFrom(WizardDraft(pickup: r.pickup, drop: r.drop, step: 1)),
                    ),
                ]),
                const SizedBox(height: DsSpace.s4),
              ],
            ]);
          },
        ),
        // Trust strip.
        Container(
          key: const ValueKey('homeTrust'),
          padding: const EdgeInsets.all(DsSpace.s4),
          decoration: BoxDecoration(color: c.successBg, borderRadius: DsRadius.all(DsRadius.lg)),
          child: Column(children: [
            _trust(context, Icons.verified_rounded, 'hvTrust1'),
            _trust(context, Icons.password_rounded, 'hvTrust2'),
            _trust(context, Icons.phone_disabled_rounded, 'hvTrust3'),
          ]),
        ),
        if (more.isNotEmpty) ...[
          const SizedBox(height: DsSpace.s5),
          Semantics(header: true, child: Text(tr(context, 'hvMore'), style: DsType.title.copyWith(color: c.textStrong))),
          const SizedBox(height: DsSpace.s2),
          ...more,
        ],
        const SizedBox(height: DsSpace.s4),
        Align(alignment: AlignmentDirectional.centerStart, child: TextButton(key: const ValueKey('homeAllTrips'), onPressed: onOpenTrips, child: Text(tr(context, 'hvTabTrips')))),
      ]),
    );
  }
}
