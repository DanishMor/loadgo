import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../call/mic_test.dart';
import 'account_deletion_screen.dart';
import 'account_tools_screens.dart';
import 'devices_screen.dart';
import 'help_screen.dart';
import 'legal_screens.dart';

import '../app_info.dart';
import '../l10n/l10n.dart';
import '../l10n/language_widgets.dart';
import '../models/user_settings.dart';
import '../permissions/permission_rationale.dart';
import '../services/push_service.dart';
import '../services/settings_service.dart';
import '../widgets/common.dart';
import 'simple_mode.dart';

/// Settings for both roles: language, notification preferences, consent
/// center, help and policies, account deletion, app version
/// and logout. [onLogout] is supplied by the caller so core/ does not need
/// to know the app's login screen.
class SettingsScreen extends StatefulWidget {
  final Future<void> Function() onLogout;

  /// Drivers get the Simple Mode switch.
  final bool showSimpleMode;

  /// `customer`, `driver` or `fleet`: Help shows that role's questions.
  final String? helpRole;

  const SettingsScreen({super.key, required this.onLogout, this.showSimpleMode = false, this.helpRole});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  NotificationPrefs? _prefs;
  Consents? _consents;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SettingsService.loadPrefs();
      final consents = await SettingsService.loadConsents();
      if (!mounted) return;
      setState(() {
        _prefs = prefs;
        _consents = consents;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _prefs = const NotificationPrefs();
        _consents = const Consents();
      });
      showSnack(context, tr(context, 'somethingWrong'));
    }
  }

  Future<void> _save(Future<void> Function() write) async {
    try {
      await write();
      if (mounted) showSnack(context, tr(context, 'settingsSaved'));
    } catch (_) {
      if (mounted) showSnack(context, tr(context, 'somethingWrong'));
      _load();
    }
  }

  void _setPrefs(NotificationPrefs p) {
    setState(() => _prefs = p);
    _save(() => SettingsService.savePrefs(p));
  }

  void _setConsents(Consents c) {
    setState(() => _consents = c);
    _save(() => SettingsService.saveConsents(c));
  }

  String _themeLabel(ThemeMode m) => tr(context, switch (m) { ThemeMode.system => 'themeSystem', ThemeMode.light => 'themeLight', ThemeMode.dark => 'themeDark' });

  Future<void> _pickTheme() async {
    final picked = await showDialog<ThemeMode>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(tr(ctx, 'themeMode')),
        children: [
          for (final m in ThemeMode.values)
            ListTile(
              key: ValueKey('theme_${m.name}'),
              leading: Icon(ThemeStore.mode.value == m ? Icons.radio_button_checked : Icons.radio_button_off),
              title: Text(_themeLabel(m)),
              onTap: () => Navigator.pop(ctx, m),
            ),
        ],
      ),
    );
    if (picked != null) await ThemeStore.set(picked);
  }

  void _open(Widget screen) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  Widget _header(String key) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(tr(context, key), style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primary)),
      );

  Widget _switch(String key, String labelKey, bool value, ValueChanged<bool> onChanged) => SwitchListTile(
        key: ValueKey(key),
        title: Text(tr(context, labelKey)),
        value: value,
        onChanged: onChanged,
      );

  @override
  Widget build(BuildContext context) {
    final p = _prefs, c = _consents;
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'settings'))),
      body: p == null || c == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(children: [
              if (widget.showSimpleMode) const SimpleModeSwitch(),
              ListTile(
                key: const ValueKey('settingsLanguage'),
                leading: const Icon(Icons.language_rounded),
                title: Text(tr(context, 'language')),
                trailing: Text(trLanguageName(LanguageScope.of(context))),
                onTap: () => showLanguageSelector(context),
              ),
              ValueListenableBuilder<ThemeMode>(
                valueListenable: ThemeStore.mode,
                builder: (context, mode, _) => ListTile(
                  key: const ValueKey('settingsTheme'),
                  leading: const Icon(Icons.dark_mode_outlined),
                  title: Text(tr(context, 'themeMode')),
                  trailing: Text(_themeLabel(mode)),
                  onTap: _pickTheme,
                ),
              ),
              _header('notificationPrefs'),
              _switch('prefBookings', 'prefBookingUpdates', p.bookingUpdates, (v) => _setPrefs(p.copyWith(bookingUpdates: v))),
              _switch('prefRatings', 'prefRatings', p.ratings, (v) => _setPrefs(p.copyWith(ratings: v))),
              _switch('prefPromotions', 'prefPromotions', p.promotions, (v) => _setPrefs(p.copyWith(promotions: v))),
              _switch('prefPayments', 'notifCat_payments', p.payments, (v) => _setPrefs(p.copyWith(payments: v))),
              _switch('prefReminders', 'notifCat_reminders', p.reminders, (v) => _setPrefs(p.copyWith(reminders: v))),
              _header('consentCenter'),
              _switch('consentLocation', 'consentLocation', c.location, (v) => _setConsents(c.copyWith(location: v))),
              _switch('consentAnalytics', 'consentAnalytics', c.analytics, (v) => _setConsents(c.copyWith(analytics: v))),
              _switch('consentMarketing', 'consentMarketing', c.marketing, (v) => _setConsents(c.copyWith(marketing: v))),
              ListTile(
                key: const ValueKey('settingsDevices'),
                leading: const Icon(Icons.devices_rounded),
                title: Text(tr(context, 'myDevices')),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DevicesScreen())),
              ),
              ListTile(
                key: const ValueKey('settingsMicTest'),
                leading: const Icon(Icons.mic_rounded),
                title: Text(tr(context, 'mtTitle')),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const MicTestScreen())),
              ),
              ListTile(
                key: const ValueKey('settingsPhoneAlerts'),
                leading: const Icon(Icons.notifications_active_outlined),
                title: Text(tr(context, 'rationaleNotifTitle')),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () async {
                  if (!await PermissionRationale.ask(context, RationaleKind.notifications)) return;
                  await PushService.register();
                },
              ),
              const Divider(),
              ListTile(
                key: const ValueKey('settingsTerms'),
                leading: const Icon(Icons.description_outlined),
                title: Text(tr(context, 'termsOfService')),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _open(PolicyScreen.terms),
              ),
              ListTile(
                key: const ValueKey('settingsPrivacy'),
                leading: const Icon(Icons.privacy_tip_outlined),
                title: Text(tr(context, 'privacyPolicy')),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _open(PolicyScreen.privacy),
              ),
              ListTile(
                key: const ValueKey('settingsRefund'),
                leading: const Icon(Icons.currency_rupee_rounded),
                title: Text(tr(context, 'refundPolicy')),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _open(PolicyScreen.refund),
              ),
              ListTile(
                key: const ValueKey('settingsHelp'),
                leading: const Icon(Icons.help_outline_rounded),
                title: Text(tr(context, 'helpCenter')),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _open(HelpScreen(role: widget.helpRole)),
              ),
              ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: Text(tr(context, 'appVersion')),
                trailing: const Text(appVersion, key: ValueKey('appVersion')),
              ),
              const Divider(),
              ListTile(
                key: const ValueKey('settingsLinked'),
                leading: const Icon(Icons.link_rounded),
                title: Text(tr(context, 'linkedAccounts')),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _open(const LinkedAccountsScreen()),
              ),
              ListTile(
                key: const ValueKey('settingsPhone'),
                leading: const Icon(Icons.phone_android_rounded),
                title: Text(tr(context, 'phoneChange')),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _open(const PhoneChangeScreen()),
              ),
              ListTile(
                key: const ValueKey('settingsExport'),
                leading: const Icon(Icons.download_rounded),
                title: Text(tr(context, 'dataExport')),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _open(const DataExportScreen()),
              ),
              ListTile(
                key: const ValueKey('deleteAccount'),
                leading: const Icon(Icons.delete_forever_outlined, color: Colors.redAccent),
                title: Text(tr(context, 'deleteAccount'), style: const TextStyle(color: Colors.redAccent)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _open(const AccountDeletionScreen()),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: OutlinedButton.icon(
                  key: const ValueKey('settingsLogout'),
                  onPressed: widget.onLogout,
                  icon: const Icon(Icons.logout_rounded),
                  label: Text(tr(context, 'logout')),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                ),
              ),
            ]),
    );
  }
}
