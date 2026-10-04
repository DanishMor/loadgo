import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/trip_evidence.dart';
import 'common.dart';

/// Strokes as drawn: points normalised to the pad size.
class _StrokePainter extends CustomPainter {
  final List<List<({double x, double y})>> strokes;
  _StrokePainter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final s in strokes) {
      if (s.length < 2) continue;
      final path = Path()..moveTo(s.first.x * size.width, s.first.y * size.height);
      for (final p in s.skip(1)) {
        path.lineTo(p.x * size.width, p.y * size.height);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StrokePainter old) => true;
}

/// Read-only drawing of saved signature strokes.
class SignatureView extends StatelessWidget {
  final SignatureStrokes signature;
  final double height;
  const SignatureView({super.key, required this.signature, this.height = 120});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppColors.faint), borderRadius: BorderRadius.circular(12)),
      child: CustomPaint(key: const ValueKey('signatureView'), painter: _StrokePainter(signature.strokes)),
    );
  }
}

/// A box to sign in with a finger. [onChanged] gets the strokes so far.
class SignaturePad extends StatefulWidget {
  final ValueChanged<SignatureStrokes> onChanged;
  const SignaturePad({super.key, required this.onChanged});

  @override
  State<SignaturePad> createState() => SignaturePadState();
}

class SignaturePadState extends State<SignaturePad> {
  final List<List<({double x, double y})>> _strokes = [];

  void clear() {
    setState(_strokes.clear);
    widget.onChanged(const SignatureStrokes([]));
  }

  ({double x, double y}) _norm(Offset o, Size size) =>
      (x: (o.dx / size.width).clamp(0, 1).toDouble(), y: (o.dy / size.height).clamp(0, 1).toDouble());

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final size = Size(c.maxWidth, 180);
      return GestureDetector(
        key: const ValueKey('signaturePad'),
        onPanStart: (d) {
          setState(() => _strokes.add([_norm(d.localPosition, size)]));
        },
        onPanUpdate: (d) {
          if (_strokes.isEmpty || _strokes.last.length >= SignatureStrokes.maxPointsPerStroke) return;
          setState(() => _strokes.last.add(_norm(d.localPosition, size)));
        },
        onPanEnd: (_) => widget.onChanged(SignatureStrokes([for (final s in _strokes) List.of(s)])),
        child: Container(
          height: size.height,
          width: double.infinity,
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppColors.primary), borderRadius: BorderRadius.circular(12)),
          child: CustomPaint(painter: _StrokePainter(_strokes)),
        ),
      );
    });
  }
}

/// Dialog with a pad; pops the strokes, or null when cancelled.
Future<SignatureStrokes?> showSignatureDialog(BuildContext context) {
  final pad = GlobalKey<SignaturePadState>();
  var current = const SignatureStrokes([]);
  return showDialog<SignatureStrokes>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(tr(c, 'receiverSignature')),
      content: SizedBox(width: double.maxFinite, child: SignaturePad(key: pad, onChanged: (s) => current = s)),
      actions: [
        TextButton(onPressed: () => pad.currentState?.clear(), child: Text(tr(c, 'clear'))),
        TextButton(onPressed: () => Navigator.pop(c), child: Text(tr(c, 'cancel'))),
        FilledButton(key: const ValueKey('signatureSave'), onPressed: () => Navigator.pop(c, current.isEmpty ? null : current), child: Text(tr(c, 'save'))),
      ],
    ),
  );
}
