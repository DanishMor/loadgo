/// Which build this is. The normal app is `customer/driver/fleet` + admin tile.
/// `flutter build web --dart-define=APP_MODE=admin` builds the web console that
/// shows only the admin area (F32); it is a build-time choice, not a setting.
class AppMode {
  AppMode._();

  static const String _value = String.fromEnvironment('APP_MODE');

  static bool get isAdminOnly => _value == 'admin';
}
