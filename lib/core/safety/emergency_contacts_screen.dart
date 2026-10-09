import '../errors/error_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../services/safety_service.dart';
import '../services/user_service.dart';
import '../widgets/common.dart';
import 'call.dart';

/// Up to three people to call in an emergency, stored on the profile.
class EmergencyContactsScreen extends StatefulWidget {
  const EmergencyContactsScreen({super.key});

  @override
  State<EmergencyContactsScreen> createState() => _EmergencyContactsScreenState();
}

class _EmergencyContactsScreenState extends State<EmergencyContactsScreen> {
  List<EmergencyContact>? _contacts;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    UserService.getUser().then((u) {
      if (mounted) setState(() => _contacts = SafetyService.contactsFrom(u));
    }).catchError((_) {
      if (mounted) setState(() => _contacts = []);
    });
  }

  Future<void> _add() async {
    if (_contacts!.length >= SafetyService.maxContacts) {
      showSnack(context, tr(context, 'maxContacts'));
      return;
    }
    final c = await showDialog<EmergencyContact>(context: context, builder: (_) => const _ContactDialog());
    if (c != null) await _save([..._contacts!, c]);
  }

  Future<void> _save(List<EmergencyContact> list) async {
    setState(() => _saving = true);
    try {
      await SafetyService.saveContacts(list);
      if (!mounted) return;
      setState(() => _contacts = list);
      showSnack(context, tr(context, 'contactsSaved'));
    } catch (error) {
      if (mounted) showSnack(context, errorText(context, error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final contacts = _contacts;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        scrolledUnderElevation: 0,
        title: Text(tr(context, 'emergencyContacts'), style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      floatingActionButton: contacts == null || contacts.length >= SafetyService.maxContacts
          ? null
          : FloatingActionButton.extended(
              key: const ValueKey('addContact'),
              onPressed: _saving ? null : _add,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: Text(tr(context, 'addContact')),
            ),
      body: SafeArea(
        child: contacts == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 100),
                children: [
                  Text(tr(context, 'maxContacts'), style: TextStyle(color: AppColors.muted)),
                  const SizedBox(height: 10),
                  for (final (i, c) in contacts.indexed)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.contact_phone_rounded, color: AppColors.primary),
                        title: Text(c.name),
                        subtitle: Text(c.phone),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(tooltip: tr(context, 'a11yCall'), icon: const Icon(Icons.call_rounded), onPressed: () => callNumber(context, c.phone)),
                            IconButton(tooltip: tr(context, 'a11yDelete'), 
                              icon: const Icon(Icons.delete_outline_rounded),
                              onPressed: _saving ? null : () => _save([...contacts]..removeAt(i)),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _ContactDialog extends StatefulWidget {
  const _ContactDialog();

  @override
  State<_ContactDialog> createState() => _ContactDialogState();
}

class _ContactDialogState extends State<_ContactDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr(context, 'addContact')),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const ValueKey('contactName'),
              controller: _name,
              maxLength: 40,
              decoration: InputDecoration(labelText: tr(context, 'placeName'), counterText: ''),
              validator: (v) => (v == null || v.trim().isEmpty) ? tr(context, 'fieldRequired') : null,
            ),
            TextFormField(
              key: const ValueKey('contactPhone'),
              controller: _phone,
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 10,
              decoration: InputDecoration(labelText: tr(context, 'phone'), prefixText: '+91 ', counterText: ''),
              validator: (v) => RegExp(r'^[6-9]\d{9}$').hasMatch(v?.trim() ?? '') ? null : tr(context, 'invalidMobile'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr(context, 'cancel'))),
        FilledButton(
          key: const ValueKey('contactSave'),
          onPressed: () {
            if (_form.currentState!.validate()) {
              Navigator.of(context).pop(EmergencyContact(_name.text.trim(), '+91${_phone.text.trim()}'));
            }
          },
          child: Text(tr(context, 'save')),
        ),
      ],
    );
  }
}
