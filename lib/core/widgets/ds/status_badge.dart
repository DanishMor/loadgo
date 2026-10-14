import 'package:flutter/material.dart';

import '../../theme/contrast.dart';
import '../../theme/design_tokens.dart';

/// How a status is coloured. Every screen asks [statusToneFor], so the same
/// status has the same colour in a list, a card, the admin and the PDF.
enum StatusTone {
  /// Nothing to act on: an open post, a closed one, a draft.
  neutral,

  /// Moving along: accepted, on the way, being checked.
  progress,

  /// Needs somebody's attention: pending, waiting for approval, disputed.
  attention,

  /// Done well: delivered, paid, verified, approved.
  success,

  /// Stopped or wrong: cancelled, rejected, failed, blocked.
  danger,
}

const _success = {
  'delivered', 'settled', 'driver_confirmed', 'paid', 'verified', 'approved', 'resolved', 'issued', 'completed', 'done', 'active_ok', 'granted', 'valid', 'online', 'on',
};
const _progress = {
  'accepted', 'driver_arriving', 'loading', 'picked_up', 'in_transit', 'unloading', 'matched', 'requested', 'in_review', 'assigned', 'confirmed', 'inspecting', 'expiring_soon', 'created',
};
const _attention = {
  'pending', 'customer_marked_paid', 'awaiting_approval', 'review', 'disputed', 'superseded', 'on_hold', 'low', 'waiting', 'expiring', 'unpaid', 'partial', 'late', 'delayed', 'new', 'appealed',
};
const _danger = {
  'cancelled', 'canceled', 'rejected', 'failed', 'fraud', 'blocked', 'reversed', 'expired', 'suspended', 'denied', 'frozen', 'overdue', 'sos', 'offline_problem', 'unavailable',
};

/// The tone of a status string (booking, load, payment, LR, payout, KYC, case
/// and ticket states). Unknown words are [StatusTone.neutral].
StatusTone statusToneFor(String? status) {
  final s = (status ?? '').trim().toLowerCase().replaceAll(' ', '_').replaceAll('-', '_');
  if (_danger.contains(s)) return StatusTone.danger;
  if (_success.contains(s)) return StatusTone.success;
  if (_attention.contains(s)) return StatusTone.attention;
  if (_progress.contains(s)) return StatusTone.progress;
  return StatusTone.neutral;
}

/// Text colour, soft background and icon of a [tone] in the theme's mode.
({Color fg, Color bg, IconData icon}) statusStyle(StatusTone tone, Brightness b) {
  final c = DsColors.of(b);
  return switch (tone) {
    StatusTone.success => (fg: c.success, bg: c.successBg, icon: Icons.check_circle_outline_rounded),
    StatusTone.attention => (fg: c.warning, bg: c.warningBg, icon: Icons.schedule_rounded),
    StatusTone.danger => (fg: c.error, bg: c.errorBg, icon: Icons.cancel_outlined),
    StatusTone.progress => (fg: c.primary, bg: c.tint, icon: Icons.local_shipping_outlined),
    StatusTone.neutral => (fg: c.textMuted, bg: c.chip, icon: Icons.circle_outlined),
  };
}

/// A small rounded status label. Colour never carries the meaning alone: the
/// [label] is always shown, and a small icon backs the tone up. Long labels
/// (Tamil, Telugu, big text) wrap instead of overflowing.
class StatusBadge extends StatelessWidget {
  final String label;
  final StatusTone tone;
  final bool showIcon;

  const StatusBadge({super.key, required this.label, required this.tone, this.showIcon = true});

  /// Picks the tone from a status string.
  StatusBadge.forStatus(String? status, {super.key, required this.label, this.showIcon = true}) : tone = statusToneFor(status);

  @override
  Widget build(BuildContext context) {
    final s = statusStyle(tone, Theme.of(context).brightness);
    return Semantics(
      label: label,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
        padding: const EdgeInsets.symmetric(horizontal: DsSpace.s3, vertical: DsSpace.s1),
        decoration: BoxDecoration(color: s.bg, borderRadius: DsRadius.all(DsRadius.pill)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showIcon) ...[ExcludeSemantics(child: Icon(s.icon, size: 14, color: s.fg)), const SizedBox(width: DsSpace.s1)],
            Flexible(child: Text(label, style: DsType.caption.copyWith(color: s.fg, fontWeight: FontWeight.w700))),
          ],
        ),
      ),
    );
  }
}

/// The badge for an old call site that still passes its own [color]: the text
/// is moved to a readable shade of it (4.5:1 on the soft background).
class ColorBadge extends StatelessWidget {
  final String label;
  final Color color;
  const ColorBadge({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final surface = DsColors.of(b).surface;
    final bg = Color.alphaBlend(color.withValues(alpha: 0.14), surface);
    final fg = ensureContrast(color, bg);
    return Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
      padding: const EdgeInsets.symmetric(horizontal: DsSpace.s3, vertical: DsSpace.s1),
      decoration: BoxDecoration(color: bg, borderRadius: DsRadius.all(DsRadius.pill)),
      child: Text(label, style: DsType.caption.copyWith(color: fg, fontWeight: FontWeight.w700)),
    );
  }
}
