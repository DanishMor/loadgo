import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/booking.dart';
import '../permissions/permission_rationale.dart';
import '../services/backend.dart';
import '../widgets/common.dart';
import 'call_controller.dart';
import 'call_models.dart';
import 'call_provider.dart';
import 'call_signaling.dart';
import 'call_webrtc.dart';
import 'mic_test.dart';

/// Builds the media side. Replaced in tests; the real one is WebRTC.
CallProvider Function() callProviderFactory = WebRtcCallProvider.new;

String _endText(BuildContext context, CallEnd? e) => switch (e) {
      CallEnd.noAnswer => '${tr(context, 'pcNoAnswer')}. ${tr(context, 'pcCallNeedsApp')}',
      CallEnd.declined => tr(context, 'pcDeclined'),
      CallEnd.micDenied => tr(context, 'pcMicDenied'),
      CallEnd.unsupported => tr(context, 'pcCallUnsupported'),
      CallEnd.failed => tr(context, 'pcCallFailed'),
      CallEnd.tooMany => tr(context, 'pcTooMany'),
      CallEnd.blocked => trf(context, 'pcBlockedBanner', {'until': '…'}),
      _ => tr(context, 'pcCallEnded'),
    };

/// The call screen for either side: who, what is happening, mute / speaker /
/// end. With [incoming] set it first shows Answer and Decline.
class CallScreen extends StatefulWidget {
  final CallController controller;
  final CallDoc? incoming;
  final String peer;

  /// Opens the chat of the booking: offered when a call could not happen
  /// (MASTER-6 Task 35).
  final VoidCallback? onChat;

  const CallScreen({super.key, required this.controller, this.incoming, this.peer = '', this.onChat});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  StreamSubscription<CallDoc?>? _watch;
  bool _closing = false;

  CallController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
    final inc = widget.incoming;
    if (inc != null) {
      // Caller gave up (or it timed out) before this person answered.
      _watch = CallSignaling.watch(inc.id).listen((d) {
        if (c.phase == CallPhase.idle && (d == null || d.status != CallStatus.ringing)) _close();
      });
    }
  }

  @override
  void dispose() {
    _watch?.cancel();
    c.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
    if ((c.phase == CallPhase.ended || c.phase == CallPhase.failed) && !_closing) {
      final stay = c.phase == CallPhase.failed || (c.endReason != null && _needsHelp(c.endReason!));
      Future.delayed(stay ? const Duration(seconds: 3) : const Duration(milliseconds: 800), _close);
    }
  }

  void _close() {
    if (_closing || !mounted) return;
    _closing = true;
    Navigator.of(context).maybePop();
  }

  /// The call did not happen: say what to do instead.
  static bool _needsHelp(CallEnd e) => const [CallEnd.noAnswer, CallEnd.declined, CallEnd.failed, CallEnd.micDenied, CallEnd.unsupported, CallEnd.tooMany, CallEnd.blocked].contains(e);

  bool get _didNotHappen => (c.phase == CallPhase.ended || c.phase == CallPhase.failed) && (c.phase == CallPhase.failed || (c.endReason != null && _needsHelp(c.endReason!)));

  String _status(BuildContext context) => switch (c.phase) {
        CallPhase.idle => trf(context, 'pcIncoming', {'name': widget.incoming?.callerName ?? widget.peer}),
        CallPhase.preparing => tr(context, 'pcConnecting'),
        CallPhase.ringing => trf(context, 'pcCalling', {'name': c.peerName.isEmpty ? widget.peer : c.peerName}),
        CallPhase.incoming => trf(context, 'pcIncoming', {'name': c.peerName}),
        CallPhase.connecting => tr(context, 'pcConnecting'),
        CallPhase.connected => tr(context, 'pcConnected'),
        CallPhase.ended || CallPhase.failed => _endText(context, c.endReason),
      };

  @override
  Widget build(BuildContext context) {
    final incoming = widget.incoming;
    final waiting = incoming != null && c.phase == CallPhase.idle;
    final live = c.isActive;
    final name = incoming?.callerName.isNotEmpty == true ? incoming!.callerName : (c.peerName.isNotEmpty ? c.peerName : widget.peer);
    return PopScope(
      canPop: !live && !waiting,
      child: Scaffold(
        backgroundColor: const Color(0xFF0B1B33),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, box) => SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: box.maxHeight - 48),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const SizedBox(height: 24),
                  const CircleAvatar(radius: 44, backgroundColor: Color(0xFF1565C0), child: Icon(Icons.person_rounded, size: 52, color: Colors.white)),
                  const SizedBox(height: 20),
                  Text(name, key: const ValueKey('callName'), style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800), textAlign: TextAlign.center),
                  if (incoming != null && incoming.vehicleNumber.isNotEmpty)
                    Padding(padding: const EdgeInsets.only(top: 4), child: Text(incoming.vehicleNumber, style: const TextStyle(color: Colors.white70))),
                  const SizedBox(height: 12),
                  Text(_status(context), key: const ValueKey('callStatus'), style: const TextStyle(color: Colors.white70, fontSize: 16), textAlign: TextAlign.center),
                  const SizedBox(height: 40),
                  if (waiting)
                    Wrap(alignment: WrapAlignment.center, spacing: 32, runSpacing: 20, children: [
                      _round(Icons.call_end_rounded, Colors.red, tr(context, 'pcDecline'), () async {
                        await c.decline(incoming);
                      }, key: const ValueKey('callDecline')),
                      _round(Icons.call_rounded, AppColors.success, tr(context, 'pcAnswer'), () async {
                        if (!await PermissionRationale.ask(context, RationaleKind.callMicrophone)) {
                          await c.decline(incoming);
                          return;
                        }
                        await c.answer(incoming);
                      }, key: const ValueKey('callAnswer')),
                    ])
                  else if (live)
                    Wrap(alignment: WrapAlignment.center, spacing: 24, runSpacing: 20, children: [
                      _round(c.muted ? Icons.mic_off_rounded : Icons.mic_rounded, Colors.white24, tr(context, c.muted ? 'pcUnmute' : 'pcMute'), c.toggleMute, key: const ValueKey('callMute')),
                      _round(Icons.call_end_rounded, Colors.red, tr(context, 'pcEnd'), c.hangUp, key: const ValueKey('callEnd')),
                      _round(c.speaker ? Icons.volume_up_rounded : Icons.volume_down_rounded, Colors.white24, tr(context, 'pcSpeaker'), c.toggleSpeaker, key: const ValueKey('callSpeaker')),
                    ])
                  else ...[
                    if (_didNotHappen && widget.onChat != null && c.endReason != CallEnd.blocked)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: FilledButton.icon(
                          key: const ValueKey('callFallbackChat'),
                          onPressed: () {
                            _closing = true;
                            Navigator.of(context).pop();
                            widget.onChat!();
                          },
                          icon: const Icon(Icons.chat_bubble_outline_rounded),
                          label: Text(tr(context, 'callFallbackChat')),
                        ),
                      ),
                    if (_didNotHappen && (c.endReason == CallEnd.micDenied || c.endReason == CallEnd.failed))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: OutlinedButton.icon(
                          key: const ValueKey('callTestMic'),
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54)),
                          onPressed: () {
                            _closing = true;
                            final nav = Navigator.of(context);
                            nav.pop();
                            nav.push(MaterialPageRoute<void>(builder: (_) => const MicTestScreen()));
                          },
                          icon: const Icon(Icons.mic_rounded),
                          label: Text(tr(context, 'callTestMic')),
                        ),
                      ),
                    FilledButton(onPressed: _close, child: Text(tr(context, 'pcDone'))),
                  ],
                  const SizedBox(height: 24),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _round(IconData icon, Color color, String label, Future<void> Function() onTap, {Key? key}) => Column(mainAxisSize: MainAxisSize.min, children: [
        InkResponse(
          key: key,
          onTap: onTap,
          child: CircleAvatar(radius: 32, backgroundColor: color, child: Icon(icon, color: Colors.white, size: 30)),
        ),
        const SizedBox(height: 6),
        SizedBox(width: 96, child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12), textAlign: TextAlign.center)),
      ]);
}

/// Starts a call to the other person of [booking]: explains the microphone,
/// then opens the call screen. Calls need a confirmed booking.
Future<void> startBookingCall(BuildContext context, Booking booking, {bool preferDriver = false, String peer = '', VoidCallback? onChat}) async {
  final me = Backend.uid;
  if (me == null) return;
  if (!bookingAllowsCall(booking)) return showSnack(context, tr(context, 'pcCallOnlyConfirmed'));
  final callee = callTarget(booking, me, preferDriver: preferDriver);
  if (callee == null) return;
  final provider = callProviderFactory();
  if (!provider.supported) return showSnack(context, tr(context, 'pcCallUnsupported'));
  if (!await PermissionRationale.ask(context, RationaleKind.callMicrophone) || !context.mounted) return;
  final controller = CallController(provider);
  final name = await CallController.myDisplayName();
  if (!context.mounted) return;
  unawaited(controller.start(booking: booking, calleeId: callee, callerName: name, peer: peer));
  final nav = Navigator.of(context);
  await nav.push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => CallScreen(controller: controller, peer: peer, onChat: onChat)));
  controller.dispose();
}

/// "Call" button next to Chat (both roles). Hidden when the booking does not
/// allow calls. The other person never sees a phone number.
class BookingCallButton extends StatelessWidget {
  final Booking booking;
  final bool preferDriver;
  final String label;
  final VoidCallback? onChat;

  const BookingCallButton({super.key, required this.booking, this.preferDriver = false, this.label = '', this.onChat});

  @override
  Widget build(BuildContext context) {
    final me = Backend.uid;
    if (me == null || !bookingAllowsCall(booking) || callTarget(booking, me, preferDriver: preferDriver) == null) return const SizedBox.shrink();
    return OutlinedButton.icon(
      key: ValueKey(preferDriver ? 'callDriverButton' : 'callButton'),
      onPressed: () => startBookingCall(context, booking, preferDriver: preferDriver, onChat: onChat),
      icon: const Icon(Icons.call_rounded),
      label: Text(label.isEmpty ? tr(context, 'pcCall') : label),
    );
  }
}

/// Wrap a home screen with this: while the app is open, a call that rings for
/// this person opens the incoming-call screen. A closed app does not ring
/// (LATER(paid): push message).
class IncomingCallHost extends StatefulWidget {
  final Widget child;
  final Stream<List<CallDoc>>? calls;

  const IncomingCallHost({super.key, required this.child, this.calls});

  @override
  State<IncomingCallHost> createState() => _IncomingCallHostState();
}

class _IncomingCallHostState extends State<IncomingCallHost> {
  StreamSubscription<List<CallDoc>>? _sub;
  final _shown = <String>{};
  bool _open = false;

  @override
  void initState() {
    super.initState();
    try {
      _sub = (widget.calls ?? CallSignaling.watchIncoming()).listen(_onCalls, onError: (_) {});
    } catch (_) {
      // No backend yet (a screen shown on its own, a test): nothing can ring.
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _onCalls(List<CallDoc> calls) async {
    if (_open || !mounted) return;
    final fresh = [for (final c in calls) if (c.isFresh(DateTime.now()) && !_shown.contains(c.id)) c];
    if (fresh.isEmpty) return;
    final call = fresh.first;
    _shown.add(call.id);
    _open = true;
    final controller = CallController(callProviderFactory());
    await Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => CallScreen(controller: controller, incoming: call)));
    controller.dispose();
    _open = false;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
