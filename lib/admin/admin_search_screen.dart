import 'package:flutter/material.dart';

import '../core/admin/admin_search.dart';
import '../core/errors/friendly_error.dart';
import '../core/l10n/l10n.dart';
import '../core/services/admin_console_service.dart';
import '../core/widgets/common.dart';
import 'admin_user_screen.dart';

/// Admin > Search everything (MASTER-6 Task 10).
class AdminSearchScreen extends StatefulWidget {
  /// Test hooks: the staff role and the lookup.
  final String? role;
  final Future<List<AdminHit>> Function(AdminSearchPlan)? run;
  const AdminSearchScreen({super.key, this.role, this.run});

  @override
  State<AdminSearchScreen> createState() => _AdminSearchScreenState();
}

class _AdminSearchScreenState extends State<AdminSearchScreen> {
  final _q = TextEditingController();
  late final Future<String> _role = widget.role != null ? Future.value(widget.role!) : AdminConsoleService.staffRole();
  List<AdminHit>? _hits;
  bool _short = false;
  bool _busy = false;
  Object? _error;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    if (_busy) return;
    final role = await _role;
    final plan = AdminSearch.plan(_q.text, role: role);
    if (plan.isEmpty) {
      setState(() {
        _short = true;
        _hits = null;
        _error = null;
      });
      return;
    }
    setState(() {
      _busy = true;
      _short = false;
      _error = null;
    });
    try {
      final hits = await (widget.run ?? AdminConsoleService.search)(plan);
      if (mounted) setState(() => _hits = hits);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
    if (mounted) setState(() => _busy = false);
  }

  String _kind(AdminHit h) => switch (h.kind) {
        AdminLookup.booking => 'asBooking',
        AdminLookup.lr => 'asLr',
        AdminLookup.vehicle => 'asVehicle',
        _ => 'asUser',
      };

  void _openUser(String uid) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminUserScreen(uid: uid)));

  Future<void> _open(AdminHit h) async {
    if (h.uid != null && h.uid!.isNotEmpty) return _openUser(h.uid!);
    final id = h.bookingId;
    if (id == null || id.isEmpty) return;
    final b = await AdminConsoleService.bookingSummary(id);
    if (!mounted || b == null) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          SelectableText(id, style: const TextStyle(fontWeight: FontWeight.w800)),
          Text('${b['pickup'] ?? ''} → ${b['drop'] ?? ''} · ${b['status'] ?? ''}'),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            if ('${b['customerId'] ?? ''}'.isNotEmpty) OutlinedButton(key: const ValueKey('asOpenCustomer'), onPressed: () { Navigator.pop(ctx); _openUser('${b['customerId']}'); }, child: Text(tr(ctx, 'asOpenCustomer'))),
            if ('${b['driverId'] ?? ''}'.isNotEmpty) OutlinedButton(key: const ValueKey('asOpenDriver'), onPressed: () { Navigator.pop(ctx); _openUser('${b['driverId']}'); }, child: Text(tr(ctx, 'asOpenDriver'))),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'adminSearch'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
          key: const ValueKey('asQuery'),
          controller: _q,
          maxLength: AdminSearch.maxLength,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(labelText: tr(context, 'asQueryHint'), suffixIcon: IconButton(key: const ValueKey('asGo'), tooltip: tr(context, 'asGo'), icon: const Icon(Icons.search_rounded), onPressed: _go)),
          onSubmitted: (_) => _go(),
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_short) Text(tr(context, 'asShort'), key: const ValueKey('asShort')),
        if (_error != null) Text(tr(context, FriendlyError.of(_error)), key: const ValueKey('asError')),
        if (_hits != null && _hits!.isEmpty) Text(tr(context, 'asNone'), key: const ValueKey('asNone')),
        for (final h in _hits ?? const <AdminHit>[])
          AppCard(
            key: ValueKey('as_${h.kind.name}_${h.id}'),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(h.title),
              subtitle: Text('${tr(context, _kind(h))}${h.subtitle.isEmpty ? '' : ' · ${h.subtitle}'}'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _open(h),
            ),
          ),
        const SizedBox(height: 8),
        Text(tr(context, 'asNote'), style: TextStyle(color: AppColors.faint, fontSize: 12)),
      ]),
    );
  }
}
