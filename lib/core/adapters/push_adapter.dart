class PushMessage {
  final String title;
  final String body;
  final Map<String, String> data;
  const PushMessage({required this.title, required this.body, this.data = const {}});
}

class PushOutcome {
  final int delivered;
  final List<String> badTokens; // tokens to remove from the profile
  const PushOutcome(this.delivered, this.badTokens);
}

/// LATER(paid): sending push needs Cloud Functions (Blaze plan). The send
/// side belongs on the server; this interface is what a function wraps, and
/// what an admin "send test" would call.
abstract class PushGateway {
  /// At most 500 tokens per call. Tokens that are no longer valid come back
  /// in [PushOutcome.badTokens].
  Future<PushOutcome> send(List<String> tokens, PushMessage message);
}

class NoPushGateway implements PushGateway {
  const NoPushGateway();
  @override
  Future<PushOutcome> send(List<String> tokens, PushMessage message) async => const PushOutcome(0, []);
}

class FakePushGateway implements PushGateway {
  final List<(String, PushMessage)> sent = [];
  final Set<String> invalid = {};

  @override
  Future<PushOutcome> send(List<String> tokens, PushMessage message) async {
    if (tokens.length > 500) throw ArgumentError('at most 500 tokens per call');
    var ok = 0;
    final bad = <String>[];
    for (final t in tokens) {
      if (t.isEmpty || invalid.contains(t)) {
        bad.add(t);
      } else {
        sent.add((t, message));
        ok++;
      }
    }
    return PushOutcome(ok, bad);
  }
}
