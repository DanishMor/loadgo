import '../call/call_screens.dart';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';

import '../share/share_links.dart';
import 'app_routes.dart';

/// Opens `https://{host}/load/{id}` links that Android hands to the app
/// (manifest intent filter). The id waits in [pendingLoadId] until a customer
/// or driver home is on screen; [DeepLinkListener] then opens the load and
/// clears it. No extra package: the engine passes the link as a route.
class DeepLinks with WidgetsBindingObserver {
  DeepLinks._();

  static final ValueNotifier<String?> pendingLoadId = ValueNotifier(null);
  static final DeepLinks _observer = DeepLinks._();
  static bool _started = false;

  /// The load id of a link or of a route name like `/load/abc` (null for any
  /// other path). A full link must match [ShareLinks.parseLoadId].
  static String? loadIdFrom(String? link) {
    if (link == null) return null;
    final t = link.trim();
    if (t.startsWith('/')) return ShareLinks.parseLoadId('https://${ShareLinks.host}$t');
    return ShareLinks.parseLoadId(t);
  }

  /// Remembers the load of [link]; true when it was a load link.
  static bool handle(String? link) {
    final id = loadIdFrom(link);
    if (id == null) return false;
    pendingLoadId.value = id;
    return true;
  }

  /// Call once from main(): the link the app was started with, and links
  /// that arrive while it runs.
  static void start() {
    if (_started) return;
    _started = true;
    handle(PlatformDispatcher.instance.defaultRouteName);
    WidgetsBinding.instance.addObserver(_observer);
  }

  @visibleForTesting
  static DeepLinks get observerForTest => _observer;

  @visibleForTesting
  static void reset() {
    if (_started) WidgetsBinding.instance.removeObserver(_observer);
    _started = false;
    pendingLoadId.value = null;
  }

  @override
  Future<bool> didPushRouteInformation(RouteInformation routeInformation) async => handle(routeInformation.uri.toString());
}

/// Put around a home screen: opens the pending shared load once, for this role.
class DeepLinkListener extends StatefulWidget {
  final bool isDriver;
  final Widget child;
  const DeepLinkListener({super.key, required this.isDriver, required this.child});

  @override
  State<DeepLinkListener> createState() => _DeepLinkListenerState();
}

class _DeepLinkListenerState extends State<DeepLinkListener> {
  @override
  void initState() {
    super.initState();
    DeepLinks.pendingLoadId.addListener(_check);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    DeepLinks.pendingLoadId.removeListener(_check);
    super.dispose();
  }

  void _check() {
    final id = DeepLinks.pendingLoadId.value;
    if (id == null || !mounted) return;
    DeepLinks.pendingLoadId.value = null;
    AppRoutes.openLoad?.call(context, id, isDriver: widget.isDriver);
  }

  @override
  // Also the one place every signed-in home passes through: calls ring here.
  Widget build(BuildContext context) => IncomingCallHost(child: widget.child);
}
