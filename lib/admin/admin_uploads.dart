import 'package:flutter/material.dart';

import '../core/features/features.dart';
import '../core/l10n/l10n.dart';
import '../core/photos/photo_widgets.dart';
import '../core/services/audit_service.dart';
import '../core/services/backend.dart';
import '../core/theme/design_tokens.dart';
import '../core/widgets/ds/app_button.dart';
import '../core/widgets/feature_gate.dart';

/// Admin: the photos of papers a person uploaded (F30), on the verification card.
/// Nothing loads until the admin presses "Show papers"; that press is written to
/// the audit log. The pictures are read with the admin's sign-in (storage.rules
/// let admins read papers), never from a public link.
class AdminUploads extends StatefulWidget {
  final String uid;
  const AdminUploads({super.key, required this.uid});

  @override
  State<AdminUploads> createState() => _AdminUploadsState();
}

class _AdminUploadsState extends State<AdminUploads> {
  bool _shown = false;

  Future<void> _show() async {
    // The look is recorded first; if the log cannot be written the papers stay hidden.
    try {
      await AuditService.record(AuditType.userAction, targetId: widget.uid, data: {'action': 'view_papers'});
    } catch (_) {
      return;
    }
    if (mounted) setState(() => _shown = true);
  }

  @override
  Widget build(BuildContext context) {
    return FeatureGate(
      featureKey: FeatureKey.photoUploads,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (!_shown)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppButton(key: ValueKey('showPapers_${widget.uid}'), label: tr(context, 'adminShowPapers'), icon: Icons.photo_library_outlined, kind: AppButtonKind.tertiary, expand: false, onPressed: _show),
          )
        else
          StreamBuilder(
            stream: Backend.db.collection('users').doc(widget.uid).collection('uploads').limit(20).snapshots(),
            builder: (context, snap) {
              final docs = snap.data?.docs ?? const [];
              if (docs.isEmpty) return Text(tr(context, 'adminNoPapers'), key: ValueKey('noPapers_${widget.uid}'), style: DsType.caption.copyWith(color: context.ds.textMuted));
              return Wrap(spacing: DsSpace.s3, runSpacing: DsSpace.s3, children: [
                for (final d in docs)
                  if (d.data()['path'] is String)
                    Column(key: ValueKey('paper_${d.id}'), mainAxisSize: MainAxisSize.min, children: [
                      PhotoImage(d.data()['path'] as String, size: 96),
                      const SizedBox(height: DsSpace.s1),
                      SizedBox(
                        width: 96,
                        child: Text(
                          [tr(context, 'photoKind_${d.data()['kind']}'), if (d.data()['vehicleId'] is String) d.data()['vehicleId']].join(' · '),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: DsType.caption.copyWith(color: context.ds.textMuted),
                        ),
                      ),
                    ]),
              ]);
            },
          ),
      ]),
    );
  }
}
