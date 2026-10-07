import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../services/feedback_service.dart';
import '../widgets/common.dart';

/// Help > Send feedback: stars, a category and a short note.
class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _text = TextEditingController();
  int _rating = 0;
  String _category = 'app';
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_rating == 0) {
      showSnack(context, tr(context, 'fbPickStars'));
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final thanks = tr(context, 'fbThanks');
    final tooSoon = tr(context, 'fbTooSoon');
    final failed = tr(context, 'somethingWrong');
    final nav = Navigator.of(context);
    setState(() => _busy = true);
    try {
      await FeedbackService.send(rating: _rating, category: _category, text: _text.text);
      nav.pop();
      messenger.showSnackBar(SnackBar(content: Text(thanks), behavior: SnackBarBehavior.floating));
    } on FeedbackTooSoonException {
      messenger.showSnackBar(SnackBar(content: Text(tooSoon), behavior: SnackBarBehavior.floating));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(failed), behavior: SnackBarBehavior.floating));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'fbTitle'))),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text(tr(context, 'fbIntro'), style: TextStyle(color: AppColors.muted)),
        const SizedBox(height: 16),
        FieldLabel(tr(context, 'fbRating')),
        Row(children: [
          for (var i = 1; i <= 5; i++)
            IconButton(
              key: ValueKey('fbStar_$i'),
              tooltip: '$i',
              iconSize: 34,
              onPressed: () => setState(() => _rating = i),
              icon: Icon(i <= _rating ? Icons.star_rounded : Icons.star_border_rounded, color: const Color(0xFFF59E0B)),
            ),
        ]),
        const SizedBox(height: 12),
        FieldLabel(tr(context, 'fbCategory')),
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final c in FeedbackCategory.all)
            ChoiceChip(
              key: ValueKey('fbCat_$c'),
              label: Text(tr(context, 'fbCat_$c')),
              selected: _category == c,
              onSelected: (_) => setState(() => _category = c),
            ),
        ]),
        const SizedBox(height: 14),
        TextField(
          key: const ValueKey('fbText'),
          controller: _text,
          maxLines: 5,
          maxLength: 500,
          inputFormatters: [LengthLimitingTextInputFormatter(500)],
          decoration: InputDecoration(labelText: tr(context, 'fbText')),
        ),
        const SizedBox(height: 12),
        PrimaryButton(label: tr(context, 'fbSend'), loading: _busy, onPressed: _send),
      ]),
    );
  }
}
