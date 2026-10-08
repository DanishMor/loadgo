import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/enterprise/validators.dart';
import 'package:transport_app/core/identity/kyc_validators.dart';

/// MASTER-5 Task 22: Indian identifier formats, accepted and refused.
void main() {
  test('vehicle numbers', () {
    for (final ok in ['MH12AB1234', 'mh 12 ab 1234', 'DL1CAB1234', 'KA01A1234', 'TN09AZ0001', '22BH1234AA', 'MH12 1234']) {
      expect(isValidVehicleNumber(ok), isTrue, reason: ok);
    }
    for (final bad in ['', '1234', 'MHAB1234', 'MH12AB12', 'MH12ABCD1234', '22BH12AA', 'AB', 'MH-12-AB-12345']) {
      expect(isValidVehicleNumber(bad), isFalse, reason: bad);
    }
  });

  test('mobile numbers', () {
    for (final ok in ['9876543210', '+919876543210', '919876543210', '09876543210', '+91 98765 43210', '6000000000']) {
      expect(isValidIndianMobile(ok), isTrue, reason: ok);
    }
    for (final bad in ['', '12345', '5876543210', '98765432100', '+449876543210', 'abcdefghij', '98765 4321']) {
      expect(isValidIndianMobile(bad), isFalse, reason: bad);
    }
  });

  test('PIN codes', () {
    expect(isValidPincode('560001'), isTrue);
    expect(isValidPincode(' 110011 '), isTrue);
    for (final bad in ['', '012345', '56001', '5600011', '56000a']) {
      expect(isValidPincode(bad), isFalse, reason: bad);
    }
  });

  test('PAN and GSTIN', () {
    expect(isValidPan('abcde1234f'), isTrue);
    for (final bad in ['ABCDE12345', 'ABCD1234F', '']) {
      expect(isValidPan(bad), isFalse, reason: bad);
    }
    expect(isValidGstinFormat('29ABCDE1234F1Z5'), isTrue);
    for (final bad in ['', '29ABCDE1234F1X5', '9ABCDE1234F1Z5', '29ABCDE1234F1Z']) {
      expect(isValidGstinFormat(bad), isFalse, reason: bad);
    }
  });

  test('driving licence and Aadhaar last four', () {
    expect(isValidDlNumber('MH12 2011 0012345'), isTrue);
    expect(isValidDlNumber('MH12201100123'), isFalse);
    expect(isValidAadhaarLast4('4321'), isTrue);
    expect(isValidAadhaarLast4('123456789012'), isFalse);
  });
}
