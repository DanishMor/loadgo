import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/comm/contact_filter.dart';

ContactKind? k(String s, {List<String> recent = const []}) => ContactFilter.check(s, recent: recent);

void main() {
  group('phone numbers', () {
    test('plain, prefixed, spaced, dashed, dotted, bracketed', () {
      for (final s in [
        '9876543210',
        'call 9876543210 now',
        '+91 98765 43210',
        '+919876543210',
        '09876543210',
        '98765-43210',
        '98765 43210 pe call',
        '9.8.7.6.5.4.3.2.1.0',
        '98 76 54 32 10',
        '(98765) 43210',
        '987-654-3210',
        'no 98765*43210',
        '9876 5432',
        '8765 43210',
        '011 2345 6789',
      ]) {
        expect(k(s), ContactKind.phone, reason: s);
      }
    });

    test('other scripts and keycap emoji', () {
      expect(k('९८७६५४३२१०'), ContactKind.phone, reason: 'Devanagari digits');
      expect(k('৯৮৭৬৫৪৩২১০'), ContactKind.phone, reason: 'Bengali digits');
      expect(k('٩٨٧٦٥٤٣٢١٠'), ContactKind.phone, reason: 'Arabic-Indic digits');
      expect(k('９８７６５４３２１０'), ContactKind.phone, reason: 'full width digits');
      expect(k('9️⃣8️⃣7️⃣6️⃣5️⃣4️⃣3️⃣2️⃣1️⃣0️⃣'), ContactKind.phone, reason: 'keycap emoji');
      expect(k('9​8​7​6​5​4​3​2​1​0'), ContactKind.phone, reason: 'zero width characters');
    });

    test('spelled out in English, Hindi and Hinglish', () {
      expect(k('nau aath saat chhe paanch char teen do ek zero'), ContactKind.phone);
      expect(k('nine eight seven six five four three two one zero'), ContactKind.phone);
      expect(k('नौ आठ सात छह पांच चार तीन दो एक शून्य'), ContactKind.phone);
      expect(k('nau-aath-saat-chhe-paanch-char-teen-do-ek-shunya'), ContactKind.phone);
      expect(k('9 8 seven 6 five 4 teen 2 1 0'), ContactKind.phone, reason: 'digits and words mixed');
      expect(k('nine eight double seven six five four three two'), ContactKind.phone, reason: 'double seven');
      expect(k('98765 four three two one'), ContactKind.phone);
    });

    test('a number split over two messages is caught', () {
      expect(k('98765'), isNull);
      expect(k('43210', recent: ['98765']), ContactKind.phone);
      expect(k('hello', recent: ['98765']), isNull);
      expect(k('43210', recent: ['reached', '98765']), isNull, reason: 'something else in between');
      expect(k('43210'), isNull);
    });

    test('ordinary numbers in a freight chat are fine', () {
      for (final s in [
        'Load is 12000 kg',
        'Weight 12.5 ton, rate 25,000',
        'Rate 12,50,000 only',
        'Pickup at 10:30 am',
        'Reach by 10:30-12:30',
        'Date 05/10/2026 or 2026-10-05',
        'Vehicle MH12AB1234 reached gate 4',
        'Invoice 1234567890123',
        'Pincode 452001',
        'Price 25000-30000',
        '20 x 8 x 8 feet',
        'do ghante mein pahunch jaunga',
        'ek baar dekh lo, do teen packet hain',
        'OTP is 482913',
        'LR number LG-AB12CD34',
        'e-way bill 123456789012',
        'Reached the gate, loading now',
        'Kal subah 6 baje',
        '5 tyre aur 2 spare',
      ]) {
        expect(k(s), isNull, reason: s);
      }
    });
  });

  group('UPI, links and other apps', () {
    test('upi ids and any name@handle', () {
      expect(k('send to ramesh.k@okaxis'), ContactKind.upi);
      expect(k('9876543210@ybl'), ContactKind.upi);
      expect(k('mail me at a@gmail.com'), ContactKind.upi);
      expect(k('ramesh @ paytm'), ContactKind.upi);
    });

    test('whatsapp, telegram, links, call me (English, Hindi, Hinglish)', () {
      for (final s in [
        'WhatsApp pe aao',
        'watsapp karo',
        'w h a t s a p p',
        'whats app me msg',
        'add me on telegram',
        't.me/ramesh',
        'wa.me/919876543210',
        'https://example.com/x',
        'www.site.com',
        'call me',
        'call karo',
        'phone kar lo',
        'mujhe call kr',
        'apna number do',
        'mera number le lo',
        'your mobile number please',
        'phone number bhejo',
        'व्हाट्सएप पर आओ',
        'टेलीग्राम पर',
        'मोबाइल नंबर दो',
        'कॉल करो',
        'अपना नंबर दो',
        'gpay number do',
        'my upi is on the card',
      ]) {
        expect(k(s), ContactKind.app, reason: s);
      }
    });

    test('paying outside the app', () {
      expect(k('Pay outside the app, cheaper'), ContactKind.payment);
      expect(k('app ke bahar payment karo'), ContactKind.payment);
      expect(k('direct payment kar dena'), ContactKind.payment);
      expect(k('ऐप के बाहर पेमेंट'), ContactKind.payment);
    });

    test('harmless sentences', () {
      for (final s in [
        'Namaste, main 20 minute mein aa raha hoon',
        'gaadi ka number kya hai',
        'vehicle number batao',
        'traffic signal par ruka hoon',
        'please call the office if needed',
        'ok done',
        'Thanks! Delivery completed.',
        'recall the load details',
        '',
        '   ',
      ]) {
        expect(k(s), isNull, reason: s);
      }
    });
  });
}
