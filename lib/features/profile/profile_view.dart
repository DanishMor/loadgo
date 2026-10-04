import 'package:flutter/material.dart';

import '../../core/models/rating.dart';
import '../../core/services/auth_helpers.dart';
import '../../core/services/backend.dart';
import '../../core/services/rating_service.dart';
import '../../core/services/user_service.dart';
import '../../core/widgets/common.dart';
import '../../main.dart';
import '../ratings/rating_widgets.dart';
import '../../core/widgets/live_stream.dart';
import 'edit_profile_screen.dart';
import '../../core/support/support_screens.dart';
import '../../admin/admin_entry.dart';
import '../../core/safety/emergency_contacts_screen.dart';

/// Profile tab for both roles: identity, contact details, average rating and
/// logout. [isDriver] picks which name field and label to show.
class ProfileView extends StatefulWidget {
  final bool isDriver;

  const ProfileView({super.key, required this.isDriver});

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> {
  late final Stream<RatingSummary> _rating = RatingService.watchSummary(Backend.uid ?? '');

  Future<void> _logout() async {
    await UserService.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
      (route) => false,
    );
  }

  Widget _detail(IconData icon, String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: AppColors.muted),
      title: Text(label, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
      subtitle: Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.title)),
    );
  }

  Widget _ratingSection() {
    return StreamBuilder<RatingSummary>(
      stream: _rating,
      builder: (context, snap) {
        final s = snap.data ?? RatingSummary.empty;
        if (s.count == 0) {
          return Text(tr(context, 'noRatingsYet'), style: const TextStyle(color: AppColors.muted));
        }
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            StarRow(stars: s.average.round(), size: 22),
            const SizedBox(width: 8),
            Text('${s.average.toStringAsFixed(1)} (${s.count} ${tr(context, 'ratings')})',
                style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.body)),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: LiveStream<Map<String, dynamic>>(
        stream: UserService.watchUser,
        builder: (context, data) {
          final name = (widget.isDriver ? data['driverName'] : (data['name'] ?? data['fullName'])) as String?;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(tr(context, 'profile'),
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.title)),
                  ),
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => EditProfileScreen(isDriver: widget.isDriver, profile: data),
                    )),
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(tr(context, 'editProfile')),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              AppCard(
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 36,
                      backgroundColor: AppColors.primaryLight,
                      child: Icon(widget.isDriver ? Icons.local_shipping_rounded : Icons.person_rounded,
                          size: 36, color: AppColors.primary),
                    ),
                    const SizedBox(height: 12),
                    Text(name?.isNotEmpty == true ? name! : '--',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.title)),
                    const SizedBox(height: 4),
                    Text(tr(context, widget.isDriver ? 'driver' : 'customer'), style: const TextStyle(color: AppColors.muted)),
                    const SizedBox(height: 10),
                    _ratingSection(),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              AppCard(
                child: Column(
                  children: [
                    _detail(Icons.phone_outlined, tr(context, 'phone'), maskPhone(data['phone'] as String?)),
                    _detail(Icons.email_outlined, tr(context, 'email'), data['email'] as String?),
                    _detail(Icons.business_outlined, tr(context, 'company'), data['companyName'] as String?),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.language_rounded, color: AppColors.muted),
                      title: Text(tr(context, 'language')),
                      trailing: Text(trLanguageName(LanguageScope.of(context))),
                      onTap: () => showLanguageSelector(context),
                    ),
                    const AdminEntryTile(),
                    ListTile(
                      key: const ValueKey('profileSupport'),
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.support_agent_rounded, color: AppColors.muted),
                      title: Text(tr(context, 'helpSupport')),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SupportHomeScreen())),
                    ),
                    ListTile(
                      key: const ValueKey('profileEmergency'),
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.contact_emergency_outlined, color: AppColors.muted),
                      title: Text(tr(context, 'emergencyContacts')),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () =>
                          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EmergencyContactsScreen())),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: _logout,
                icon: const Icon(Icons.logout_rounded),
                label: Text(tr(context, 'logout')),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              ),
            ],
          );
        },
      ),
    );
  }
}
