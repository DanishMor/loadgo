import 'dart:async';

import 'package:flutter/material.dart';

import '../core/features/features.dart';
import '../core/l10n/l10n.dart';
import '../core/models/booking.dart';
import '../core/services/features_service.dart';
import '../core/services/safety_service.dart';
import '../core/theme/design_tokens.dart';
import '../core/widgets/common.dart';
import '../core/widgets/ds/app_button.dart';

/// What the check-in did, for the screen and for tests.
enum CheckinState { asking, ok, help, escalated }

/// G22: the truck has been standing for a long time on the road ("Are you OK?"). One tap says all is fine; one tap
/// asks for help (an SOS to support, and to the saved contacts when SMS is on); no answer for [window] counts as
/// "no answer" and support is told too. Behind `safetyCheckin` (OFF). It asks once per stop: it is built again
/// (and asks again) only when the next long halt begins.
class SafetyCheckinCard extends StatefulWidget {
  final Booking? booking;
  final Duration window;

  /// Sends the alert; tests replace it. [reason] is `checkin_help` or `checkin_no_answer`.
  final Future<void> Function(Booking? booking, String reason)? send;

  const SafetyCheckinCard({super.key, this.booking, this.window = const Duration(minutes: 10), this.send});

  static bool get enabled => FeaturesService.isOn(FeatureKey.safetyCheckin);

  @override
  State<SafetyCheckinCard> createState() => _SafetyCheckinCardState();
}

class _SafetyCheckinCardState extends State<SafetyCheckinCard> {
  CheckinState _state = CheckinState.asking;
  Timer? _timer;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.window, () {
      if (_state == CheckinState.asking) _escalate(CheckinState.escalated, 'checkin_no_answer');
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _escalate(CheckinState next, String reason) async {
    _timer?.cancel();
    if (mounted) setState(() => _state = next);
    try {
      await (widget.send ?? _defaultSend)(widget.booking, reason);
    } catch (_) {
      // The alert could not be written (no network): the screen says so and the driver can call.
      if (mounted) setState(() => _failed = true);
    }
  }

  static Future<void> _defaultSend(Booking? b, String reason) => SafetyService.sendSos(booking: b, reason: reason);

  void _ok() {
    _timer?.cancel();
    setState(() => _state = CheckinState.ok);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    if (_state == CheckinState.ok) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: AppCard(
          key: const ValueKey('checkinOk'),
          child: Row(children: [
            Icon(Icons.check_circle_outline_rounded, color: c.success),
            const SizedBox(width: 12),
            Expanded(child: Text(tr(context, 'checkinThanks'), style: DsStyle.w700.copyWith(color: AppColors.title))),
          ]),
        ),
      );
    }
    final sent = _state == CheckinState.help || _state == CheckinState.escalated;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        key: const ValueKey('checkinCard'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(sent ? Icons.sos_rounded : Icons.health_and_safety_outlined, color: sent ? c.error : c.warning),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                tr(context, switch (_state) {
                  CheckinState.help => 'checkinHelpSent',
                  CheckinState.escalated => 'checkinNoAnswerSent',
                  _ => 'checkinAsk',
                }),
                style: DsStyle.w700.copyWith(color: AppColors.title),
              ),
            ),
          ]),
          if (_failed) ...[
            const SizedBox(height: 6),
            Text(tr(context, 'checkinNotSent'), key: const ValueKey('checkinNotSent'), style: DsType.caption.copyWith(color: c.error)),
          ],
          if (_state == CheckinState.asking) ...[
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: AppButton(key: const ValueKey('checkinOkButton'), label: tr(context, 'checkinImOk'), icon: Icons.thumb_up_alt_outlined, kind: AppButtonKind.secondary, onPressed: _ok)),
              const SizedBox(width: 8),
              Expanded(child: AppButton(key: const ValueKey('checkinHelpButton'), label: tr(context, 'checkinNeedHelp'), icon: Icons.sos_rounded, onPressed: () => _escalate(CheckinState.help, 'checkin_help'))),
            ]),
          ],
        ]),
      ),
    );
  }
}
