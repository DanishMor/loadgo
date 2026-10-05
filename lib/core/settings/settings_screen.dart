import 'package:flutter/material.dart';
import 'devices_screen.dart';

import '../app_info.dart';
import '../l10n/l10n.dart';
import '../l10n/language_widgets.dart';
import '../models/user_settings.dart';
import '../services/settings_service.dart';
import '../widgets/common.dart';

/// Settings for both roles: language, notification preferences, consent
/// center, delete-account request, terms/privacy placeholders, app version
/// and logout. [onLogout] is supplied by the caller so core/ does not need
/// to know the app's login screen.
class SettingsScreen extends StatefulWidget {
  final Future<void> Function() onLogout;

  const SettingsScreen({super.key, required this.onLogout});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  NotificationPrefs? _prefs;
  Consents? _consents;
  bool _deletionPending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SettingsService.loadPrefs();
      final consents = await SettingsService.loadConsents();
      final pending = await SettingsService.hasPendingDeletion();
      if (!mounted) return;
      setState(() {
        _prefs = prefs;
        _consents = consents;
        _deletionPending = pending;
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

  Future<void> _requestDeletion() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'deleteAccount')),
        content: Text(tr(ctx, 'deleteAccountInfo')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr(ctx, 'cancel'))),
          FilledButton(
            key: const ValueKey('confirmDeletion'),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr(ctx, 'requestDeletion')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await SettingsService.requestDeletion();
      if (!mounted) return;
      setState(() => _deletionPending = true);
      showSnack(context, tr(context, 'deleteRequestSent'));
    } catch (_) {
      if (mounted) showSnack(context, tr(context, 'somethingWrong'));
    }
  }

  void _legal(String titleKey) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(tr(context, titleKey))),
          body: Padding(padding: const EdgeInsets.all(20), child: Text(tr(context, 'legalPlaceholder'))),
        ),
      ));

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
              ListTile(
                key: const ValueKey('settingsLanguage'),
                leading: const Icon(Icons.language_rounded),
                title: Text(tr(context, 'language')),
                trailing: Text(trLanguageName(LanguageScope.of(context))),
                onTap: () => showLanguageSelector(context),
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
              const Divider(),
              ListTile(
                key: const ValueKey('settingsTerms'),
                leading: const Icon(Icons.description_outlined),
                title: Text(tr(context, 'termsOfService')),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _legal('termsOfService'),
              ),
              ListTile(
                key: const ValueKey('settingsPrivacy'),
                leading: const Icon(Icons.privacy_tip_outlined),
                title: Text(tr(context, 'privacyPolicy')),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _legal('privacyPolicy'),
              ),
              ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: Text(tr(context, 'appVersion')),
                trailing: const Text(appVersion, key: ValueKey('appVersion')),
              ),
              const Divider(),
              ListTile(
                key: const ValueKey('deleteAccount'),
                leading: const Icon(Icons.delete_forever_outlined, color: Colors.redAccent),
                title: Text(tr(context, 'deleteAccount'), style: const TextStyle(color: Colors.redAccent)),
                subtitle: _deletionPending ? Text(tr(context, 'deleteRequestPending')) : null,
                onTap: _deletionPending ? null : _requestDeletion,
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
