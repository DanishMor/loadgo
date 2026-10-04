import 'core/services/auth_helpers.dart';
import 'core/services/connectivity_service.dart';
import 'core/services/language_store.dart';
import 'core/services/push_service.dart';
import 'core/services/user_service.dart';
import 'core/widgets/live_stream.dart' show OfflineBanner;
import 'features/auth/driver_login_screen.dart';
import 'features/home/customer_home_screen.dart';
import 'features/home/driver_home_screen.dart';
import 'features/pending/driver_pending_screen.dart';
import 'features/profile/customer_profile_setup_screen.dart';
import 'features/profile/driver_profile_setup_screen.dart';

import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'firebase_options.dart';
import 'core/l10n/l10n.dart';
import 'core/l10n/language_widgets.dart';

export 'core/l10n/l10n.dart';
export 'core/l10n/language_widgets.dart';
import 'core/services/vehicle_type_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Log uncaught async errors (e.g. a dropped network call) instead of
  // letting them take the app down; screens show their own retry UI.
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught error: $error\n$stack');
    return true;
  };
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await ConnectivityService.start();
  applyLanguageName(await LanguageStore.loadLocal());
  // Register for push whenever a user is signed in (also after app restarts).
  FirebaseAuth.instance.authStateChanges().listen((user) {
    if (user != null) {
      PushService.register();
      VehicleTypeService.refresh();
    }
  });
  runApp(const LoadGoApp());
}

// ============================================================
// ROLE RESOLVERS
// ============================================================

Future<Widget> resolveCustomerStart() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return const RoleSelectionScreen();

  final doc =
      await FirebaseFirestore.instance.collection('users').doc(user.uid).get();

  if (!doc.exists) {
    return CustomerProfileSetupScreen(phoneNumber: user.phoneNumber ?? '');
  }

  final data = doc.data() ?? {};

  if (data['profileComplete'] != true) {
    return CustomerProfileSetupScreen(
      phoneNumber: user.phoneNumber ?? '',
      existingName: data['name']?.toString() ?? '',
    );
  }

  return const CustomerHomeScreen();
}

Future<Widget> resolveDriverStart() async {
  final data = await UserService.getUser();

  final roles = ((data?['roles'] as List?) ?? const [])
      .map((e) => e.toString())
      .toList();
  final profileComplete = data?['driverProfileComplete'] == true;
  final verified = data?['verified'] == true ||
      data?['verificationStatus'] == 'approved';

  if (!roles.contains('driver') || !profileComplete) {
    return const DriverProfileSetupScreen();
  }
  if (!verified) {
    return const DriverPendingScreen();
  }
  return const DriverHomeScreen();
}

// ============================================================
// APP
// ============================================================

class LoadGoApp extends StatelessWidget {
  const LoadGoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return LanguageScope(
      notifier: languageNotifier,
      child: MaterialApp(
        title: 'LoadGo',
        debugShowCheckedModeBanner: false,
        builder: (context, child) => Column(
          children: [
            Expanded(child: child ?? const SizedBox.shrink()),
            const OfflineBanner(),
          ],
        ),
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: 'Roboto',
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF1565C0),
            brightness: Brightness.light,
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE4E7EC)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE4E7EC)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFF1565C0), width: 1.5),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
        ),
        home: const SplashScreen(),
      ),
    );
  }
}

// ============================================================
// SPLASH SCREEN
// ============================================================

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    Widget next = const RoleSelectionScreen();
    final user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      try {
        final data = await UserService.getUser();
        final selectedRole = data?['selectedRole'] as String?;
        next = selectedRole == 'driver'
            ? await resolveDriverStart()
            : await resolveCustomerStart();
      } catch (_) {
        next = const RoleSelectionScreen();
      }
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => next));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0D47A1), Color(0xFF1976D2)],
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 25,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: const Icon(Icons.local_shipping_rounded, size: 70, color: Color(0xFF1565C0)),
              ),
              const SizedBox(height: 28),
              const Text(
                'LoadGo',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 42,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                tr(context, 'tagline'),
                style: const TextStyle(color: Colors.white70, fontSize: 17, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 50),
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// ROLE SELECTION
// ============================================================

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: () => showLanguageSelector(context),
                  icon: const Icon(Icons.language_rounded, size: 19),
                  label: Text(trLanguageName(LanguageScope.of(context))),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'LoadGo',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1565C0)),
              ),
              const SizedBox(height: 12),
              Text(
                tr(context, 'welcome'),
                style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: Color(0xFF111827)),
              ),
              const SizedBox(height: 8),
              Text(
                tr(context, 'chooseRole'),
                style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 32),
              _RoleCard(
                icon: Icons.business_center_rounded,
                title: tr(context, 'bookTruck'),
                subtitle: tr(context, 'customerDesc'),
                buttonText: tr(context, 'continueCustomer'),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const CustomerLoginScreen()),
                  );
                },
              ),
              const SizedBox(height: 18),
              _RoleCard(
                icon: Icons.local_shipping_rounded,
                title: tr(context, 'getLoads'),
                subtitle: tr(context, 'driverDesc'),
                buttonText: tr(context, 'continueDriver'),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DriverLoginScreen()),
                  );
                },
              ),
              const SizedBox(height: 28),
              InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => showLanguageSelector(context),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE4E7EC)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.language_rounded, color: Color(0xFF1565C0), size: 25),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tr(context, 'language'),
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              trLanguageName(LanguageScope.of(context)),
                              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: Color(0xFF667085)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Center(
                child: Text(
                  tr(context, 'footer'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String buttonText;
  final VoidCallback onPressed;

  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.buttonText,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 18, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(color: const Color(0xFFE8F1FF), borderRadius: BorderRadius.circular(16)),
            child: Icon(icon, color: const Color(0xFF1565C0), size: 32),
          ),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF111827))),
          const SizedBox(height: 7),
          Text(subtitle, style: const TextStyle(fontSize: 14, height: 1.45, color: Color(0xFF667085))),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: Text(
                buttonText,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// CUSTOMER LOGIN
// ============================================================

class CustomerLoginScreen extends StatefulWidget {
  const CustomerLoginScreen({super.key});

  @override
  State<CustomerLoginScreen> createState() => _CustomerLoginScreenState();
}

class _CustomerLoginScreenState extends State<CustomerLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _phoneController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _continueWithPhone() async {
    if (!_formKey.currentState!.validate()) return;

    final phone = _phoneController.text.trim();
    setState(() => _isLoading = true);

    void fail(String key) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, key)), behavior: SnackBarBehavior.floating),
      );
    }

    await sendPhoneOtp(
      phone,
      OtpCallbacks(
        onAutoVerified: (credential) async {
          try {
            await FirebaseAuth.instance.signInWithCredential(credential);
            if (!mounted) return;

            setState(() => _isLoading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(tr(context, 'phoneVerified')), behavior: SnackBarBehavior.floating),
            );

            await UserService.markRoleSelected('customer');
            await syncLanguageAfterLogin();
            final next = await resolveCustomerStart();

            if (!mounted) return;
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => next),
              (route) => false,
            );
          } on FirebaseAuthException catch (e) {
            fail(authErrorKey(e.code));
          } catch (_) {
            fail('otpFailed');
          }
        },
        onError: fail,
        onCodeSent: (verificationId, resendToken) {
          if (!mounted) return;
          setState(() => _isLoading = false);
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => OtpVerificationScreen(
                phoneNumber: phone,
                verificationId: verificationId,
                resendToken: resendToken,
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF6F8FC),
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(tr(context, 'login'), style: const TextStyle(fontWeight: FontWeight.w700)),
        actions: const [LanguageButton()],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                Center(
                  child: Container(
                    width: 82,
                    height: 82,
                    decoration: BoxDecoration(color: const Color(0xFFE8F1FF), borderRadius: BorderRadius.circular(24)),
                    child: const Icon(Icons.person_rounded, size: 45, color: Color(0xFF1565C0)),
                  ),
                ),
                const SizedBox(height: 28),
                Center(
                  child: Text(
                    tr(context, 'welcome'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Color(0xFF111827)),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    tr(context, 'loginSub'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 15, color: Color(0xFF667085)),
                  ),
                ),
                const SizedBox(height: 40),
                Text(
                  tr(context, 'mobile'),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF344054)),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  maxLength: 10,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    counterText: '',
                    prefixIcon: const Padding(
                      padding: EdgeInsets.only(left: 16, right: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('🇮🇳', style: TextStyle(fontSize: 20)),
                          SizedBox(width: 8),
                          Text('+91', style: TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    hintText: tr(context, 'mobileHint'),
                  ),
                  validator: (value) {
                    final phone = value?.trim() ?? '';
                    if (phone.isEmpty) return tr(context, 'required');
                    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(phone)) return tr(context, 'invalidMobile');
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _continueWithPhone,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1565C0),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFF9DBCE5),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 23,
                            height: 23,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text(
                            tr(context, 'continueMobile'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(child: Divider(color: Colors.grey.shade300)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        tr(context, 'or'),
                        style: const TextStyle(color: Color(0xFF98A2B3), fontWeight: FontWeight.w600, fontSize: 12),
                      ),
                    ),
                    Expanded(child: Divider(color: Colors.grey.shade300)),
                  ],
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(tr(context, 'googleSoon')), behavior: SnackBarBehavior.floating),
                      );
                    },
                    icon: const Icon(Icons.g_mobiledata_rounded, size: 30),
                    label: Text(tr(context, 'google'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF344054),
                      side: const BorderSide(color: Color(0xFFD0D5DD)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Center(
                  child: Text(
                    tr(context, 'terms'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, height: 1.4, color: Color(0xFF98A2B3)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// OTP (shared by Customer + Driver)
// ============================================================

class OtpVerificationScreen extends StatefulWidget {
  final String phoneNumber;
  final String verificationId;
  final int? resendToken;
  final bool isDriver;

  const OtpVerificationScreen({
    super.key,
    required this.phoneNumber,
    required this.verificationId,
    this.resendToken,
    this.isDriver = false,
  });

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  static const resendSeconds = 60;

  final _otpController = TextEditingController();
  bool _isLoading = false;
  late String _verificationId = widget.verificationId;
  late int? _resendToken = widget.resendToken;
  int _secondsLeft = resendSeconds;
  bool _resending = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _secondsLeft = resendSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) t.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _otpController.dispose();
    super.dispose();
  }

  void _snack(String key) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(tr(context, key)), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _resend() async {
    setState(() => _resending = true);
    await sendPhoneOtp(
      widget.phoneNumber,
      OtpCallbacks(
        onCodeSent: (verificationId, resendToken) {
          if (!mounted) return;
          _verificationId = verificationId;
          _resendToken = resendToken ?? _resendToken;
          setState(() => _resending = false);
          _startTimer();
          _snack('otpResent');
        },
        onError: (key) {
          if (!mounted) return;
          setState(() => _resending = false);
          _snack(key);
        },
        onAutoVerified: (credential) => _signIn(credential),
      ),
      resendToken: _resendToken,
    );
  }

  Future<void> _verifyOtp() async {
    final otp = _otpController.text.trim();

    if (otp.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'invalidOtp')), behavior: SnackBarBehavior.floating),
      );
      return;
    }

    await _signIn(PhoneAuthProvider.credential(verificationId: _verificationId, smsCode: otp));
  }

  Future<void> _signIn(PhoneAuthCredential credential) async {
    setState(() => _isLoading = true);

    try {
      await FirebaseAuth.instance.signInWithCredential(credential);
      if (!mounted) return;
      await syncLanguageAfterLogin();

      Widget next;
      if (widget.isDriver) {
        await UserService.markRoleSelected('driver');
        next = await resolveDriverStart();
      } else {
        await UserService.markRoleSelected('customer');
        next = await resolveCustomerStart();
      }

      if (!mounted) return;
      setState(() => _isLoading = false);

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => next),
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);

      _snack(authErrorKey(e.code));
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'otpFailed')), behavior: SnackBarBehavior.floating),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF6F8FC),
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(tr(context, 'verifyMobile'), style: const TextStyle(fontWeight: FontWeight.w700)),
        actions: const [LanguageButton()],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 35, 20, 30),
          child: Column(
            children: [
              Container(
                width: 82,
                height: 82,
                decoration: BoxDecoration(color: const Color(0xFFE8F1FF), borderRadius: BorderRadius.circular(24)),
                child: const Icon(Icons.sms_rounded, size: 42, color: Color(0xFF1565C0)),
              ),
              const SizedBox(height: 28),
              Text(
                tr(context, 'verifyTitle'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Color(0xFF111827)),
              ),
              const SizedBox(height: 10),
              Text(
                '${tr(context, 'otpText')}\n${maskPhone('+91${widget.phoneNumber}')}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, height: 1.5, color: Color(0xFF667085)),
              ),
              const SizedBox(height: 35),
              TextField(
                controller: _otpController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: 10),
                decoration: const InputDecoration(counterText: '', hintText: '••••••'),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _verifyOtp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1565C0),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 23,
                          height: 23,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Text(
                          tr(context, 'verifyOtp'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                ),
              ),
              const SizedBox(height: 20),
              TextButton(
                key: const Key('resendOtp'),
                onPressed: _secondsLeft > 0 || _resending ? null : _resend,
                child: Text(
                  _secondsLeft > 0 ? trf(context, 'resendIn', {'s': _secondsLeft}) : tr(context, 'resendOtp'),
                  style: TextStyle(
                    color: _secondsLeft > 0 ? const Color(0xFF98A2B3) : const Color(0xFF1565C0),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
