import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../app_info.dart';
import '../l10n/l10n.dart';
import '../models/booking.dart';
import '../widgets/common.dart';
import '../widgets/live_stream.dart';
import 'lr_copy_screen.dart';
import 'lr_copy_view.dart';
import 'lr_model.dart';
import 'lr_pdf.dart';
import 'lr_service.dart';
import 'lr_visibility.dart';

/// Pick a copy type, see exactly what the receiver gets, then send it: to the
/// driver in the app, as a PDF (WhatsApp), or as a link that can be revoked.
class LrSendScreen extends StatefulWidget {
  final Booking booking;
  final LrBundle bundle;
  const LrSendScreen({super.key, required this.booking, required this.bundle});

  @override
  State<LrSendScreen> createState() => _LrSendScreenState();
}

class _LrSendScreenState extends State<LrSendScreen> {
  String _copy = LrCopy.driver;
  bool _showRate = false;
  bool _busy = false;

  LrPublic get _lr => widget.bundle.pub;

  Map<String, Object> get _fields => LrVisibility.snapshot(widget.bundle, _copy, consigneeShowsRate: _showRate);

  Future<void> _run(Future<void> Function() job) async {
    setState(() => _busy = true);
    try {
      await job();
    } on LrException catch (e) {
      if (mounted) showSnack(context, tr(context, e.reason == 'no_driver' ? 'blNoDriver' : 'somethingWrong'));
    } catch (_) {
      if (mounted) showSnack(context, tr(context, 'somethingWrong'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<Uint8List> _pdf(AppLanguage language) async {
    final token = await LrService.verifyToken(widget.booking, _lr);
    return buildLrPdf(LrPdfInput(
      fields: _fields,
      copy: _copy,
      issuerRole: _lr.issuerRole,
      language: language,
      verifyUrl: LrService.linkFor(token),
      issuerName: _lr.issuerName,
      delivered: widget.booking.deliveryOtpVerified,
      generatedAt: DateTime.now(),
    ));
  }

  Future<void> _sharePdf() {
    final language = LanguageScope.of(context);
    return _run(() async {
        final bytes = await _pdf(language);
        if (!mounted) return;
        await SharePlus.instance.share(ShareParams(
          files: [XFile.fromData(bytes, mimeType: 'application/pdf', name: '${_lr.lrNo}.pdf')],
          text: trf(context, 'blShareText', {'app': AppInfo.name, 'no': _lr.lrNo, 'route': _lr.route}),
        ));
        await LrService.noteShare(widget.booking, _lr, _copy, 'pdf');
      });
  }

  Future<void> _createLink() => _run(() async {
        final token = await LrService.createShare(widget.booking, _lr, _copy, _fields);
        if (!mounted) return;
        showSnack(context, tr(context, 'blLinkReady'));
        await SharePlus.instance.share(ShareParams(text: '${trf(context, 'blShareText', {'app': AppInfo.name, 'no': _lr.lrNo, 'route': _lr.route})}\n${LrService.linkFor(token)}'));
      });

  Future<void> _toDriver() => _run(() async {
        await LrService.sendToDriver(widget.booking, _lr);
        if (mounted) showSnack(context, tr(context, 'blSentDriver'));
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(backgroundColor: AppColors.background, scrolledUnderElevation: 0, title: Text(tr(context, 'blSend'), style: const TextStyle(fontWeight: FontWeight.w700))),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 10, 20, 30), children: [
          Text(tr(context, 'blCopyKind'), style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            key: const ValueKey('lrCopyPicker'),
            showSelectedIcon: false,
            segments: [for (final c in LrCopy.all) ButtonSegment(value: c, label: Text(tr(context, lrCopyKey(c)), key: ValueKey('lrCopy_$c'), maxLines: 2, textAlign: TextAlign.center))],
            selected: {_copy},
            onSelectionChanged: (s) => setState(() => _copy = s.first),
          ),
          if (_copy == LrCopy.consignee)
            SwitchListTile(
              key: const ValueKey('lrConsigneeRate'),
              contentPadding: EdgeInsets.zero,
              title: Text(tr(context, 'blConsigneeRate')),
              value: _showRate,
              onChanged: (v) => setState(() => _showRate = v),
            ),
          const SizedBox(height: 12),
          Text(tr(context, 'blPreview'), style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          LrCopyCard(key: ValueKey('lrPreview_$_copy$_showRate'), fields: _fields, copy: _copy, issuerRole: _lr.issuerRole),
          const SizedBox(height: 14),
          if (_copy == LrCopy.driver)
            FilledButton.icon(key: const ValueKey('lrToDriver'), onPressed: _busy ? null : _toDriver, icon: const Icon(Icons.send_rounded), label: Text(tr(context, 'blSendDriver'))),
          const SizedBox(height: 8),
          OutlinedButton.icon(key: const ValueKey('lrSharePdf'), onPressed: _busy ? null : _sharePdf, icon: const Icon(Icons.picture_as_pdf_outlined), label: Text(tr(context, 'blSharePdf'))),
          const SizedBox(height: 8),
          OutlinedButton.icon(key: const ValueKey('lrCreateLink'), onPressed: _busy ? null : _createLink, icon: const Icon(Icons.link_rounded), label: Text(tr(context, 'blCreateLink'))),
          const SizedBox(height: 18),
          Text(tr(context, 'blLinks'), style: const TextStyle(fontWeight: FontWeight.w700)),
          LiveStream<List<LrShare>>(
            compact: true,
            stream: () => LrService.watchShares(_lr.id),
            builder: (context, shares) => Column(children: [
              for (final s in shares.where((s) => s.copyType != 'verify'))
                ListTile(
                  key: ValueKey('lrShare_${s.token}'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr(context, lrCopyKey(s.copyType))),
                  subtitle: Text('${trf(context, 'blViews', {'n': s.views})} · ${s.revoked ? tr(context, 'blRevoked') : trf(context, 'blExpires', {'d': formatDate(s.expiresAt)})}'),
                  trailing: s.revoked ? null : TextButton(key: ValueKey('lrRevoke_${s.token}'), onPressed: () => LrService.revokeShare(s, _lr), child: Text(tr(context, 'blRevoke'))),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}
