import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/documents/amount_words.dart';
import 'package:transport_app/core/documents/invoice_pdf.dart';

/// MASTER-5 Task 36: the invoice prints amounts the Indian way and in words.
void main() {
  test('amount in words, lakh / crore style', () {
    expect(amountInWords(0), 'Rupees Zero Only');
    expect(amountInWords(100), 'Rupees One Only');
    expect(amountInWords(5), 'Rupees Zero and Five Paise Only');
    expect(amountInWords(1950), 'Rupees Nineteen and Fifty Paise Only');
    expect(amountInWords(2400000), 'Rupees Twenty Four Thousand Only');
    expect(amountInWords(12345600), 'Rupees One Lakh Twenty Three Thousand Four Hundred Fifty Six Only');
    expect(amountInWords(12345670), 'Rupees One Lakh Twenty Three Thousand Four Hundred Fifty Six and Seventy Paise Only');
    expect(amountInWords(1000000000), 'Rupees One Crore Only');
    expect(amountInWords(2500000000), 'Rupees Two Crore Fifty Lakh Only');
    expect(amountInWords(10100), 'Rupees One Hundred and One Only'.replaceAll(' and One', ' One'));
    expect(amountInWords(-5000), 'Minus Rupees Fifty Only');
  });

  test('rupees use Indian grouping', () {
    expect(invoiceRupees(0), '₹0.00');
    expect(invoiceRupees(99999), '₹999.99');
    expect(invoiceRupees(100000), '₹1,000.00');
    expect(invoiceRupees(1234567), '₹12,345.67');
    expect(invoiceRupees(123456789), '₹12,34,567.89');
    expect(invoiceRupees(1000000000), '₹1,00,00,000.00');
  });
}
