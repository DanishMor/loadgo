import 'package:flutter/widgets.dart';

import '../l10n/l10n.dart';
import 'friendly_error.dart';

/// The translated sentence for [error] (MASTER-6 Task 41): no access, no
/// internet, busy, signed out, and so on, never the raw exception text.
/// A null error (nothing to inspect) gives the general message.
String errorText(BuildContext context, Object? error) => tr(context, error == null ? 'somethingWrong' : FriendlyError.of(error));
