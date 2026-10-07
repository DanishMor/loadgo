import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../l10n/l10n.dart';
import '../permissions/permission_rationale.dart';
import '../widgets/common.dart';

/// Why [VoiceInput.listenOnce] gave no text.
enum VoiceIssue { unavailable, denied, nothingHeard }

class VoiceResult {
  final String? text;
  final VoiceIssue? issue;
  const VoiceResult.text(String this.text) : issue = null;
  const VoiceResult.issue(VoiceIssue this.issue) : text = null;
}

/// The speech engine behind the mic buttons (replaced by a fake in tests).
abstract class SpeechEngine {
  /// True when recognition can start; [onDenied] is called when the cause is
  /// a refused microphone permission.
  Future<bool> init({required void Function() onDenied});
  Future<String?> listen({required String localeId});
  Future<void> stop();
}

class SpeechToTextEngine implements SpeechEngine {
  final SpeechToText _stt = SpeechToText();

  @override
  Future<bool> init({required void Function() onDenied}) async {
    try {
      final ok = await _stt.initialize(onError: (e) {
        if (e.errorMsg.contains('permission')) onDenied();
      });
      if (!ok && !await _stt.hasPermission) onDenied();
      return ok;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> listen({required String localeId}) async {
    String words = '';
    final done = _DoneSignal();
    await _stt.listen(
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        localeId: localeId,
        listenFor: const Duration(seconds: 10),
        pauseFor: const Duration(seconds: 3),
      ),
      onResult: (r) {
        words = r.recognizedWords;
        if (r.finalResult) done.complete();
      },
    );
    await done.wait(const Duration(seconds: 12));
    await _stt.stop();
    return words.trim().isEmpty ? null : words.trim();
  }

  @override
  Future<void> stop() => _stt.stop();
}

class _DoneSignal {
  bool _done = false;
  void complete() => _done = true;

  Future<void> wait(Duration max) async {
    final end = DateTime.now().add(max);
    while (!_done && DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
  }
}

/// One-shot voice input in the app language.
class VoiceInput {
  VoiceInput._();

  static SpeechEngine engine = SpeechToTextEngine();

  /// Speech locale for an app language (Hinglish and English use en_IN).
  static String localeFor(AppLanguage l) => switch (l) {
        AppLanguage.hindi => 'hi_IN',
        AppLanguage.kannada => 'kn_IN',
        AppLanguage.tamil => 'ta_IN',
        AppLanguage.telugu => 'te_IN',
        AppLanguage.marathi => 'mr_IN',
        AppLanguage.gujarati => 'gu_IN',
        AppLanguage.bengali => 'bn_IN',
        AppLanguage.punjabi => 'pa_IN',
        AppLanguage.kashmiri || AppLanguage.urdu => 'ur_IN',
        _ => 'en_IN',
      };

  static Future<VoiceResult> listenOnce({AppLanguage? language}) async {
    var denied = false;
    final ok = await engine.init(onDenied: () => denied = true);
    if (!ok) return VoiceResult.issue(denied ? VoiceIssue.denied : VoiceIssue.unavailable);
    final text = await engine.listen(localeId: localeFor(language ?? languageNotifier.value));
    if (denied) return const VoiceResult.issue(VoiceIssue.denied);
    return text == null ? const VoiceResult.issue(VoiceIssue.nothingHeard) : VoiceResult.text(text);
  }
}

/// Mic button: listens once and hands the text to [onText]. Problems show a
/// plain message (typing always still works).
class VoiceMicButton extends StatefulWidget {
  final ValueChanged<String> onText;

  /// A filled (more visible) button, used on the Simple Mode screens.
  final bool filled;

  const VoiceMicButton({super.key, required this.onText, this.filled = false});

  @override
  State<VoiceMicButton> createState() => _VoiceMicButtonState();
}

class _VoiceMicButtonState extends State<VoiceMicButton> {
  bool _listening = false;

  Future<void> _start() async {
    if (!await PermissionRationale.ask(context, RationaleKind.microphone) || !mounted) return;
    setState(() => _listening = true);
    showSnack(context, tr(context, 'voiceListening'));
    final r = await VoiceInput.listenOnce();
    if (!mounted) return;
    setState(() => _listening = false);
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    if (r.text != null) {
      widget.onText(r.text!);
    } else if (r.issue == VoiceIssue.denied) {
      showSnack(context, tr(context, 'voiceDenied'));
    } else if (r.issue == VoiceIssue.unavailable) {
      showSnack(context, tr(context, 'voiceUnavailable'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final icon = Icon(_listening ? Icons.mic : Icons.mic_none_rounded);
    final tip = tr(context, 'voiceSpeak');
    return widget.filled
        ? IconButton.filled(key: const ValueKey('voiceMic'), tooltip: tip, onPressed: _listening ? null : _start, icon: icon)
        : IconButton(key: const ValueKey('voiceMic'), tooltip: tip, onPressed: _listening ? null : _start, icon: icon);
  }
}
