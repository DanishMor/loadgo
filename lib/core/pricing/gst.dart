/// Splits a GST-inclusive amount (paise) into taxable value and CGST/SGST.
/// Intra-state split is shown (half each); IGST would be the sum.
class GstSplit {
  final int total;
  final int taxable;
  final int cgst;
  final int sgst;
  final num percent;

  const GstSplit({required this.total, required this.taxable, required this.cgst, required this.sgst, required this.percent});

  int get gst => cgst + sgst;

  factory GstSplit.inclusive(int totalPaise, num gstPercent) {
    final bp = (gstPercent * 100).round(); // basis points
    final taxable = (totalPaise * 10000 / (10000 + bp)).round();
    final gst = totalPaise - taxable;
    final cgst = gst ~/ 2;
    return GstSplit(total: totalPaise, taxable: taxable, cgst: cgst, sgst: gst - cgst, percent: gstPercent);
  }
}
