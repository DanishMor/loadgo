import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/l10n.dart';
import '../../theme/design_tokens.dart';
import 'haptics.dart';

/// Quiet hours for sounds: from [startMinute] to [endMinute] (minutes after midnight) no
/// sound plays; a vibration still does. The default is 22:00 to 06:00. When start equals
/// end the quiet time is empty.
class QuietHours {
  final int startMinute;
  final int endMinute;
  const QuietHours({this.startMinute = 22 * 60, this.endMinute = 6 * 60});

  static const defaults = QuietHours();

  bool contains(DateTime t) {
    final m = t.hour * 60 + t.minute;
    if (startMinute == endMinute) return false;
    return startMinute < endMinute ? (m >= startMinute && m < endMinute) : (m >= startMinute || m < endMinute);
  }

  static const _kStart = 'quiet_start', _kEnd = 'quiet_end';

  static Future<QuietHours> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getInt(_kStart), e = p.getInt(_kEnd);
      if (s == null || e == null || s < 0 || s >= 1440 || e < 0 || e >= 1440) return defaults;
      return QuietHours(startMinute: s, endMinute: e);
    } catch (_) {
      return defaults;
    }
  }

  Future<void> save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(_kStart, startMinute);
      await p.setInt(_kEnd, endMinute);
    } catch (_) {}
  }
}

/// What an alert does: a vibration and, when allowed, one short sound. The sound is the
/// phone's own alert sound (no audio file or plugin is added to the app). It is skipped in
/// quiet hours, in Low-end mode, and when the person turned touch feedback off.
class FeedbackKit {
  FeedbackKit._();

  static QuietHours quiet = QuietHours.defaults;

  /// Tests replace these.
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;
  @visibleForTesting
  static Future<void> Function() soundPlayer = () => SystemSound.play(SystemSoundType.alert);

  static bool soundAllowed() => !DsMotion.lowEnd && Haptics.enabled.value && !quiet.contains(clock());

  /// A new load or bid arrived: vibrate, and a sound if allowed. Never throws.
  static Future<bool> alert() async {
    Haptics.warning();
    if (!soundAllowed()) return false;
    try {
      await soundPlayer();
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// A banner that slides in at the top while the app is open, for "new load near you" or
/// "a new bid". It goes by itself after [seconds], on a tap runs [onTap], and never covers
/// the whole screen. With reduced motion it just appears.
OverlayEntry? showHeadsUp(BuildContext context, {required String title, String? body, VoidCallback? onTap, int seconds = 6}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return null;
  late OverlayEntry entry;
  var gone = false;
  void remove() {
    if (gone) return;
    gone = true;
    entry.remove();
  }

  entry = OverlayEntry(builder: (ctx) => HeadsUpBanner(title: title, body: body, onTap: onTap == null ? null : () {
        remove();
        onTap();
      }, onDismiss: remove));
  overlay.insert(entry);
  Future<void>.delayed(Duration(seconds: seconds), remove);
  return entry;
}

class HeadsUpBanner extends StatelessWidget {
  final String title;
  final String? body;
  final VoidCallback? onTap;
  final VoidCallback onDismiss;
  const HeadsUpBanner({super.key, required this.title, this.body, this.onTap, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.all(DsSpace.s3),
          child: Semantics(
            liveRegion: true,
            container: true,
            label: body == null ? title : '$title. $body',
            excludeSemantics: true,
            onTap: onTap,
            onDismiss: onDismiss,
            child: Material(
              elevation: DsElevation.dialog,
              color: c.primary,
              borderRadius: DsRadius.all(DsRadius.lg),
              child: InkWell(
                borderRadius: DsRadius.all(DsRadius.lg),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.all(DsSpace.s4),
                  child: Row(children: [
                    Icon(Icons.local_shipping_rounded, color: c.onPrimary),
                    const SizedBox(width: DsSpace.s3),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: DsType.subtitle.copyWith(color: c.onPrimary)),
                        if (body != null) Text(body!, maxLines: 2, overflow: TextOverflow.ellipsis, style: DsType.bodySmall.copyWith(color: c.onPrimary)),
                      ]),
                    ),
                    IconButton(tooltip: tr(context, 'uxDismiss'), icon: Icon(Icons.close_rounded, color: c.onPrimary), onPressed: onDismiss),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
