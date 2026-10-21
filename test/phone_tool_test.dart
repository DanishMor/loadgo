import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Z10: tool/phone_lib.ps1 reads pasted adb output (no phone, no adb call).
/// These need Windows PowerShell 5.1 (the owner's laptop); on Linux CI they are skipped.
final _skipNoPowerShell = Platform.isWindows ? null : 'needs Windows PowerShell';

void main() {
  String ps(String body) {
    final r = Process.runSync('powershell', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', '. ./tool/phone_lib.ps1; $body']);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    return '${r.stdout}'.trim();
  }

  test('devices: the real phone is picked, emulators are ignored', skip: _skipNoPowerShell, () {
    final out = ps(r"""
$t = "List of devices attached`r`nemulator-5554 device product:sdk model:sdk_gphone`r`nR58M1234ABC device usb:1-1 product:x model:SM_A525F transport_id:2`r`n"
$s = Get-PhoneStatus -Devices (ConvertFrom-AdbDevices -Text $t)
"$($s.Status) $($s.Phone.Serial) $($s.Phone.Model)"
""");
    expect(out, 'ready R58M1234ABC SM_A525F');
  });

  test('unauthorized, offline, none and many each give their own advice in Hinglish', skip: _skipNoPowerShell, () {
    final out = ps(r"""
function st($t) { (Get-PhoneStatus -Devices (ConvertFrom-AdbDevices -Text $t)).Status }
st "List of devices attached`r`nR58 unauthorized usb:1`r`n"
st "List of devices attached`r`nR58 offline`r`n"
st "List of devices attached`r`nemulator-5554 device`r`n"
st "List of devices attached`r`nA device`r`nB device`r`n"
""");
    expect(out.split(RegExp(r'\r?\n')), ['unauthorized', 'offline', 'none', 'many']);
    expect(ps("Get-PhoneAdvice -Status 'unauthorized'"), contains('Always allow'));
    expect(ps("Get-PhoneAdvice -Status 'unauthorized'"), contains('Revoke'));
    expect(ps("Get-PhoneAdvice -Status 'none'"), allOf(contains('File transfer'), contains('USB debugging')));
  });

  test('install output: success, signature clash (needs -ReinstallClean), storage', skip: _skipNoPowerShell, () {
    expect(ps(r"$p = Get-InstallProblem -Output 'Performing Streamed Install`nSuccess'; if ($null -eq $p) { 'null' }"), 'null');
    expect(ps(r"(Get-InstallProblem -Output 'adb: failed to install: Failure [INSTALL_FAILED_UPDATE_INCOMPATIBLE: Package signatures do not match]').Message"), contains('-ReinstallClean'));
    expect(ps(r"(Get-InstallProblem -Output 'Failure [INSTALL_FAILED_INSUFFICIENT_STORAGE]').Code"), 'STORAGE');
    expect(ps(r"Test-TransientAdbFailure -Output 'error: device offline'"), 'True');
    expect(ps(r"Test-TransientAdbFailure -Output 'Success'"), 'False');
  });

  test('package id is read from android/gradle.properties', skip: _skipNoPowerShell, () {
    expect(ps(r"Get-PackageIdFromGradleProperties -Path 'android/gradle.properties'"), matches(RegExp(r'^[a-z][\w]*(\.[a-z][\w]*)+$')));
  });

  test('log lines: only flutter, AndroidRuntime, FATAL and E/ lines; personal data masked', skip: _skipNoPowerShell, () {
    expect(ps(r"Test-LogLineWanted -Line '10-21 10:00:00.000 E/AndroidRuntime(123): FATAL EXCEPTION: main'"), 'True');
    expect(ps(r"Test-LogLineWanted -Line '10-21 10:00:00.000 I/flutter (123): hello'"), 'True');
    expect(ps(r"Test-LogLineWanted -Line '10-21 10:00:00.000 I/ActivityManager(1): Start proc'"), 'False');
    final m = ps(r"Get-MaskedLogLine -Line 'E/flutter: user +91 99999 00001 mail a@b.com otp 123456 key AIzaSyA1234567890123456789012345678901 https://x.y/z'");
    expect(m, isNot(contains('99999')));
    expect(m, isNot(contains('a@b.com')));
    expect(m, isNot(contains('123456')));
    expect(m, isNot(contains('AIza')));
    expect(m, isNot(contains('https')));
  });
}
