import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../l10n/l10n.dart';
import '../widgets/common.dart';

/// What opening the microphone gave.
enum MicResult { ok, denied, unavailable }

/// The microphone behind "Test my microphone" (a fake in tests).
abstract class MicProbe {
  /// Opens the microphone; [MicResult.denied] when the person said no.
  Future<MicResult> open();

  /// Sound level 0..1 while open; empty when this phone cannot measure it.
  Stream<double> get levels;

  Future<void> close();
}

class WebRtcMicProbe implements MicProbe {
  MediaStream? _stream;
  final SpeechToText _stt = SpeechToText();
  final _levels = StreamController<double>.broadcast();

  @override
  Stream<double> get levels => _levels.stream;

  @override
  Future<MicResult> open() async {
    try {
      _stream = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': false});
    } catch (e) {
      final s = e.toString().toLowerCase();
      return s.contains('notfound') || s.contains('not found') || s.contains('devices') ? MicResult.unavailable : MicResult.denied;
    }
    // A level meter, when speech recognition is available (its sound level is the meter).
    try {
      if (await _stt.initialize()) {
        await _stt.listen(
          onResult: (_) {},
          onSoundLevelChange: (db) {
            if (!_levels.isClosed) _levels.add(((db + 2) / 12).clamp(0.0, 1.0));
          },
          listenOptions: SpeechListenOptions(partialResults: false, listenMode: ListenMode.confirmation, listenFor: const Duration(seconds: 30)),
        );
      }
    } catch (_) {}
    return MicResult.ok;
  }

  @override
  Future<void> close() async {
    try {
      await _stt.cancel();
    } catch (_) {}
    for (final t in _stream?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      await t.stop();
    }
    await _stream?.dispose();
    _stream = null;
    if (!_levels.isClosed) await _levels.close();
  }
}

/// Builds the probe; replaced in tests.
MicProbe Function() micProbeFactory = WebRtcMicProbe.new;

/// How the test went from the levels heard: nothing, or speech.
class MicVerdict {
  MicVerdict._();

  /// A level at or above this counts as hearing the person.
  static const heardAt = 0.25;

  static bool heard(Iterable<double> levels) => levels.any((l) => l >= heardAt);
}

/// "Test my microphone" (MASTER-6 Task 35): opens the microphone, shows a
/// level bar while the person speaks, and says plainly what to do if nothing
/// is heard. Used before a call and when a call could not start.
class MicTestScreen extends StatefulWidget {
  final MicProbe Function()? probe;
  const MicTestScreen({super.key, this.probe});

  @override
  State<MicTestScreen> createState() => _MicTestScreenState();
}

enum _Stage { idle, opening, listening, denied, unavailable }

class _MicTestScreenState extends State<MicTestScreen> {
  _Stage _stage = _Stage.idle;
  double _level = 0;
  bool _heard = false;
  bool _meter = false;
  MicProbe? _probe;
  StreamSubscription<double>? _sub;

  Future<void> _stop() async {
    await _sub?.cancel();
    _sub = null;
    await _probe?.close();
    _probe = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  Future<void> _start() async {
    await _stop();
    setState(() {
      _stage = _Stage.opening;
      _level = 0;
      _heard = false;
      _meter = false;
    });
    final probe = (widget.probe ?? micProbeFactory)();
    _probe = probe;
    _sub = probe.levels.listen((l) {
      if (!mounted) return;
      setState(() {
        _meter = true;
        _level = l;
        if (l >= MicVerdict.heardAt) _heard = true;
      });
    });
    final r = await probe.open();
    if (!mounted) return;
    setState(() => _stage = switch (r) { MicResult.ok => _Stage.listening, MicResult.denied => _Stage.denied, MicResult.unavailable => _Stage.unavailable });
    if (r != MicResult.ok) await _stop();
  }

  @override
  Widget build(BuildContext context) {
    final listening = _stage == _Stage.listening;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(backgroundColor: AppColors.background, scrolledUnderElevation: 0, title: Text(tr(context, 'mtTitle'), style: const TextStyle(fontWeight: FontWeight.w700))),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(20), children: [
          Text(tr(context, 'mtIntro')),
          const SizedBox(height: 16),
          if (listening) ...[
            Text(tr(context, 'mtSpeak'), key: const ValueKey('mtSpeak'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 8),
            if (_meter) LinearProgressIndicator(key: const ValueKey('mtLevel'), value: _level, minHeight: 14, borderRadius: BorderRadius.circular(7)) else Text(tr(context, 'mtNoMeter'), key: const ValueKey('mtNoMeter'), style: TextStyle(color: AppColors.muted)),
            const SizedBox(height: 8),
            if (_heard) Text(tr(context, 'mtHeard'), key: const ValueKey('mtHeard'), style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.success)),
          ],
          if (_stage == _Stage.denied) Text(tr(context, 'mtDenied'), key: const ValueKey('mtDenied'), style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.warning)),
          if (_stage == _Stage.unavailable) Text(tr(context, 'mtUnavailable'), key: const ValueKey('mtUnavailable'), style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.warning)),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const ValueKey('mtStart'),
            onPressed: _stage == _Stage.opening ? null : _start,
            icon: Icon(listening ? Icons.replay_rounded : Icons.mic_rounded),
            label: Text(tr(context, listening ? 'mtAgain' : 'mtStart')),
          ),
          if (listening && !_heard) Padding(padding: const EdgeInsets.only(top: 12), child: Text(tr(context, 'mtTips'), key: const ValueKey('mtTips'), style: TextStyle(color: AppColors.muted, fontSize: 13))),
        ]),
      ),
    );
  }
}
