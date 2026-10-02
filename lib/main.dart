import 'core/services/user_service.dart';
import 'features/auth/driver_login_screen.dart';
import 'features/home/customer_home_screen.dart';
import 'features/home/driver_home_screen.dart';
import 'features/pending/driver_pending_screen.dart';
import 'features/profile/customer_profile_setup_screen.dart';
import 'features/profile/driver_profile_setup_screen.dart';

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const LoadGoApp());
}

// ============================================================
// 12-LANGUAGE SYSTEM
// ============================================================

enum AppLanguage {
  english,
  hindi,
  hinglish,
  kannada,
  tamil,
  telugu,
  marathi,
  gujarati,
  bengali,
  punjabi,
  kashmiri,
  urdu,
}

final ValueNotifier<AppLanguage> languageNotifier = ValueNotifier<AppLanguage>(
  AppLanguage.english,
);

class LanguageInfo {
  final String nativeName;
  final String englishName;
  const LanguageInfo(this.nativeName, this.englishName);
}

const Map<AppLanguage, LanguageInfo> languageInfo = {
  AppLanguage.english: LanguageInfo('English', 'English'),
  AppLanguage.hindi: LanguageInfo('हिंदी', 'Hindi'),
  AppLanguage.hinglish: LanguageInfo('Hinglish', 'Hinglish'),
  AppLanguage.kannada: LanguageInfo('ಕನ್ನಡ', 'Kannada'),
  AppLanguage.tamil: LanguageInfo('தமிழ்', 'Tamil'),
  AppLanguage.telugu: LanguageInfo('తెలుగు', 'Telugu'),
  AppLanguage.marathi: LanguageInfo('मराठी', 'Marathi'),
  AppLanguage.gujarati: LanguageInfo('ગુજરાતી', 'Gujarati'),
  AppLanguage.bengali: LanguageInfo('বাংলা', 'Bengali'),
  AppLanguage.punjabi: LanguageInfo('ਪੰਜਾਬੀ', 'Punjabi'),
  AppLanguage.kashmiri: LanguageInfo('کٲشُر', 'Kashmiri'),
  AppLanguage.urdu: LanguageInfo('اردو', 'Urdu'),
};

class LanguageScope extends InheritedNotifier<ValueNotifier<AppLanguage>> {
  const LanguageScope({
    super.key,
    required ValueNotifier<AppLanguage> super.notifier,
    required super.child,
  });

  static AppLanguage of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<LanguageScope>();
    return scope?.notifier?.value ?? AppLanguage.english;
  }
}

class T {
  static const Map<String, Map<AppLanguage, String>> data = {
    'tagline': {
      AppLanguage.english: 'Truck & Cargo Booking',
      AppLanguage.hindi: 'ट्रक और कार्गो बुकिंग',
      AppLanguage.hinglish: 'Truck aur Cargo Booking',
      AppLanguage.kannada: 'ಟ್ರಕ್ ಮತ್ತು ಕಾರ್ಗೋ ಬುಕ್ಕಿಂಗ್',
      AppLanguage.tamil: 'டிரக் மற்றும் சரக்கு முன்பதிவு',
      AppLanguage.telugu: 'ట్రక్ మరియు కార్గో బుకింగ్',
      AppLanguage.marathi: 'ट्रक आणि कार्गो बुकिंग',
      AppLanguage.gujarati: 'ટ્રક અને કાર્ગો બુકિંગ',
      AppLanguage.bengali: 'ট্রাক ও কার্গো বুকিং',
      AppLanguage.punjabi: 'ਟਰੱਕ ਅਤੇ ਕਾਰਗੋ ਬੁਕਿੰਗ',
      AppLanguage.kashmiri: 'ٹرٛک تہٕ کارگو بُکِنگ',
      AppLanguage.urdu: 'ٹرک اور کارگو بکنگ',
    },
    'welcome': {
      AppLanguage.english: 'Welcome to LoadGo',
      AppLanguage.hindi: 'लोडगो में आपका स्वागत है',
      AppLanguage.hinglish: 'LoadGo mein aapka welcome hai',
      AppLanguage.kannada: 'ಲೋಡ್‌ಗೋಗೆ ಸ್ವಾಗತ',
      AppLanguage.tamil: 'LoadGo-க்கு வரவேற்கிறோம்',
      AppLanguage.telugu: 'LoadGo కి స్వాగతం',
      AppLanguage.marathi: 'LoadGo मध्ये आपले स्वागत आहे',
      AppLanguage.gujarati: 'LoadGo માં આપનું સ્વાગત છે',
      AppLanguage.bengali: 'LoadGo-তে আপনাকে স্বাগতম',
      AppLanguage.punjabi: 'LoadGo ਵਿੱਚ ਤੁਹਾਡਾ ਸੁਆਗਤ ਹੈ',
      AppLanguage.kashmiri: 'LoadGo منز توہہِ چھِ خیرمقدم',
      AppLanguage.urdu: 'LoadGo میں خوش آمدید',
    },
    'chooseRole': {
      AppLanguage.english: 'Choose how you want to use LoadGo',
      AppLanguage.hindi: 'चुनें कि आप LoadGo का उपयोग कैसे करना चाहते हैं',
      AppLanguage.hinglish: 'Choose karo ki aap LoadGo kaise use karna chahte hain',
      AppLanguage.kannada: 'ನೀವು LoadGo ಅನ್ನು ಹೇಗೆ ಬಳಸಲು ಬಯಸುತ್ತೀರಿ ಆಯ್ಕೆಮಾಡಿ',
      AppLanguage.tamil: 'LoadGo-வை எப்படி பயன்படுத்த விரும்புகிறீர்கள் என்பதைத் தேர்வு செய்யவும்',
      AppLanguage.telugu: 'మీరు LoadGo ను ఎలా ఉపయోగించాలనుకుంటున్నారో ఎంచుకోండి',
      AppLanguage.marathi: 'तुम्हाला LoadGo कसे वापरायचे आहे ते निवडा',
      AppLanguage.gujarati: 'તમે LoadGo કેવી રીતે વાપરવા માંગો છો તે પસંદ કરો',
      AppLanguage.bengali: 'আপনি LoadGo কীভাবে ব্যবহার করতে চান তা বেছে নিন',
      AppLanguage.punjabi: 'ਚੁਣੋ ਕਿ ਤੁਸੀਂ LoadGo ਨੂੰ ਕਿਵੇਂ ਵਰਤਣਾ ਚਾਹੁੰਦੇ ਹੋ',
      AppLanguage.kashmiri: 'چُنیِو زِ توہہِ LoadGo کِتھ پٲٹھۍ کَرِو استعمال',
      AppLanguage.urdu: 'منتخب کریں کہ آپ LoadGo کو کیسے استعمال کرنا چاہتے ہیں',
    },
    'customer': {
      AppLanguage.english: 'Customer',
      AppLanguage.hindi: 'ग्राहक',
      AppLanguage.hinglish: 'Customer',
      AppLanguage.kannada: 'ಗ್ರಾಹಕ',
      AppLanguage.tamil: 'வாடிக்கையாளர்',
      AppLanguage.telugu: 'కస్టమర్',
      AppLanguage.marathi: 'ग्राहक',
      AppLanguage.gujarati: 'ગ્રાહક',
      AppLanguage.bengali: 'গ্রাহক',
      AppLanguage.punjabi: 'ਗਾਹਕ',
      AppLanguage.kashmiri: 'گراہک',
      AppLanguage.urdu: 'صارف',
    },
    'customerDesc': {
      AppLanguage.english: 'For traders, factories, shops, importers & exporters',
      AppLanguage.hindi: 'व्यापारी, फैक्ट्री, दुकान, आयातक और निर्यातक के लिए',
      AppLanguage.hinglish: 'Traders, factories, shops, importers & exporters ke liye',
      AppLanguage.kannada: 'ವ್ಯಾಪಾರಿಗಳು, ಕಾರ್ಖಾನೆಗಳು, ಅಂಗಡಿಗಳು, ಆಮದುದಾರರು ಮತ್ತು ರಫ್ತುದಾರರಿಗೆ',
      AppLanguage.tamil: 'வணிகர்கள், தொழிற்சாலைகள், கடைகள், இறக்குமதியாளர்கள் மற்றும் ஏற்றுமதியாளர்களுக்கு',
      AppLanguage.telugu: 'వ్యాపారులు, ఫ్యాక్టరీలు, షాపులు, దిగుమతిదారులు మరియు ఎగుమతిదారుల కోసం',
      AppLanguage.marathi: 'व्यापारी, कारखाने, दुकाने, आयातदार आणि निर्यातदारांसाठी',
      AppLanguage.gujarati: 'વેપારીઓ, ફેક્ટરીઓ, દુકાનો, આયાતકારો અને નિકાસકારો માટે',
      AppLanguage.bengali: 'ব্যবসায়ী, কারখানা, দোকান, আমদানিকারক ও রপ্তানিকারকদের জন্য',
      AppLanguage.punjabi: 'ਵਪਾਰੀਆਂ, ਫੈਕਟਰੀਆਂ, ਦੁਕਾਨਾਂ, ਆਯਾਤਕਾਰਾਂ ਅਤੇ ਨਿਰਯਾਤਕਾਰਾਂ ਲਈ',
      AppLanguage.kashmiri: 'تاجٕر، فیکٹری، دُکان، امپورٹر تہٕ ایکسپورٹر خٲطرٕ',
      AppLanguage.urdu: 'تاجروں، فیکٹریوں، دکانوں، درآمد کنندگان اور برآمد کنندگان کے لیے',
    },
    'bookTruck': {
      AppLanguage.english: 'Book a Truck',
      AppLanguage.hindi: 'ट्रक बुक करें',
      AppLanguage.hinglish: 'Truck Book Karo',
      AppLanguage.kannada: 'ಟ್ರಕ್ ಬುಕ್ ಮಾಡಿ',
      AppLanguage.tamil: 'டிரக்கை முன்பதிவு செய்',
      AppLanguage.telugu: 'ట్రక్ బుక్ చేయండి',
      AppLanguage.marathi: 'ट्रक बुक करा',
      AppLanguage.gujarati: 'ટ્રક બુક કરો',
      AppLanguage.bengali: 'ট্রাক বুক করুন',
      AppLanguage.punjabi: 'ਟਰੱਕ ਬੁੱਕ ਕਰੋ',
      AppLanguage.kashmiri: 'ٹرٛک کٔر بُک',
      AppLanguage.urdu: 'ٹرک بک کریں',
    },
    'continueCustomer': {
      AppLanguage.english: 'Continue as Customer',
      AppLanguage.hindi: 'ग्राहक के रूप में जारी रखें',
      AppLanguage.hinglish: 'Customer ke roop mein Continue Karo',
      AppLanguage.kannada: 'ಗ್ರಾಹಕರಾಗಿ ಮುಂದುವರಿಸಿ',
      AppLanguage.tamil: 'வாடிக்கையாளராக தொடரவும்',
      AppLanguage.telugu: 'కస్టమర్‌గా కొనసాగించండి',
      AppLanguage.marathi: 'ग्राहक म्हणून पुढे जा',
      AppLanguage.gujarati: 'ગ્રાહક તરીકે ચાલુ રાખો',
      AppLanguage.bengali: 'গ্রাহক হিসেবে চালিয়ে যান',
      AppLanguage.punjabi: 'ਗਾਹਕ ਵਜੋਂ ਜਾਰੀ ਰੱਖੋ',
      AppLanguage.kashmiri: 'گراہک طوٗر جاری تھاو',
      AppLanguage.urdu: 'صارف کے طور پر جاری رکھیں',
    },
    'driver': {
      AppLanguage.english: 'Driver',
      AppLanguage.hindi: 'ड्राइवर',
      AppLanguage.hinglish: 'Driver',
      AppLanguage.kannada: 'ಚಾಲಕ',
      AppLanguage.tamil: 'ஓட்டுநர்',
      AppLanguage.telugu: 'డ్రైవర్',
      AppLanguage.marathi: 'ड्रायव्हर',
      AppLanguage.gujarati: 'ડ્રાઇવર',
      AppLanguage.bengali: 'ড্রাইভার',
      AppLanguage.punjabi: 'ਡਰਾਈਵਰ',
      AppLanguage.kashmiri: 'ڈرایِور',
      AppLanguage.urdu: 'ڈرائیور',
    },
    'driverDesc': {
      AppLanguage.english: 'For truck owners and drivers',
      AppLanguage.hindi: 'ट्रक मालिकों और ड्राइवरों के लिए',
      AppLanguage.hinglish: 'Truck owners aur drivers ke liye',
      AppLanguage.kannada: 'ಟ್ರಕ್ ಮಾಲೀಕರು ಮತ್ತು ಚಾಲಕರಿಗಾಗಿ',
      AppLanguage.tamil: 'டிரக் உரிமையாளர்கள் மற்றும் ஓட்டுநர்களுக்காக',
      AppLanguage.telugu: 'ట్రక్ యజమానులు మరియు డ్రైవర్ల కోసం',
      AppLanguage.marathi: 'ट्रक मालक आणि ड्रायव्हर्ससाठी',
      AppLanguage.gujarati: 'ટ્રક માલિકો અને ડ્રાઇવરો માટે',
      AppLanguage.bengali: 'ট্রাক মালিক ও ড্রাইভারদের জন্য',
      AppLanguage.punjabi: 'ਟਰੱਕ ਮਾਲਕਾਂ ਅਤੇ ਡਰਾਈਵਰਾਂ ਲਈ',
      AppLanguage.kashmiri: 'ٹرٛک مالکن تہٕ ڈرایِور خٲطرٕ',
      AppLanguage.urdu: 'ٹرک مالکان اور ڈرائیوروں کے لیے',
    },
    'getLoads': {
      AppLanguage.english: 'Get Loads',
      AppLanguage.hindi: 'लोड पाएं',
      AppLanguage.hinglish: 'Loads Pao',
      AppLanguage.kannada: 'ಲೋಡ್‌ಗಳನ್ನು ಪಡೆಯಿರಿ',
      AppLanguage.tamil: 'சரக்குகளைப் பெறுங்கள்',
      AppLanguage.telugu: 'లోడ్లను పొందండి',
      AppLanguage.marathi: 'लोड मिळवा',
      AppLanguage.gujarati: 'લોડ મેળવો',
      AppLanguage.bengali: 'লোড পান',
      AppLanguage.punjabi: 'ਲੋਡ ਪ੍ਰਾਪਤ ਕਰੋ',
      AppLanguage.kashmiri: 'لوڈ حٲصِل کٔرِو',
      AppLanguage.urdu: 'لوڈ حاصل کریں',
    },
    'continueDriver': {
      AppLanguage.english: 'Continue as Driver',
      AppLanguage.hindi: 'ड्राइवर के रूप में जारी रखें',
      AppLanguage.hinglish: 'Driver ke roop mein Continue Karo',
      AppLanguage.kannada: 'ಚಾಲಕರಾಗಿ ಮುಂದುವರಿಸಿ',
      AppLanguage.tamil: 'ஓட்டுநராக தொடரவும்',
      AppLanguage.telugu: 'డ్రైవర్‌గా కొనసాగించండి',
      AppLanguage.marathi: 'ड्रायव्हर म्हणून पुढे जा',
      AppLanguage.gujarati: 'ડ્રાઇવર તરીકે ચાલુ રાખો',
      AppLanguage.bengali: 'ড্রাইভার হিসেবে চালিয়ে যান',
      AppLanguage.punjabi: 'ਡਰਾਈਵਰ ਵਜੋਂ ਜਾਰੀ ਰੱਖੋ',
      AppLanguage.kashmiri: 'ڈرایِور طوٗر جاری تھاو',
      AppLanguage.urdu: 'ڈرائیور کے طور پر جاری رکھیں',
    },
    'login': {
      AppLanguage.english: 'Customer Login',
      AppLanguage.hindi: 'ग्राहक लॉगिन',
      AppLanguage.hinglish: 'Customer Login',
      AppLanguage.kannada: 'ಗ್ರಾಹಕ ಲಾಗಿನ್',
      AppLanguage.tamil: 'வாடிக்கையாளர் உள்நுழைவு',
      AppLanguage.telugu: 'కస్టమర్ లాగిన్',
      AppLanguage.marathi: 'ग्राहक लॉगिन',
      AppLanguage.gujarati: 'ગ્રાહક લૉગિન',
      AppLanguage.bengali: 'গ্রাহক লগইন',
      AppLanguage.punjabi: 'ਗਾਹਕ ਲੌਗਇਨ',
      AppLanguage.kashmiri: 'گراہک لاگ اِن',
      AppLanguage.urdu: 'صارف لاگ اِن',
    },
    'loginSub': {
      AppLanguage.english: 'Login or create your customer account',
      AppLanguage.hindi: 'लॉगिन करें या अपना ग्राहक अकाउंट बनाएं',
      AppLanguage.hinglish: 'Login karo ya apna customer account banao',
      AppLanguage.kannada: 'ಲಾಗಿನ್ ಮಾಡಿ ಅಥವಾ ನಿಮ್ಮ ಗ್ರಾಹಕ ಖಾತೆಯನ್ನು ರಚಿಸಿ',
      AppLanguage.tamil: 'உள்நுழையவும் அல்லது உங்கள் வாடிக்கையாளர் கணக்கை உருவாக்கவும்',
      AppLanguage.telugu: 'లాగిన్ చేయండి లేదా మీ కస్టమర్ ఖాతాను సృష్టించండి',
      AppLanguage.marathi: 'लॉगिन करा किंवा तुमचे ग्राहक खाते तयार करा',
      AppLanguage.gujarati: 'લૉગિન કરો અથવા તમારું ગ્રાહક ખાતું બનાવો',
      AppLanguage.bengali: 'লগইন করুন অথবা আপনার গ্রাহক অ্যাকাউন্ট তৈরি করুন',
      AppLanguage.punjabi: 'ਲੌਗਇਨ ਕਰੋ ਜਾਂ ਆਪਣਾ ਗਾਹਕ ਖਾਤਾ ਬਣਾਓ',
      AppLanguage.kashmiri: 'لاگ اِن کٔرِو یا پنُن گراہک اکاؤنٹ بناو',
      AppLanguage.urdu: 'لاگ اِن کریں یا اپنا صارف اکاؤنٹ بنائیں',
    },
    'mobile': {
      AppLanguage.english: 'Mobile Number',
      AppLanguage.hindi: 'मोबाइल नंबर',
      AppLanguage.hinglish: 'Mobile Number',
      AppLanguage.kannada: 'ಮೊಬೈಲ್ ಸಂಖ್ಯೆ',
      AppLanguage.tamil: 'மொபைல் எண்',
      AppLanguage.telugu: 'మొబైల్ నంబర్',
      AppLanguage.marathi: 'मोबाईल नंबर',
      AppLanguage.gujarati: 'મોબાઇલ નંબર',
      AppLanguage.bengali: 'মোবাইল নম্বর',
      AppLanguage.punjabi: 'ਮੋਬਾਈਲ ਨੰਬਰ',
      AppLanguage.kashmiri: 'موبایل نمبر',
      AppLanguage.urdu: 'موبائل نمبر',
    },
    'mobileHint': {
      AppLanguage.english: 'Enter mobile number',
      AppLanguage.hindi: 'मोबाइल नंबर दर्ज करें',
      AppLanguage.hinglish: 'Mobile number enter karo',
      AppLanguage.kannada: 'ಮೊಬೈಲ್ ಸಂಖ್ಯೆಯನ್ನು ನಮೂದಿಸಿ',
      AppLanguage.tamil: 'மொபைல் எண்ணை உள்ளிடவும்',
      AppLanguage.telugu: 'మొబైల్ నంబర్‌ను నమోదు చేయండి',
      AppLanguage.marathi: 'मोबाईल नंबर टाका',
      AppLanguage.gujarati: 'મોબાઇલ નંબર દાખલ કરો',
      AppLanguage.bengali: 'মোবাইল নম্বর দিন',
      AppLanguage.punjabi: 'ਮੋਬਾਈਲ ਨੰਬਰ ਦਰਜ ਕਰੋ',
      AppLanguage.kashmiri: 'موبایل نمبر دٕیِو',
      AppLanguage.urdu: 'موبائل نمبر درج کریں',
    },
    'required': {
      AppLanguage.english: 'Please enter your mobile number',
      AppLanguage.hindi: 'कृपया अपना मोबाइल नंबर दर्ज करें',
      AppLanguage.hinglish: 'Please mobile number enter karo',
      AppLanguage.kannada: 'ದಯವಿಟ್ಟು ನಿಮ್ಮ ಮೊಬೈಲ್ ಸಂಖ್ಯೆಯನ್ನು ನಮೂದಿಸಿ',
      AppLanguage.tamil: 'உங்கள் மொபைல் எண்ணை உள்ளிடவும்',
      AppLanguage.telugu: 'దయచేసి మీ మొబైల్ నంబర్‌ను నమోదు చేయండి',
      AppLanguage.marathi: 'कृपया मोबाईल नंबर टाका',
      AppLanguage.gujarati: 'કૃપા કરીને મોબાઇલ નંબર દાખલ કરો',
      AppLanguage.bengali: 'অনুগ্রহ করে মোবাইল নম্বর দিন',
      AppLanguage.punjabi: 'ਕਿਰਪਾ ਕਰਕੇ ਮੋਬਾਈਲ ਨੰਬਰ ਦਰਜ ਕਰੋ',
      AppLanguage.kashmiri: 'مہربٲنی کٔرِو پنُن موبایل نمبر دٕیِو',
      AppLanguage.urdu: 'براہ کرم موبائل نمبر درج کریں',
    },
    'invalidMobile': {
      AppLanguage.english: 'Valid 10-digit mobile number enter karein',
      AppLanguage.hindi: 'सही 10 अंकों का मोबाइल नंबर दर्ज करें',
      AppLanguage.hinglish: 'Valid 10 digit mobile number enter karo',
      AppLanguage.kannada: 'ಸರಿಯಾದ 10 ಅಂಕಿಯ ಮೊಬೈಲ್ ಸಂಖ್ಯೆಯನ್ನು ನಮೂದಿಸಿ',
      AppLanguage.tamil: 'சரியான 10 இலக்க மொபைல் எண்ணை உள்ளிடவும்',
      AppLanguage.telugu: 'సరైన 10 అంకెల మొబైల్ నంబర్‌ను నమోదు చేయండి',
      AppLanguage.marathi: 'वैध 10 अंकी मोबाईल नंबर टाका',
      AppLanguage.gujarati: 'માન્ય 10 અંકનો મોબાઇલ નંબર દાખલ કરો',
      AppLanguage.bengali: 'সঠিক 10 সংখ্যার মোবাইল নম্বর দিন',
      AppLanguage.punjabi: 'ਵੈਧ 10 ਅੰਕਾਂ ਦਾ ਮੋਬਾਈਲ ਨੰਬਰ ਦਰਜ ਕਰੋ',
      AppLanguage.kashmiri: 'درست 10 ہندسَن ہُنٛد موبایل نمبر دٕیِو',
      AppLanguage.urdu: 'درست 10 ہندسوں کا موبائل نمبر درج کریں',
    },
    'continueMobile': {
      AppLanguage.english: 'Continue with Mobile',
      AppLanguage.hindi: 'मोबाइल से जारी रखें',
      AppLanguage.hinglish: 'Mobile se Continue Karo',
      AppLanguage.kannada: 'ಮೊಬೈಲ್ ಮೂಲಕ ಮುಂದುವರಿಸಿ',
      AppLanguage.tamil: 'மொபைல் மூலம் தொடரவும்',
      AppLanguage.telugu: 'మొబైల్‌తో కొనసాగించండి',
      AppLanguage.marathi: 'मोबाईलद्वारे पुढे जा',
      AppLanguage.gujarati: 'મોબાઇલ સાથે ચાલુ રાખો',
      AppLanguage.bengali: 'মোবাইল দিয়ে চালিয়ে যান',
      AppLanguage.punjabi: 'ਮੋਬਾਈਲ ਨਾਲ ਜਾਰੀ ਰੱਖੋ',
      AppLanguage.kashmiri: 'موبایل سۭتۍ جاری تھاو',
      AppLanguage.urdu: 'موبائل کے ساتھ جاری رکھیں',
    },
    'or': {
      AppLanguage.english: 'OR',
      AppLanguage.hindi: 'या',
      AppLanguage.hinglish: 'YA',
      AppLanguage.kannada: 'ಅಥವಾ',
      AppLanguage.tamil: 'அல்லது',
      AppLanguage.telugu: 'లేదా',
      AppLanguage.marathi: 'किंवा',
      AppLanguage.gujarati: 'અથવા',
      AppLanguage.bengali: 'অথবা',
      AppLanguage.punjabi: 'ਜਾਂ',
      AppLanguage.kashmiri: 'یا',
      AppLanguage.urdu: 'یا',
    },
    'google': {
      AppLanguage.english: 'Continue with Google',
      AppLanguage.hindi: 'Google के साथ जारी रखें',
      AppLanguage.hinglish: 'Google ke saath Continue Karo',
      AppLanguage.kannada: 'Google ಮೂಲಕ ಮುಂದುವರಿಸಿ',
      AppLanguage.tamil: 'Google மூலம் தொடரவும்',
      AppLanguage.telugu: 'Google తో కొనసాగించండి',
      AppLanguage.marathi: 'Google सह पुढे जा',
      AppLanguage.gujarati: 'Google સાથે ચાલુ રાખો',
      AppLanguage.bengali: 'Google দিয়ে চালিয়ে যান',
      AppLanguage.punjabi: 'Google ਨਾਲ ਜਾਰੀ ਰੱਖੋ',
      AppLanguage.kashmiri: 'Google سۭتۍ جاری تھاو',
      AppLanguage.urdu: 'Google کے ساتھ جاری رکھیں',
    },
    'googleSoon': {
      AppLanguage.english: 'Google login next authentication step me add hoga.',
      AppLanguage.hindi: 'Google लॉगिन अगले authentication step में जोड़ा जाएगा।',
      AppLanguage.hinglish: 'Google login next authentication step mein add hoga.',
      AppLanguage.kannada: 'Google ಲಾಗಿನ್ ಮುಂದಿನ ದೃಢೀಕರಣ ಹಂತದಲ್ಲಿ ಸೇರಿಸಲಾಗುತ್ತದೆ.',
      AppLanguage.tamil: 'Google உள்நுழைவு அடுத்த அங்கீகார கட்டத்தில் சேர்க்கப்படும்.',
      AppLanguage.telugu: 'Google లాగిన్ తదుపరి ఆథెంటికేషన్ దశలో జోడించబడుతుంది.',
      AppLanguage.marathi: 'Google लॉगिन पुढील ऑथेंटिकेशन स्टेपमध्ये जोडले जाईल.',
      AppLanguage.gujarati: 'Google લૉગિન આગામી ઓથેન્ટિકેશન સ્ટેપમાં ઉમેરાશે.',
      AppLanguage.bengali: 'Google লগইন পরবর্তী অথেন্টিকেশন ধাপে যোগ হবে।',
      AppLanguage.punjabi: 'Google ਲੌਗਇਨ ਅਗਲੇ ਆਥੈਂਟੀਕੇਸ਼ਨ ਸਟੈਪ ਵਿੱਚ ਜੋੜਿਆ ਜਾਵੇਗਾ।',
      AppLanguage.kashmiri: 'Google لاگ اِن اگلے تصدیقی مرحلس منز یِوان۔',
      AppLanguage.urdu: 'Google لاگ اِن اگلے تصدیقی مرحلے میں شامل ہوگا۔',
    },
    'terms': {
      AppLanguage.english: 'By continuing, you agree to LoadGo Terms & Privacy Policy.',
      AppLanguage.hindi: 'जारी रखकर आप LoadGo की Terms और Privacy Policy से सहमत होते हैं।',
      AppLanguage.hinglish: 'Continue karke aap LoadGo Terms aur Privacy Policy se agree karte hain.',
      AppLanguage.kannada: 'ಮುಂದುವರಿಸುವ ಮೂಲಕ ನೀವು LoadGo ನಿಯಮಗಳು ಮತ್ತು ಗೌಪ್ಯತಾ ನೀತಿಯನ್ನು ಒಪ್ಪುತ್ತೀರಿ.',
      AppLanguage.tamil: 'தொடர்வதன் மூலம் LoadGo விதிமுறைகள் மற்றும் தனியுரிமைக் கொள்கையை ஏற்கிறீர்கள்.',
      AppLanguage.telugu: 'కొనసాగించడం ద్వారా LoadGo నిబంధనలు మరియు గోప్యతా విధానాన్ని అంగీకరిస్తారు.',
      AppLanguage.marathi: 'पुढे जाऊन तुम्ही LoadGo च्या Terms आणि Privacy Policy शी सहमत आहात.',
      AppLanguage.gujarati: 'ચાલુ રાખીને તમે LoadGo ની Terms અને Privacy Policy સાથે સહમત થાઓ છો.',
      AppLanguage.bengali: 'চালিয়ে গেলে আপনি LoadGo-এর Terms ও Privacy Policy-তে সম্মতি দেন।',
      AppLanguage.punjabi: 'ਜਾਰੀ ਰੱਖਣ ਨਾਲ ਤੁਸੀਂ LoadGo ਦੀਆਂ Terms ਅਤੇ Privacy Policy ਨਾਲ ਸਹਿਮਤ ਹੋ।',
      AppLanguage.kashmiri: 'جاری تھاونس سۭتۍ توہہِ LoadGo ہُند Terms تہٕ Privacy Policy مَنٛز راضی گژھان۔',
      AppLanguage.urdu: 'جاری رکھنے سے آپ LoadGo کی Terms اور Privacy Policy سے اتفاق کرتے ہیں۔',
    },
    'phoneVerified': {
      AppLanguage.english: 'Phone verified successfully!',
      AppLanguage.hindi: 'मोबाइल नंबर सफलतापूर्वक सत्यापित हो गया!',
      AppLanguage.hinglish: 'Phone successfully verify ho gaya!',
      AppLanguage.kannada: 'ಫೋನ್ ಯಶಸ್ವಿಯಾಗಿ ಪರಿಶೀಲಿಸಲಾಗಿದೆ!',
      AppLanguage.tamil: 'தொலைபேசி வெற்றிகரமாக சரிபார்க்கப்பட்டது!',
      AppLanguage.telugu: 'ఫోన్ విజయవంతంగా ధృవీకరించబడింది!',
      AppLanguage.marathi: 'मोबाईल नंबर यशस्वीपणे सत्यापित झाला!',
      AppLanguage.gujarati: 'ફોન સફળતાપૂર્વક ચકાસાયો!',
      AppLanguage.bengali: 'ফোন সফলভাবে যাচাই হয়েছে!',
      AppLanguage.punjabi: 'ਫੋਨ ਸਫਲਤਾਪੂਰਵਕ ਵੇਰੀਫਾਈ ਹੋ ਗਿਆ!',
      AppLanguage.kashmiri: 'فون کامیابی سۭتۍ تصدیق گژھ۔',
      AppLanguage.urdu: 'فون کامیابی سے تصدیق ہو گیا!',
    },
    'verifyMobile': {
      AppLanguage.english: 'Verify Mobile',
      AppLanguage.hindi: 'मोबाइल सत्यापित करें',
      AppLanguage.hinglish: 'Mobile Verify Karo',
      AppLanguage.kannada: 'ಮೊಬೈಲ್ ಪರಿಶೀಲಿಸಿ',
      AppLanguage.tamil: 'மொபைலை சரிபார்க்கவும்',
      AppLanguage.telugu: 'మొబైల్‌ను ధృవీకరించండి',
      AppLanguage.marathi: 'मोबाईल सत्यापित करा',
      AppLanguage.gujarati: 'મોબાઇલ ચકાસો',
      AppLanguage.bengali: 'মোবাইল যাচাই করুন',
      AppLanguage.punjabi: 'ਮੋਬਾਈਲ ਦੀ ਪੁਸ਼ਟੀ ਕਰੋ',
      AppLanguage.kashmiri: 'موبایل کٔرِو تصدیق',
      AppLanguage.urdu: 'موبائل کی تصدیق کریں',
    },
    'verifyTitle': {
      AppLanguage.english: 'Verify your number',
      AppLanguage.hindi: 'अपना नंबर सत्यापित करें',
      AppLanguage.hinglish: 'Apna number verify karo',
      AppLanguage.kannada: 'ನಿಮ್ಮ ಸಂಖ್ಯೆಯನ್ನು ಪರಿಶೀಲಿಸಿ',
      AppLanguage.tamil: 'உங்கள் எண்ணை சரிபார்க்கவும்',
      AppLanguage.telugu: 'మీ నంబర్‌ను ధృవీకరించండి',
      AppLanguage.marathi: 'तुमचा नंबर सत्यापित करा',
      AppLanguage.gujarati: 'તમારો નંબર ચકાસો',
      AppLanguage.bengali: 'আপনার নম্বর যাচাই করুন',
      AppLanguage.punjabi: 'ਆਪਣੇ ਨੰਬਰ ਦੀ ਪੁਸ਼ਟੀ ਕਰੋ',
      AppLanguage.kashmiri: 'پنُن نمبر کٔرِو تصدیق',
      AppLanguage.urdu: 'اپنے نمبر کی تصدیق کریں',
    },
    'otpText': {
      AppLanguage.english: 'Enter the 6-digit OTP sent to',
      AppLanguage.hindi: 'भेजा गया 6 अंकों का OTP दर्ज करें',
      AppLanguage.hinglish: 'Bheja gaya 6 digit OTP enter karo',
      AppLanguage.kannada: 'ಕಳುಹಿಸಿದ 6 ಅಂಕಿಯ OTP ನಮೂದಿಸಿ',
      AppLanguage.tamil: 'அனுப்பப்பட்ட 6 இலக்க OTP-ஐ உள்ளிடவும்',
      AppLanguage.telugu: 'పంపిన 6 అంకెల OTPని నమోదు చేయండి',
      AppLanguage.marathi: 'पाठवलेला 6 अंकी OTP टाका',
      AppLanguage.gujarati: 'મોકલાયેલ 6 અંકનો OTP દાખલ કરો',
      AppLanguage.bengali: 'পাঠানো 6 সংখ্যার OTP দিন',
      AppLanguage.punjabi: 'ਭੇਜਿਆ ਗਿਆ 6 ਅੰਕਾਂ ਵਾਲਾ OTP ਦਰਜ ਕਰੋ',
      AppLanguage.kashmiri: 'پنُن نمبرس پٮ۪ٹھ آیہِ 6 ہندسَن ہُنٛد OTP دٕیِو',
      AppLanguage.urdu: 'اپنے نمبر پر بھیجا گیا 6 ہندسوں کا OTP درج کریں',
    },
    'verifyOtp': {
      AppLanguage.english: 'Verify OTP',
      AppLanguage.hindi: 'OTP सत्यापित करें',
      AppLanguage.hinglish: 'OTP Verify Karo',
      AppLanguage.kannada: 'OTP ಪರಿಶೀಲಿಸಿ',
      AppLanguage.tamil: 'OTP சரிபார்க்கவும்',
      AppLanguage.telugu: 'OTP ధృవీకరించండి',
      AppLanguage.marathi: 'OTP सत्यापित करा',
      AppLanguage.gujarati: 'OTP ચકાસો',
      AppLanguage.bengali: 'OTP যাচাই করুন',
      AppLanguage.punjabi: 'OTP ਦੀ ਪੁਸ਼ਟੀ ਕਰੋ',
      AppLanguage.kashmiri: 'OTP کٔرِو تصدیق',
      AppLanguage.urdu: 'OTP کی تصدیق کریں',
    },
    'invalidOtp': {
      AppLanguage.english: '6-digit OTP enter karein.',
      AppLanguage.hindi: '6 अंकों का OTP दर्ज करें।',
      AppLanguage.hinglish: '6 digit OTP enter karo.',
      AppLanguage.kannada: '6 ಅಂಕಿಯ OTP ನಮೂದಿಸಿ.',
      AppLanguage.tamil: '6 இலக்க OTP-ஐ உள்ளிடவும்.',
      AppLanguage.telugu: '6 అంకెల OTP నమోదు చేయండి.',
      AppLanguage.marathi: '6 अंकी OTP टाका.',
      AppLanguage.gujarati: '6 અંકનો OTP દાખલ કરો.',
      AppLanguage.bengali: '6 সংখ্যার OTP দিন।',
      AppLanguage.punjabi: '6 ਅੰਕਾਂ ਵਾਲਾ OTP ਦਰਜ ਕਰੋ।',
      AppLanguage.kashmiri: '6 ہندسَن ہُنٛد OTP دٕیِو۔',
      AppLanguage.urdu: '6 ہندسوں کا OTP درج کریں۔',
    },
    'otpFailed': {
      AppLanguage.english: 'OTP verification failed.',
      AppLanguage.hindi: 'OTP सत्यापन विफल हुआ।',
      AppLanguage.hinglish: 'OTP verification fail ho gaya.',
      AppLanguage.kannada: 'OTP ಪರಿಶೀಲನೆ ವಿಫಲವಾಗಿದೆ.',
      AppLanguage.tamil: 'OTP சரிபார்ப்பு தோல்வியடைந்தது.',
      AppLanguage.telugu: 'OTP ధృవీకరణ విఫలమైంది.',
      AppLanguage.marathi: 'OTP सत्यापन अयशस्वी झाले.',
      AppLanguage.gujarati: 'OTP ચકાસણી નિષ્ફળ થઈ.',
      AppLanguage.bengali: 'OTP যাচাই ব্যর্থ হয়েছে।',
      AppLanguage.punjabi: 'OTP ਦੀ ਪੁਸ਼ਟੀ ਅਸਫਲ ਹੋ ਗਈ।',
      AppLanguage.kashmiri: 'OTP تصدیق ناکام گژھ۔',
      AppLanguage.urdu: 'OTP کی تصدیق ناکام ہوگئی۔',
    },
    'otpExpired': {
      AppLanguage.english: 'OTP expired. Please request a new OTP.',
      AppLanguage.hindi: 'OTP की समय सीमा समाप्त हो गई। नया OTP मांगें।',
      AppLanguage.hinglish: 'OTP expire ho gaya. Naya OTP request karo.',
      AppLanguage.kannada: 'OTP ಅವಧಿ ಮುಗಿದಿದೆ. ಹೊಸ OTP ಕೇಳಿ.',
      AppLanguage.tamil: 'OTP காலாவதியானது. புதிய OTP கோரவும்.',
      AppLanguage.telugu: 'OTP గడువు ముగిసింది. కొత్త OTP అభ్యర్థించండి.',
      AppLanguage.marathi: 'OTP ची मुदत संपली. नवीन OTP मागवा.',
      AppLanguage.gujarati: 'OTP ની સમયસીમા પૂરી થઈ. નવો OTP માગો.',
      AppLanguage.bengali: 'OTP-এর মেয়াদ শেষ হয়েছে। নতুন OTP চেয়ে নিন।',
      AppLanguage.punjabi: 'OTP ਦੀ ਮਿਆਦ ਖਤਮ ਹੋ ਗਈ। ਨਵਾਂ OTP ਮੰਗੋ।',
      AppLanguage.kashmiri: 'OTP ہُند وقت ختم گژھ۔ نَوا OTP درخوٗاست کٔرِو۔',
      AppLanguage.urdu: 'OTP ختم ہوگیا۔ نیا OTP طلب کریں۔',
    },
    'resendOtp': {
      AppLanguage.english: 'Resend OTP',
      AppLanguage.hindi: 'OTP दोबारा भेजें',
      AppLanguage.hinglish: 'OTP Dobara Send Karo',
      AppLanguage.kannada: 'OTP ಮರುಕಳುಹಿಸಿ',
      AppLanguage.tamil: 'OTP-ஐ மீண்டும் அனுப்பவும்',
      AppLanguage.telugu: 'OTP మళ్లీ పంపండి',
      AppLanguage.marathi: 'OTP पुन्हा पाठवा',
      AppLanguage.gujarati: 'OTP ફરી મોકલો',
      AppLanguage.bengali: 'OTP আবার পাঠান',
      AppLanguage.punjabi: 'OTP ਦੁਬਾਰਾ ਭੇਜੋ',
      AppLanguage.kashmiri: 'OTP کٔرِو دوبارٕ روان',
      AppLanguage.urdu: 'OTP دوبارہ بھیجیں',
    },
    'otpResendSoon': {
      AppLanguage.english: 'OTP resend next authentication step me.',
      AppLanguage.hindi: 'OTP दोबारा भेजना अगले authentication step में आएगा।',
      AppLanguage.hinglish: 'OTP resend next authentication step mein aayega.',
      AppLanguage.kannada: 'OTP ಮರುಕಳುಹಿಸುವ ಆಯ್ಕೆ ಮುಂದಿನ ಹಂತದಲ್ಲಿ ಬರುತ್ತದೆ.',
      AppLanguage.tamil: 'OTP மீண்டும் அனுப்பும் வசதி அடுத்த கட்டத்தில் வரும்.',
      AppLanguage.telugu: 'OTP రీసెండ్ తదుపరి దశలో వస్తుంది.',
      AppLanguage.marathi: 'OTP पुन्हा पाठवण्याचा पर्याय पुढील स्टेपमध्ये येईल.',
      AppLanguage.gujarati: 'OTP ફરી મોકલવાનો વિકલ્પ આગામી સ્ટેપમાં આવશે.',
      AppLanguage.bengali: 'OTP পুনরায় পাঠানোর সুবিধা পরবর্তী ধাপে আসবে।',
      AppLanguage.punjabi: 'OTP ਦੁਬਾਰਾ ਭੇਜਣ ਦਾ ਵਿਕਲਪ ਅਗਲੇ ਸਟੈਪ ਵਿੱਚ ਆਵੇਗਾ।',
      AppLanguage.kashmiri: 'OTP دوبارٕ روان کَرن ہُند آپشن اگلے مرحلس منز یِوان۔',
      AppLanguage.urdu: 'OTP دوبارہ بھیجنے کا آپشن اگلے مرحلے میں آئے گا۔',
    },
    'home': {
      AppLanguage.english: 'Home',
      AppLanguage.hindi: 'होम',
      AppLanguage.hinglish: 'Home',
      AppLanguage.kannada: 'ಮುಖಪುಟ',
      AppLanguage.tamil: 'முகப்பு',
      AppLanguage.telugu: 'హోమ్',
      AppLanguage.marathi: 'होम',
      AppLanguage.gujarati: 'હોમ',
      AppLanguage.bengali: 'হোম',
      AppLanguage.punjabi: 'ਹੋਮ',
      AppLanguage.kashmiri: 'ہوم',
      AppLanguage.urdu: 'ہوم',
    },
    'bookings': {
      AppLanguage.english: 'Bookings',
      AppLanguage.hindi: 'बुकिंग',
      AppLanguage.hinglish: 'Bookings',
      AppLanguage.kannada: 'ಬುಕ್ಕಿಂಗ್‌ಗಳು',
      AppLanguage.tamil: 'முன்பதிவுகள்',
      AppLanguage.telugu: 'బుకింగ్‌లు',
      AppLanguage.marathi: 'बुकिंग',
      AppLanguage.gujarati: 'બુકિંગ',
      AppLanguage.bengali: 'বুকিং',
      AppLanguage.punjabi: 'ਬੁਕਿੰਗਾਂ',
      AppLanguage.kashmiri: 'بُکِنگ',
      AppLanguage.urdu: 'بکنگز',
    },
    'loads': {
      AppLanguage.english: 'Loads',
      AppLanguage.hindi: 'लोड',
      AppLanguage.hinglish: 'Loads',
      AppLanguage.kannada: 'ಲೋಡ್‌ಗಳು',
      AppLanguage.tamil: 'சரக்குகள்',
      AppLanguage.telugu: 'లోడ్లు',
      AppLanguage.marathi: 'लोड',
      AppLanguage.gujarati: 'લોડ',
      AppLanguage.bengali: 'লোড',
      AppLanguage.punjabi: 'ਲੋਡ',
      AppLanguage.kashmiri: 'لوڈ',
      AppLanguage.urdu: 'لوڈز',
    },
    'profile': {
      AppLanguage.english: 'Profile',
      AppLanguage.hindi: 'प्रोफाइल',
      AppLanguage.hinglish: 'Profile',
      AppLanguage.kannada: 'ಪ್ರೊಫೈಲ್',
      AppLanguage.tamil: 'சுயவிவரம்',
      AppLanguage.telugu: 'ప్రొఫైల్',
      AppLanguage.marathi: 'प्रोफाइल',
      AppLanguage.gujarati: 'પ્રોફાઇલ',
      AppLanguage.bengali: 'প্রোফাইল',
      AppLanguage.punjabi: 'ਪ੍ਰੋਫਾਈਲ',
      AppLanguage.kashmiri: 'پروفٲیل',
      AppLanguage.urdu: 'پروفائل',
    },
    'welcomeBack': {
      AppLanguage.english: 'Welcome back 👋',
      AppLanguage.hindi: 'वापसी पर स्वागत है 👋',
      AppLanguage.hinglish: 'Welcome back 👋',
      AppLanguage.kannada: 'ಮತ್ತೆ ಸ್ವಾಗತ 👋',
      AppLanguage.tamil: 'மீண்டும் வரவேற்கிறோம் 👋',
      AppLanguage.telugu: 'తిరిగి స్వాగతం 👋',
      AppLanguage.marathi: 'पुन्हा स्वागत आहे 👋',
      AppLanguage.gujarati: 'ફરી સ્વાગત છે 👋',
      AppLanguage.bengali: 'আবারও স্বাগতম 👋',
      AppLanguage.punjabi: 'ਵਾਪਸ ਆਉਣ ਤੇ ਸੁਆਗਤ ਹੈ 👋',
      AppLanguage.kashmiri: 'واپس آوٗن پؠٹھ خیرمقدم 👋',
      AppLanguage.urdu: 'واپسی پر خوش آمدید 👋',
    },
    'search': {
      AppLanguage.english: 'Search trucks, loads, bookings...',
      AppLanguage.hindi: 'ट्रक, लोड, बुकिंग खोजें...',
      AppLanguage.hinglish: 'Trucks, loads, bookings search karo...',
      AppLanguage.kannada: 'ಟ್ರಕ್‌ಗಳು, ಲೋಡ್‌ಗಳು, ಬುಕ್ಕಿಂಗ್‌ಗಳನ್ನು ಹುಡುಕಿ...',
      AppLanguage.tamil: 'டிரக்குகள், சரக்குகள், முன்பதிவுகளைத் தேடுங்கள்...',
      AppLanguage.telugu: 'ట్రక్కులు, లోడ్లు, బుకింగ్‌లను శోధించండి...',
      AppLanguage.marathi: 'ट्रक, लोड, बुकिंग शोधा...',
      AppLanguage.gujarati: 'ટ્રક, લોડ, બુકિંગ શોધો...',
      AppLanguage.bengali: 'ট্রাক, লোড, বুকিং খুঁজুন...',
      AppLanguage.punjabi: 'ਟਰੱਕ, ਲੋਡ, ਬੁਕਿੰਗ ਖੋਜੋ...',
      AppLanguage.kashmiri: 'ٹرٛک، لوڈ، بُکِنگ ژٔھٲنو...',
      AppLanguage.urdu: 'ٹرک، لوڈ، بکنگ تلاش کریں...',
    },
    'heroTitle': {
      AppLanguage.english: 'Move your goods\nwith confidence.',
      AppLanguage.hindi: 'अपने सामान को\nभरोसे के साथ भेजें।',
      AppLanguage.hinglish: 'Apna goods\nconfidence ke saath move karo.',
      AppLanguage.kannada: 'ನಿಮ್ಮ ಸರಕುಗಳನ್ನು\nಭರವಸೆಯಿಂದ ಸಾಗಿಸಿ.',
      AppLanguage.tamil: 'உங்கள் சரக்குகளை\nநம்பிக்கையுடன் அனுப்புங்கள்.',
      AppLanguage.telugu: 'మీ సరుకులను\nనమ్మకంగా తరలించండి.',
      AppLanguage.marathi: 'तुमचा माल\nविश्वासाने पाठवा.',
      AppLanguage.gujarati: 'તમારો માલ\nવિશ્વાસ સાથે મોકલો.',
      AppLanguage.bengali: 'আপনার পণ্য\nআস্থার সাথে পাঠান।',
      AppLanguage.punjabi: 'ਆਪਣਾ ਸਮਾਨ\nਭਰੋਸੇ ਨਾਲ ਭੇਜੋ।',
      AppLanguage.kashmiri: 'پنُن مال\nیقین سۭتۍ روان کٔرِو۔',
      AppLanguage.urdu: 'اپنا سامان\nاعتماد کے ساتھ بھیجیں۔',
    },
    'heroSub': {
      AppLanguage.english: 'Book reliable trucks for domestic,\nimport & export transportation.',
      AppLanguage.hindi: 'घरेलू, आयात और निर्यात परिवहन के लिए\nभरोसेमंद ट्रक बुक करें।',
      AppLanguage.hinglish: 'Domestic, import & export transportation ke liye\nreliable trucks book karo.',
      AppLanguage.kannada: 'ದೇಶೀಯ, ಆಮದು ಮತ್ತು ರಫ್ತು ಸಾಗಣೆಗಾಗಿ\nವಿಶ್ವಾಸಾರ್ಹ ಟ್ರಕ್‌ಗಳನ್ನು ಬುಕ್ ಮಾಡಿ.',
      AppLanguage.tamil: 'உள்நாட்டு, இறக்குமதி மற்றும் ஏற்றுமதி போக்குவரத்திற்காக\nநம்பகமான டிரக்குகளை முன்பதிவு செய்யுங்கள்.',
      AppLanguage.telugu: 'దేశీయ, దిగుమతి మరియు ఎగుమతి రవాణా కోసం\nనమ్మకమైన ట్రక్కులను బుక్ చేయండి.',
      AppLanguage.marathi: 'देशांतर्गत, आयात आणि निर्यात वाहतुकीसाठी\nविश्वासार्ह ट्रक बुक करा.',
      AppLanguage.gujarati: 'સ્થાનિક, આયાત અને નિકાસ પરિવહન માટે\nવિશ્વસનીય ટ્રક બુક કરો.',
      AppLanguage.bengali: 'দেশীয়, আমদানি ও রপ্তানি পরিবহনের জন্য\nবিশ্বস্ত ট্রাক বুক করুন।',
      AppLanguage.punjabi: 'ਘਰੇਲੂ, ਆਯਾਤ ਅਤੇ ਨਿਰਯਾਤ ਆਵਾਜਾਈ ਲਈ\nਭਰੋਸੇਯੋਗ ਟਰੱਕ ਬੁੱਕ ਕਰੋ।',
      AppLanguage.kashmiri: 'ملکی، امپورٹ تہٕ ایکسپورٹ ٹرانسپورٹ خٲطرٕ\nمٕضبوط ٹرٛک بُک کٔرِو۔',
      AppLanguage.urdu: 'ملکی، درآمد اور برآمدی نقل و حمل کے لیے\nقابلِ اعتماد ٹرک بک کریں۔',
    },
    'quickActions': {
      AppLanguage.english: 'Quick Actions',
      AppLanguage.hindi: 'त्वरित विकल्प',
      AppLanguage.hinglish: 'Quick Actions',
      AppLanguage.kannada: 'ತ್ವರಿತ ಆಯ್ಕೆಗಳು',
      AppLanguage.tamil: 'விரைவு செயல்கள்',
      AppLanguage.telugu: 'త్వరిత చర్యలు',
      AppLanguage.marathi: 'जलद पर्याय',
      AppLanguage.gujarati: 'ઝડપી વિકલ્પો',
      AppLanguage.bengali: 'দ্রুত কার্যক্রম',
      AppLanguage.punjabi: 'ਤੁਰੰਤ ਕਾਰਵਾਈਆਂ',
      AppLanguage.kashmiri: 'فوری کٲم',
      AppLanguage.urdu: 'فوری اختیارات',
    },
    'postLoad': {
      AppLanguage.english: 'Post Load',
      AppLanguage.hindi: 'लोड पोस्ट करें',
      AppLanguage.hinglish: 'Load Post Karo',
      AppLanguage.kannada: 'ಲೋಡ್ ಪೋಸ್ಟ್ ಮಾಡಿ',
      AppLanguage.tamil: 'சரக்கை பதிவு செய்யவும்',
      AppLanguage.telugu: 'లోడ్ పోస్ట్ చేయండి',
      AppLanguage.marathi: 'लोड पोस्ट करा',
      AppLanguage.gujarati: 'લોડ પોસ્ટ કરો',
      AppLanguage.bengali: 'লোড পোস্ট করুন',
      AppLanguage.punjabi: 'ਲੋਡ ਪੋਸਟ ਕਰੋ',
      AppLanguage.kashmiri: 'لوڈ پوسٹ کٔرِو',
      AppLanguage.urdu: 'لوڈ پوسٹ کریں',
    },
    'findVehicle': {
      AppLanguage.english: 'Find a vehicle',
      AppLanguage.hindi: 'वाहन खोजें',
      AppLanguage.hinglish: 'Vehicle find karo',
      AppLanguage.kannada: 'ವಾಹನವನ್ನು ಹುಡುಕಿ',
      AppLanguage.tamil: 'வாகனத்தைக் கண்டுபிடிக்கவும்',
      AppLanguage.telugu: 'వాహనాన్ని కనుగొనండి',
      AppLanguage.marathi: 'वाहन शोधा',
      AppLanguage.gujarati: 'વાહન શોધો',
      AppLanguage.bengali: 'গাড়ি খুঁজুন',
      AppLanguage.punjabi: 'ਵਾਹਨ ਲੱਭੋ',
      AppLanguage.kashmiri: 'گاڑی ژٔھٲنو',
      AppLanguage.urdu: 'گاڑی تلاش کریں',
    },
    'findTransporter': {
      AppLanguage.english: 'Find a transporter',
      AppLanguage.hindi: 'ट्रांसपोर्टर खोजें',
      AppLanguage.hinglish: 'Transporter find karo',
      AppLanguage.kannada: 'ಸಾಗಣೆದಾರರನ್ನು ಹುಡುಕಿ',
      AppLanguage.tamil: 'போக்குவரத்தாளரைக் கண்டுபிடிக்கவும்',
      AppLanguage.telugu: 'రవాణాదారుని కనుగొనండి',
      AppLanguage.marathi: 'ट्रान्सपोर्टर शोधा',
      AppLanguage.gujarati: 'ટ્રાન્સપોર્ટર શોધો',
      AppLanguage.bengali: 'পরিবহনকারী খুঁজুন',
      AppLanguage.punjabi: 'ਟਰਾਂਸਪੋਰਟਰ ਲੱਭੋ',
      AppLanguage.kashmiri: 'ٹرانسپورٹر ژٔھٲنو',
      AppLanguage.urdu: 'ٹرانسپورٹر تلاش کریں',
    },
    'track': {
      AppLanguage.english: 'Track',
      AppLanguage.hindi: 'ट्रैक',
      AppLanguage.hinglish: 'Track',
      AppLanguage.kannada: 'ಟ್ರ್ಯಾಕ್',
      AppLanguage.tamil: 'கண்காணிக்கவும்',
      AppLanguage.telugu: 'ట్రాక్',
      AppLanguage.marathi: 'ट्रॅक',
      AppLanguage.gujarati: 'ટ્રેક',
      AppLanguage.bengali: 'ট্র্যাক',
      AppLanguage.punjabi: 'ਟ੍ਰੈਕ',
      AppLanguage.kashmiri: 'ٹریک',
      AppLanguage.urdu: 'ٹریک',
    },
    'trackShipment': {
      AppLanguage.english: 'Track shipment',
      AppLanguage.hindi: 'शिपमेंट ट्रैक करें',
      AppLanguage.hinglish: 'Shipment track karo',
      AppLanguage.kannada: 'ಸರಕು ಸಾಗಣೆಯನ್ನು ಟ್ರ್ಯಾಕ್ ಮಾಡಿ',
      AppLanguage.tamil: 'சரக்கை கண்காணிக்கவும்',
      AppLanguage.telugu: 'షిప్‌మెంట్‌ను ట్రాక్ చేయండి',
      AppLanguage.marathi: 'शिपमेंट ट्रॅक करा',
      AppLanguage.gujarati: 'શિપમેન્ટ ટ્રેક કરો',
      AppLanguage.bengali: 'শিপমেন্ট ট্র্যাক করুন',
      AppLanguage.punjabi: 'ਸ਼ਿਪਮੈਂਟ ਟ੍ਰੈਕ ਕਰੋ',
      AppLanguage.kashmiri: 'شِپمینٹ ٹریک کٔرِو',
      AppLanguage.urdu: 'شپمنٹ ٹریک کریں',
    },
    'viewBookings': {
      AppLanguage.english: 'View bookings',
      AppLanguage.hindi: 'बुकिंग देखें',
      AppLanguage.hinglish: 'Bookings dekho',
      AppLanguage.kannada: 'ಬುಕ್ಕಿಂಗ್‌ಗಳನ್ನು ವೀಕ್ಷಿಸಿ',
      AppLanguage.tamil: 'முன்பதிவுகளைப் பார்க்கவும்',
      AppLanguage.telugu: 'బుకింగ్‌లను చూడండి',
      AppLanguage.marathi: 'बुकिंग पहा',
      AppLanguage.gujarati: 'બુકિંગ જુઓ',
      AppLanguage.bengali: 'বুকিং দেখুন',
      AppLanguage.punjabi: 'ਬੁਕਿੰਗ ਵੇਖੋ',
      AppLanguage.kashmiri: 'بُکِنگ ژٔھٲیو',
      AppLanguage.urdu: 'بکنگز دیکھیں',
    },
    'services': {
      AppLanguage.english: 'Transportation Services',
      AppLanguage.hindi: 'परिवहन सेवाएं',
      AppLanguage.hinglish: 'Transportation Services',
      AppLanguage.kannada: 'ಸಾರಿಗೆ ಸೇವೆಗಳು',
      AppLanguage.tamil: 'போக்குவரத்து சேவைகள்',
      AppLanguage.telugu: 'రవాణా సేవలు',
      AppLanguage.marathi: 'वाहतूक सेवा',
      AppLanguage.gujarati: 'પરિવહન સેવાઓ',
      AppLanguage.bengali: 'পরিবহন পরিষেবা',
      AppLanguage.punjabi: 'ਆਵਾਜਾਈ ਸੇਵਾਵਾਂ',
      AppLanguage.kashmiri: 'ٹرانسپورٹیشن سروسز',
      AppLanguage.urdu: 'نقل و حمل کی خدمات',
    },
    'fullTruck': {
      AppLanguage.english: 'Full Truck',
      AppLanguage.hindi: 'पूरा ट्रक',
      AppLanguage.hinglish: 'Full Truck',
      AppLanguage.kannada: 'ಪೂರ್ಣ ಟ್ರಕ್',
      AppLanguage.tamil: 'முழு டிரக்',
      AppLanguage.telugu: 'పూర్తి ట్రక్',
      AppLanguage.marathi: 'पूर्ण ट्रक',
      AppLanguage.gujarati: 'પૂર્ણ ટ્રક',
      AppLanguage.bengali: 'সম্পূর্ণ ট্রাক',
      AppLanguage.punjabi: 'ਪੂਰਾ ਟਰੱਕ',
      AppLanguage.kashmiri: 'پُورٕ ٹرٛک',
      AppLanguage.urdu: 'مکمل ٹرک',
    },
    'ftl': {
      AppLanguage.english: 'FTL',
      AppLanguage.hindi: 'FTL',
      AppLanguage.hinglish: 'FTL',
      AppLanguage.kannada: 'FTL',
      AppLanguage.tamil: 'FTL',
      AppLanguage.telugu: 'FTL',
      AppLanguage.marathi: 'FTL',
      AppLanguage.gujarati: 'FTL',
      AppLanguage.bengali: 'FTL',
      AppLanguage.punjabi: 'FTL',
      AppLanguage.kashmiri: 'FTL',
      AppLanguage.urdu: 'FTL',
    },
    'container': {
      AppLanguage.english: 'Container',
      AppLanguage.hindi: 'कंटेनर',
      AppLanguage.hinglish: 'Container',
      AppLanguage.kannada: 'ಕಂಟೈನರ್',
      AppLanguage.tamil: 'கன்டெய்னர்',
      AppLanguage.telugu: 'కంటైనర్',
      AppLanguage.marathi: 'कंटेनर',
      AppLanguage.gujarati: 'કન્ટેનર',
      AppLanguage.bengali: 'কন্টেইনার',
      AppLanguage.punjabi: 'ਕੰਟੇਨਰ',
      AppLanguage.kashmiri: 'کنٹینر',
      AppLanguage.urdu: 'کنٹینر',
    },
    'importExport': {
      AppLanguage.english: 'Import / Export',
      AppLanguage.hindi: 'आयात / निर्यात',
      AppLanguage.hinglish: 'Import / Export',
      AppLanguage.kannada: 'ಆಮದು / ರಫ್ತು',
      AppLanguage.tamil: 'இறக்குமதி / ஏற்றுமதி',
      AppLanguage.telugu: 'దిగుమతి / ఎగుమతి',
      AppLanguage.marathi: 'आयात / निर्यात',
      AppLanguage.gujarati: 'આયાત / નિકાસ',
      AppLanguage.bengali: 'আমদানি / রপ্তানি',
      AppLanguage.punjabi: 'ਆਯਾਤ / ਨਿਰਯਾਤ',
      AppLanguage.kashmiri: 'امپورٹ / ایکسپورٹ',
      AppLanguage.urdu: 'درآمد / برآمد',
    },
    'agriLoad': {
      AppLanguage.english: 'Agri Load',
      AppLanguage.hindi: 'कृषि लोड',
      AppLanguage.hinglish: 'Agri Load',
      AppLanguage.kannada: 'ಕೃಷಿ ಲೋಡ್',
      AppLanguage.tamil: 'விவசாய சரக்கு',
      AppLanguage.telugu: 'వ్యవసాయ లోడ్',
      AppLanguage.marathi: 'कृषी लोड',
      AppLanguage.gujarati: 'કૃષિ લોડ',
      AppLanguage.bengali: 'কৃষি লোড',
      AppLanguage.punjabi: 'ਖੇਤੀਬਾੜੀ ਲੋਡ',
      AppLanguage.kashmiri: 'زرعی لوڈ',
      AppLanguage.urdu: 'زرعی لوڈ',
    },
    'agricultural': {
      AppLanguage.english: 'Agricultural',
      AppLanguage.hindi: 'कृषि सामग्री',
      AppLanguage.hinglish: 'Agricultural',
      AppLanguage.kannada: 'ಕೃಷಿ',
      AppLanguage.tamil: 'விவசாயம்',
      AppLanguage.telugu: 'వ్యవసాయం',
      AppLanguage.marathi: 'कृषी',
      AppLanguage.gujarati: 'કૃષિ',
      AppLanguage.bengali: 'কৃষি',
      AppLanguage.punjabi: 'ਖੇਤੀਬਾੜੀ',
      AppLanguage.kashmiri: 'زرعی',
      AppLanguage.urdu: 'زرعی',
    },
    'generalCargo': {
      AppLanguage.english: 'General Cargo',
      AppLanguage.hindi: 'सामान्य कार्गो',
      AppLanguage.hinglish: 'General Cargo',
      AppLanguage.kannada: 'ಸಾಮಾನ್ಯ ಕಾರ್ಗೋ',
      AppLanguage.tamil: 'பொது சரக்கு',
      AppLanguage.telugu: 'సాధారణ కార్గో',
      AppLanguage.marathi: 'सामान्य कार्गो',
      AppLanguage.gujarati: 'સામાન્ય કાર્ગો',
      AppLanguage.bengali: 'সাধারণ কার্গো',
      AppLanguage.punjabi: 'ਜਨਰਲ ਕਾਰਗੋ',
      AppLanguage.kashmiri: 'عام کارگو',
      AppLanguage.urdu: 'عام کارگو',
    },
    'allCargo': {
      AppLanguage.english: 'All cargo',
      AppLanguage.hindi: 'सभी कार्गो',
      AppLanguage.hinglish: 'All cargo',
      AppLanguage.kannada: 'ಎಲ್ಲಾ ಕಾರ್ಗೋ',
      AppLanguage.tamil: 'அனைத்து சரக்குகள்',
      AppLanguage.telugu: 'అన్ని కార్గో',
      AppLanguage.marathi: 'सर्व कार्गो',
      AppLanguage.gujarati: 'તમામ કાર્ગો',
      AppLanguage.bengali: 'সব কার্গো',
      AppLanguage.punjabi: 'ਸਾਰਾ ਕਾਰਗੋ',
      AppLanguage.kashmiri: 'سٲری کارگو',
      AppLanguage.urdu: 'تمام کارگو',
    },
    'recent': {
      AppLanguage.english: 'Recent Activity',
      AppLanguage.hindi: 'हाल की गतिविधि',
      AppLanguage.hinglish: 'Recent Activity',
      AppLanguage.kannada: 'ಇತ್ತೀಚಿನ ಚಟುವಟಿಕೆ',
      AppLanguage.tamil: 'சமீபத்திய செயல்பாடு',
      AppLanguage.telugu: 'ఇటీవలి కార్యకలాపం',
      AppLanguage.marathi: 'अलीकडील क्रियाकलाप',
      AppLanguage.gujarati: 'તાજેતરની પ્રવૃત્તિ',
      AppLanguage.bengali: 'সাম্প্রতিক কার্যকলাপ',
      AppLanguage.punjabi: 'ਹਾਲੀਆ ਗਤੀਵਿਧੀ',
      AppLanguage.kashmiri: 'حالیہ کٲم',
      AppLanguage.urdu: 'حالیہ سرگرمی',
    },
    'viewAll': {
      AppLanguage.english: 'View All',
      AppLanguage.hindi: 'सभी देखें',
      AppLanguage.hinglish: 'View All',
      AppLanguage.kannada: 'ಎಲ್ಲವನ್ನೂ ವೀಕ್ಷಿಸಿ',
      AppLanguage.tamil: 'அனைத்தையும் பார்க்கவும்',
      AppLanguage.telugu: 'అన్నింటినీ చూడండి',
      AppLanguage.marathi: 'सर्व पहा',
      AppLanguage.gujarati: 'બધું જુઓ',
      AppLanguage.bengali: 'সব দেখুন',
      AppLanguage.punjabi: 'ਸਭ ਵੇਖੋ',
      AppLanguage.kashmiri: 'سٲری ژٔھٲیو',
      AppLanguage.urdu: 'سب دیکھیں',
    },
    'noActivity': {
      AppLanguage.english: 'No recent activity',
      AppLanguage.hindi: 'कोई हाल की गतिविधि नहीं',
      AppLanguage.hinglish: 'Abhi koi recent activity nahi hai',
      AppLanguage.kannada: 'ಇತ್ತೀಚಿನ ಚಟುವಟಿಕೆ ಇಲ್ಲ',
      AppLanguage.tamil: 'சமீபத்திய செயல்பாடு இல்லை',
      AppLanguage.telugu: 'ఇటీవలి కార్యకలాపం లేదు',
      AppLanguage.marathi: 'अलीकडील क्रियाकलाप नाही',
      AppLanguage.gujarati: 'હાલમાં કોઈ પ્રવૃત્તિ નથી',
      AppLanguage.bengali: 'সাম্প্রতিক কোনো কার্যকলাপ নেই',
      AppLanguage.punjabi: 'ਕੋਈ ਹਾਲੀਆ ਗਤੀਵਿਧੀ ਨਹੀਂ',
      AppLanguage.kashmiri: 'کاہہِ حالی کٲم چھِ نہٕ',
      AppLanguage.urdu: 'کوئی حالیہ سرگرمی نہیں',
    },
    'activitySub': {
      AppLanguage.english: 'Your bookings and loads will appear here.',
      AppLanguage.hindi: 'आपकी बुकिंग और लोड यहां दिखाई देंगे।',
      AppLanguage.hinglish: 'Aapki bookings aur loads yahan dikhenge.',
      AppLanguage.kannada: 'ನಿಮ್ಮ ಬುಕ್ಕಿಂಗ್‌ಗಳು ಮತ್ತು ಲೋಡ್‌ಗಳು ಇಲ್ಲಿ ಕಾಣಿಸುತ್ತವೆ.',
      AppLanguage.tamil: 'உங்கள் முன்பதிவுகள் மற்றும் சரக்குகள் இங்கே தோன்றும்.',
      AppLanguage.telugu: 'మీ బుకింగ్‌లు మరియు లోడ్లు ఇక్కడ కనిపిస్తాయి.',
      AppLanguage.marathi: 'तुमच्या बुकिंग आणि लोड्स येथे दिसतील.',
      AppLanguage.gujarati: 'તમારી બુકિંગ અને લોડ અહીં દેખાશે.',
      AppLanguage.bengali: 'আপনার বুকিং ও লোড এখানে দেখা যাবে।',
      AppLanguage.punjabi: 'ਤੁਹਾਡੀਆਂ ਬੁਕਿੰਗਾਂ ਅਤੇ ਲੋਡ ਇੱਥੇ ਦਿਖਾਈ ਦੇਣਗੇ।',
      AppLanguage.kashmiri: 'تُہُنٛد بُکِنگ تہٕ لوڈ ییَتھ ژٕھِو۔',
      AppLanguage.urdu: 'آپ کی بکنگز اور لوڈز یہاں دکھائی دیں گے۔',
    },
    'bookingsTitle': {
      AppLanguage.english: 'My Bookings',
      AppLanguage.hindi: 'मेरी बुकिंग',
      AppLanguage.hinglish: 'Meri Bookings',
      AppLanguage.kannada: 'ನನ್ನ ಬುಕ್ಕಿಂಗ್‌ಗಳು',
      AppLanguage.tamil: 'என் முன்பதிவுகள்',
      AppLanguage.telugu: 'నా బుకింగ్‌లు',
      AppLanguage.marathi: 'माझी बुकिंग',
      AppLanguage.gujarati: 'મારી બુકિંગ',
      AppLanguage.bengali: 'আমার বুকিং',
      AppLanguage.punjabi: 'ਮੇਰੀਆਂ ਬੁਕਿੰਗਾਂ',
      AppLanguage.kashmiri: 'میٚن بُکِنگ',
      AppLanguage.urdu: 'میری بکنگز',
    },
    'bookingsSub': {
      AppLanguage.english: 'Your truck bookings will appear here.',
      AppLanguage.hindi: 'आपकी ट्रक बुकिंग यहां दिखाई देंगी।',
      AppLanguage.hinglish: 'Aapki truck bookings yahan dikhengi.',
      AppLanguage.kannada: 'ನಿಮ್ಮ ಟ್ರಕ್ ಬುಕ್ಕಿಂಗ್‌ಗಳು ಇಲ್ಲಿ ಕಾಣಿಸುತ್ತವೆ.',
      AppLanguage.tamil: 'உங்கள் டிரக் முன்பதிவுகள் இங்கே தோன்றும்.',
      AppLanguage.telugu: 'మీ ట్రక్ బుకింగ్‌లు ఇక్కడ కనిపిస్తాయి.',
      AppLanguage.marathi: 'तुमच्या ट्रक बुकिंग येथे दिसतील.',
      AppLanguage.gujarati: 'તમારી ટ્રક બુકિંગ અહીં દેખાશે.',
      AppLanguage.bengali: 'আপনার ট্রাক বুকিং এখানে দেখা যাবে।',
      AppLanguage.punjabi: 'ਤੁਹਾਡੀਆਂ ਟਰੱਕ ਬੁਕਿੰਗਾਂ ਇੱਥੇ ਦਿਖਾਈ ਦੇਣਗੀਆਂ।',
      AppLanguage.kashmiri: 'تُہُنٛد ٹرٛک بُکِنگ ییَتھ ژٕھِو۔',
      AppLanguage.urdu: 'آپ کی ٹرک بکنگز یہاں دکھائی دیں گی۔',
    },
    'loadsTitle': {
      AppLanguage.english: 'My Loads',
      AppLanguage.hindi: 'मेरे लोड',
      AppLanguage.hinglish: 'Mere Loads',
      AppLanguage.kannada: 'ನನ್ನ ಲೋಡ್‌ಗಳು',
      AppLanguage.tamil: 'என் சரக்குகள்',
      AppLanguage.telugu: 'నా లోడ్లు',
      AppLanguage.marathi: 'माझे लोड्स',
      AppLanguage.gujarati: 'મારા લોડ',
      AppLanguage.bengali: 'আমার লোড',
      AppLanguage.punjabi: 'ਮੇਰੇ ਲੋਡ',
      AppLanguage.kashmiri: 'میٚن لوڈ',
      AppLanguage.urdu: 'میرے لوڈز',
    },
    'loadsSub': {
      AppLanguage.english: 'Your posted loads will appear here.',
      AppLanguage.hindi: 'आपके पोस्ट किए गए लोड यहां दिखाई देंगे।',
      AppLanguage.hinglish: 'Aapke posted loads yahan dikhenge.',
      AppLanguage.kannada: 'ನೀವು ಪೋಸ್ಟ್ ಮಾಡಿದ ಲೋಡ್‌ಗಳು ಇಲ್ಲಿ ಕಾಣಿಸುತ್ತವೆ.',
      AppLanguage.tamil: 'நீங்கள் பதிவு செய்த சரக்குகள் இங்கே தோன்றும்.',
      AppLanguage.telugu: 'మీరు పోస్ట్ చేసిన లోడ్లు ఇక్కడ కనిపిస్తాయి.',
      AppLanguage.marathi: 'तुमचे पोस्ट केलेले लोड येथे दिसतील.',
      AppLanguage.gujarati: 'તમારા પોસ્ટ કરેલા લોડ અહીં દેખાશે.',
      AppLanguage.bengali: 'আপনার পোস্ট করা লোড এখানে দেখা যাবে।',
      AppLanguage.punjabi: 'ਤੁਹਾਡੇ ਪੋਸਟ ਕੀਤੇ ਲੋਡ ਇੱਥੇ ਦਿਖਾਈ ਦੇਣਗੇ।',
      AppLanguage.kashmiri: 'تُہُنٛد پوسٹ کٔرِتھ لوڈ ییَتھ ژٕھِو۔',
      AppLanguage.urdu: 'آپ کے پوسٹ کیے گئے لوڈز یہاں دکھائی دیں گے۔',
    },
    'profileTitle': {
      AppLanguage.english: 'My Profile',
      AppLanguage.hindi: 'मेरी प्रोफाइल',
      AppLanguage.hinglish: 'Meri Profile',
      AppLanguage.kannada: 'ನನ್ನ ಪ್ರೊಫೈಲ್',
      AppLanguage.tamil: 'என் சுயவிவரம்',
      AppLanguage.telugu: 'నా ప్రొఫైల్',
      AppLanguage.marathi: 'माझी प्रोफाइल',
      AppLanguage.gujarati: 'મારી પ્રોફાઇલ',
      AppLanguage.bengali: 'আমার প্রোফাইল',
      AppLanguage.punjabi: 'ਮੇਰੀ ਪ੍ਰੋਫਾਈਲ',
      AppLanguage.kashmiri: 'میٚن پروفٲیل',
      AppLanguage.urdu: 'میری پروفائل',
    },
    'profileSub': {
      AppLanguage.english: 'Customer profile settings will appear here.',
      AppLanguage.hindi: 'ग्राहक प्रोफाइल सेटिंग्स यहां दिखाई देंगी।',
      AppLanguage.hinglish: 'Customer profile settings yahan dikhegi.',
      AppLanguage.kannada: 'ಗ್ರಾಹಕ ಪ್ರೊಫೈಲ್ ಸೆಟ್ಟಿಂಗ್‌ಗಳು ಇಲ್ಲಿ ಕಾಣಿಸುತ್ತವೆ.',
      AppLanguage.tamil: 'வாடிக்கையாளர் சுயவிவர அமைப்புகள் இங்கே தோன்றும்.',
      AppLanguage.telugu: 'కస్టమర్ ప్రొఫైల్ సెట్టింగ్‌లు ఇక్కడ కనిపిస్తాయి.',
      AppLanguage.marathi: 'ग्राहक प्रोफाइल सेटिंग्स येथे दिसतील.',
      AppLanguage.gujarati: 'ગ્રાહક પ્રોફાઇલ સેટિંગ્સ અહીં દેખાશે.',
      AppLanguage.bengali: 'গ্রাহক প্রোফাইল সেটিংস এখানে দেখা যাবে।',
      AppLanguage.punjabi: 'ਗਾਹਕ ਪ੍ਰੋਫਾਈਲ ਸੈਟਿੰਗਾਂ ਇੱਥੇ ਦਿਖਾਈ ਦੇਣਗੀਆਂ।',
      AppLanguage.kashmiri: 'گراہک پروفٲیل سیٹنگز ییَتھ ژٕھِو۔',
      AppLanguage.urdu: 'صارف پروفائل کی ترتیبات یہاں دکھائی دیں گی۔',
    },
    'comingSoon': {
      AppLanguage.english: 'Coming Soon.',
      AppLanguage.hindi: 'जल्द आ रहा है।',
      AppLanguage.hinglish: 'Jaldi aa raha hai.',
      AppLanguage.kannada: 'ಶೀಘ್ರದಲ್ಲೇ ಬರಲಿದೆ.',
      AppLanguage.tamil: 'விரைவில் வருகிறது.',
      AppLanguage.telugu: 'త్వరలో వస్తోంది.',
      AppLanguage.marathi: 'लवकरच येत आहे.',
      AppLanguage.gujarati: 'ટૂંક સમયમાં આવી રહ્યું છે.',
      AppLanguage.bengali: 'শীঘ্রই আসছে।',
      AppLanguage.punjabi: 'ਜਲਦੀ ਆ ਰਿਹਾ ਹੈ।',
      AppLanguage.kashmiri: 'جلد یِوان۔',
      AppLanguage.urdu: 'جلد آ رہا ہے۔',
    },
    'language': {
      AppLanguage.english: 'Language',
      AppLanguage.hindi: 'भाषा',
      AppLanguage.hinglish: 'Language',
      AppLanguage.kannada: 'ಭಾಷೆ',
      AppLanguage.tamil: 'மொழி',
      AppLanguage.telugu: 'భాష',
      AppLanguage.marathi: 'भाषा',
      AppLanguage.gujarati: 'ભાષા',
      AppLanguage.bengali: 'ভাষা',
      AppLanguage.punjabi: 'ਭਾਸ਼ਾ',
      AppLanguage.kashmiri: 'زَبان',
      AppLanguage.urdu: 'زبان',
    },
    'languageCount': {
      AppLanguage.english: '12 languages',
      AppLanguage.hindi: '12 भाषाएं',
      AppLanguage.hinglish: '12 languages',
      AppLanguage.kannada: '12 ಭಾಷೆಗಳು',
      AppLanguage.tamil: '12 மொழிகள்',
      AppLanguage.telugu: '12 భాషలు',
      AppLanguage.marathi: '12 भाषा',
      AppLanguage.gujarati: '12 ભાષાઓ',
      AppLanguage.bengali: '12টি ভাষা',
      AppLanguage.punjabi: '12 ਭਾਸ਼ਾਵਾਂ',
      AppLanguage.kashmiri: '12 زَبان',
      AppLanguage.urdu: '12 زبانیں',
    },
    'footer': {
      AppLanguage.english: 'Domestic • Import • Export • Pan India',
      AppLanguage.hindi: 'घरेलू • आयात • निर्यात • पूरे भारत में',
      AppLanguage.hinglish: 'Domestic • Import • Export • Pan India',
      AppLanguage.kannada: 'ದೇಶೀಯ • ಆಮದು • ರಫ್ತು • ಭಾರತದೆಲ್ಲೆಡೆ',
      AppLanguage.tamil: 'உள்நாட்டு • இறக்குமதி • ஏற்றுமதி • இந்தியா முழுவதும்',
      AppLanguage.telugu: 'దేశీయ • దిగుమతి • ఎగుమతి • పాన్ ఇండియా',
      AppLanguage.marathi: 'देशांतर्गत • आयात • निर्यात • संपूर्ण भारत',
      AppLanguage.gujarati: 'સ્થાનિક • આયાત • નિકાસ • સમગ્ર ભારત',
      AppLanguage.bengali: 'দেশীয় • আমদানি • রপ্তানি • সারা ভারত',
      AppLanguage.punjabi: 'ਘਰੇਲੂ • ਆਯਾਤ • ਨਿਰਯਾਤ • ਪੂਰੇ ਭਾਰਤ ਵਿੱਚ',
      AppLanguage.kashmiri: 'ملکی • امپورٹ • ایکسپورٹ • پٲنس پور بھارت',
      AppLanguage.urdu: 'ملکی • درآمد • برآمد • پورے بھارت میں',
    },
    'notifications': {
      AppLanguage.english: 'Notifications coming soon.',
      AppLanguage.hindi: 'नोटिफिकेशन जल्द आएंगे।',
      AppLanguage.hinglish: 'Notifications jaldi aayenge.',
      AppLanguage.kannada: 'ಅಧಿಸೂಚನೆಗಳು ಶೀಘ್ರದಲ್ಲೇ ಬರಲಿವೆ.',
      AppLanguage.tamil: 'அறிவிப்புகள் விரைவில் வரும்.',
      AppLanguage.telugu: 'నోటిఫికేషన్‌లు త్వరలో వస్తాయి.',
      AppLanguage.marathi: 'नोटिफिकेशन्स लवकरच येतील.',
      AppLanguage.gujarati: 'નોટિફિકેશન્સ ટૂંક સમયમાં આવશે.',
      AppLanguage.bengali: 'নোটিফিকেশন শীঘ্রই আসবে।',
      AppLanguage.punjabi: 'ਨੋਟੀਫਿਕੇਸ਼ਨ ਜਲਦੀ ਆਉਣਗੇ।',
      AppLanguage.kashmiri: 'نوٹیفیکیشنز چھِ جلد یِوان۔',
      AppLanguage.urdu: 'نوٹیفکیشنز جلد آئیں گے۔',
    },
    'goodMorning': {
      AppLanguage.english: 'Good Morning',
      AppLanguage.hindi: 'सुप्रभात',
      AppLanguage.hinglish: 'Good Morning',
    },
    'goodAfternoon': {
      AppLanguage.english: 'Good Afternoon',
      AppLanguage.hindi: 'नमस्कार',
      AppLanguage.hinglish: 'Good Afternoon',
    },
    'goodEvening': {
      AppLanguage.english: 'Good Evening',
      AppLanguage.hindi: 'शुभ संध्या',
      AppLanguage.hinglish: 'Good Evening',
    },
    'fullName': {
      AppLanguage.english: 'Full Name',
      AppLanguage.hindi: 'पूरा नाम',
      AppLanguage.hinglish: 'Full Name',
    },
    'nameRequired': {
      AppLanguage.english: 'Please enter your full name',
      AppLanguage.hindi: 'कृपया अपना पूरा नाम दर्ज करें',
      AppLanguage.hinglish: 'Please apna full name enter karo',
    },
    'companyNameOptional': {
      AppLanguage.english: 'Business / Company Name (optional)',
      AppLanguage.hindi: 'बिज़नेस / कंपनी का नाम (वैकल्पिक)',
      AppLanguage.hinglish: 'Business / Company Name (optional)',
    },
    'emailOptional': {
      AppLanguage.english: 'Email (optional)',
      AppLanguage.hindi: 'ईमेल (वैकल्पिक)',
      AppLanguage.hinglish: 'Email (optional)',
    },
    'invalidEmail': {
      AppLanguage.english: 'Please enter a valid email',
      AppLanguage.hindi: 'कृपया सही ईमेल दर्ज करें',
      AppLanguage.hinglish: 'Please valid email enter karo',
    },
    'saveContinue': {
      AppLanguage.english: 'Save & Continue',
      AppLanguage.hindi: 'सेव करें और आगे बढ़ें',
      AppLanguage.hinglish: 'Save karo aur Continue karo',
    },
    'profileSetupTitle': {
      AppLanguage.english: 'Complete your profile',
      AppLanguage.hindi: 'अपनी प्रोफाइल पूरी करें',
      AppLanguage.hinglish: 'Apni profile complete karo',
    },
    'profileSetupSub': {
      AppLanguage.english: 'Tell us a little about you to get started',
      AppLanguage.hindi: 'शुरू करने के लिए अपने बारे में थोड़ा बताएं',
      AppLanguage.hinglish: 'Shuru karne ke liye apne baare mein batao',
    },
    'somethingWrong': {
      AppLanguage.english: 'Something went wrong. Please try again.',
      AppLanguage.hindi: 'कुछ गलत हुआ। कृपया दोबारा कोशिश करें।',
      AppLanguage.hinglish: 'Kuch galat hua. Please dobara try karo.',
    },
    'logout': {
      AppLanguage.english: 'Logout',
      AppLanguage.hindi: 'लॉगआउट',
      AppLanguage.hinglish: 'Logout',
    },
    'driverLoginTitle': {
      AppLanguage.english: 'Driver Login',
      AppLanguage.hindi: 'ड्राइवर लॉगिन',
      AppLanguage.hinglish: 'Driver Login',
    },
    'driverLoginSub': {
      AppLanguage.english: 'Login or create your driver account',
      AppLanguage.hindi: 'लॉगिन करें या अपना ड्राइवर अकाउंट बनाएं',
      AppLanguage.hinglish: 'Login karo ya apna driver account banao',
    },
    'driverProfileTitle': {
      AppLanguage.english: 'Set up your driver profile',
      AppLanguage.hindi: 'अपनी ड्राइवर प्रोफाइल सेट करें',
      AppLanguage.hinglish: 'Apni driver profile set karo',
    },
    'driverProfileSub': {
      AppLanguage.english: 'We need a few details before you can go online',
      AppLanguage.hindi: 'ऑनलाइन होने से पहले हमें कुछ जानकारी चाहिए',
      AppLanguage.hinglish: 'Online hone se pehle thodi details chahiye',
    },
    'vehicleNumber': {
      AppLanguage.english: 'Vehicle Number',
      AppLanguage.hindi: 'वाहन नंबर',
      AppLanguage.hinglish: 'Vehicle Number',
    },
    'vehicleNumberHint': {
      AppLanguage.english: 'e.g. DL01AB1234',
      AppLanguage.hindi: 'जैसे DL01AB1234',
      AppLanguage.hinglish: 'Jaise DL01AB1234',
    },
    'vehicleNumberRequired': {
      AppLanguage.english: 'Please enter your vehicle number',
      AppLanguage.hindi: 'कृपया वाहन नंबर दर्ज करें',
      AppLanguage.hinglish: 'Please vehicle number enter karo',
    },
    'vehicleType': {
      AppLanguage.english: 'Vehicle Type',
      AppLanguage.hindi: 'वाहन प्रकार',
      AppLanguage.hinglish: 'Vehicle Type',
    },
    'pendingTitle': {
      AppLanguage.english: 'Verification in progress',
      AppLanguage.hindi: 'सत्यापन जारी है',
      AppLanguage.hinglish: 'Verification chal rahi hai',
    },
    'pendingSub': {
      AppLanguage.english: 'Our team is reviewing your details. This usually takes a short while.',
      AppLanguage.hindi: 'हमारी टीम आपकी जानकारी की समीक्षा कर रही है। इसमें थोड़ा समय लग सकता है।',
      AppLanguage.hinglish: 'Hamari team aapki details check kar rahi hai. Thoda time lag sakta hai.',
    },
    'refreshStatus': {
      AppLanguage.english: 'Check Status',
      AppLanguage.hindi: 'स्टेटस देखें',
      AppLanguage.hinglish: 'Status Check Karo',
    },
    'online': {
      AppLanguage.english: 'ONLINE',
      AppLanguage.hindi: 'ऑनलाइन',
      AppLanguage.hinglish: 'ONLINE',
    },
    'offline': {
      AppLanguage.english: 'OFFLINE',
      AppLanguage.hindi: 'ऑफलाइन',
      AppLanguage.hinglish: 'OFFLINE',
    },
    'todayEarnings': {
      AppLanguage.english: "Today's Earnings",
      AppLanguage.hindi: 'आज की कमाई',
      AppLanguage.hinglish: 'Aaj ki Kamai',
    },
    'activeTrip': {
      AppLanguage.english: 'Active Trip',
      AppLanguage.hindi: 'चालू ट्रिप',
      AppLanguage.hinglish: 'Active Trip',
    },
    'noActiveTrip': {
      AppLanguage.english: 'No active trip',
      AppLanguage.hindi: 'कोई चालू ट्रिप नहीं',
      AppLanguage.hinglish: 'Abhi koi active trip nahi hai',
    },
    'availableLoads': {
      AppLanguage.english: 'Available Loads',
      AppLanguage.hindi: 'उपलब्ध लोड',
      AppLanguage.hinglish: 'Available Loads',
    },
    'goOnlineToSee': {
      AppLanguage.english: 'Go online to see available loads',
      AppLanguage.hindi: 'लोड देखने के लिए ऑनलाइन हों',
      AppLanguage.hinglish: 'Loads dekhne ke liye online ho jao',
    },
    'viewLoad': {
      AppLanguage.english: 'View Load',
      AppLanguage.hindi: 'लोड देखें',
      AppLanguage.hinglish: 'Load Dekho',
    },
    'myTruck': {
      AppLanguage.english: 'My Truck',
      AppLanguage.hindi: 'मेरा ट्रक',
      AppLanguage.hinglish: 'Mera Truck',
    },
    'documentsKyc': {
      AppLanguage.english: 'Documents / KYC',
      AppLanguage.hindi: 'दस्तावेज़ / KYC',
      AppLanguage.hinglish: 'Documents / KYC',
    },
    'trips': {
      AppLanguage.english: 'Trips',
      AppLanguage.hindi: 'ट्रिप',
      AppLanguage.hinglish: 'Trips',
    },
    'earnings': {
      AppLanguage.english: 'Earnings',
      AppLanguage.hindi: 'कमाई',
      AppLanguage.hinglish: 'Earnings',
    },

    // ---------------- Vehicles ----------------
    'fieldRequired': {
      AppLanguage.english: 'This field is required',
      AppLanguage.hindi: 'यह जानकारी ज़रूरी है',
      AppLanguage.hinglish: 'Ye field zaroori hai',
    },
    'myVehicles': {
      AppLanguage.english: 'My Vehicles',
      AppLanguage.hindi: 'मेरे वाहन',
      AppLanguage.hinglish: 'Meri Gaadiyan',
    },
    'addVehicle': {
      AppLanguage.english: 'Add Vehicle',
      AppLanguage.hindi: 'वाहन जोड़ें',
      AppLanguage.hinglish: 'Vehicle Add Karo',
    },
    'capacityTons': {
      AppLanguage.english: 'Capacity (tons)',
      AppLanguage.hindi: 'क्षमता (टन)',
      AppLanguage.hinglish: 'Capacity (ton)',
    },
    'rcNumber': {
      AppLanguage.english: 'RC Number',
      AppLanguage.hindi: 'RC नंबर',
      AppLanguage.hinglish: 'RC Number',
    },
    'invalidVehicleNumber': {
      AppLanguage.english: 'Enter a valid vehicle number',
      AppLanguage.hindi: 'सही वाहन नंबर डालें',
      AppLanguage.hinglish: 'Sahi vehicle number daalo',
    },
    'invalidNumber': {
      AppLanguage.english: 'Enter a valid number',
      AppLanguage.hindi: 'सही संख्या डालें',
      AppLanguage.hinglish: 'Sahi number daalo',
    },
    'noVehicleTitle': {
      AppLanguage.english: 'No vehicle added yet',
      AppLanguage.hindi: 'अभी कोई वाहन नहीं जोड़ा गया',
      AppLanguage.hinglish: 'Abhi koi vehicle add nahi kiya',
    },
    'noVehicleSub': {
      AppLanguage.english: 'Add your truck to start accepting loads.',
      AppLanguage.hindi: 'लोड स्वीकार करने के लिए अपना ट्रक जोड़ें।',
      AppLanguage.hinglish: 'Loads accept karne ke liye apna truck add karo.',
    },
    'vehicleAdded': {
      AppLanguage.english: 'Vehicle added',
      AppLanguage.hindi: 'वाहन जोड़ दिया गया',
      AppLanguage.hinglish: 'Vehicle add ho gaya',
    },
    'active': {
      AppLanguage.english: 'Active',
      AppLanguage.hindi: 'सक्रिय',
      AppLanguage.hinglish: 'Active',
    },
    'inactive': {
      AppLanguage.english: 'Inactive',
      AppLanguage.hindi: 'निष्क्रिय',
      AppLanguage.hinglish: 'Inactive',
    },
    'save': {
      AppLanguage.english: 'Save',
      AppLanguage.hindi: 'सेव करें',
      AppLanguage.hinglish: 'Save Karo',
    },
    'cancel': {
      AppLanguage.english: 'Cancel',
      AppLanguage.hindi: 'रद्द करें',
      AppLanguage.hinglish: 'Cancel',
    },

    'editVehicle': {
      AppLanguage.english: 'Edit Vehicle',
      AppLanguage.hindi: 'वाहन बदलें',
      AppLanguage.hinglish: 'Vehicle Edit Karo',
    },
    'vehicleUpdated': {
      AppLanguage.english: 'Vehicle updated',
      AppLanguage.hindi: 'वाहन अपडेट हो गया',
      AppLanguage.hinglish: 'Vehicle update ho gaya',
    },
    'uploadRc': {
      AppLanguage.english: 'Upload RC photo',
      AppLanguage.hindi: 'RC फोटो अपलोड करें',
      AppLanguage.hinglish: 'RC photo upload karo',
    },
    'changeRc': {
      AppLanguage.english: 'Change photo',
      AppLanguage.hindi: 'फोटो बदलें',
      AppLanguage.hinglish: 'Photo badlo',
    },
    'rcPhotoOptional': {
      AppLanguage.english: 'RC document photo (optional)',
      AppLanguage.hindi: 'RC दस्तावेज़ फोटो (वैकल्पिक)',
      AppLanguage.hinglish: 'RC document photo (optional)',
    },
    'rcUploaded': {
      AppLanguage.english: 'RC uploaded',
      AppLanguage.hindi: 'RC अपलोड हुआ',
      AppLanguage.hinglish: 'RC upload ho gaya',
    },
    'rcMissing': {
      AppLanguage.english: 'RC photo pending',
      AppLanguage.hindi: 'RC फोटो बाकी है',
      AppLanguage.hinglish: 'RC photo baaki hai',
    },
    'camera': {
      AppLanguage.english: 'Camera',
      AppLanguage.hindi: 'कैमरा',
      AppLanguage.hinglish: 'Camera',
    },
    'gallery': {
      AppLanguage.english: 'Gallery',
      AppLanguage.hindi: 'गैलरी',
      AppLanguage.hinglish: 'Gallery',
    },
    // ---------------- Loads ----------------
    'pickupLocation': {
      AppLanguage.english: 'Pickup location',
      AppLanguage.hindi: 'पिकअप स्थान',
      AppLanguage.hinglish: 'Pickup location',
    },
    'dropLocation': {
      AppLanguage.english: 'Drop location',
      AppLanguage.hindi: 'ड्रॉप स्थान',
      AppLanguage.hinglish: 'Drop location',
    },
    'cargoType': {
      AppLanguage.english: 'Cargo type',
      AppLanguage.hindi: 'माल का प्रकार',
      AppLanguage.hinglish: 'Cargo type',
    },
    'weightTons': {
      AppLanguage.english: 'Weight (tons)',
      AppLanguage.hindi: 'वज़न (टन)',
      AppLanguage.hinglish: 'Weight (ton)',
    },
    'vehicleTypeNeeded': {
      AppLanguage.english: 'Vehicle type needed',
      AppLanguage.hindi: 'ज़रूरी वाहन का प्रकार',
      AppLanguage.hinglish: 'Kaunsi gaadi chahiye',
    },
    'budgetOptional': {
      AppLanguage.english: 'Budget ₹ (optional)',
      AppLanguage.hindi: 'बजट ₹ (वैकल्पिक)',
      AppLanguage.hinglish: 'Budget ₹ (optional)',
    },
    'pickupDate': {
      AppLanguage.english: 'Pickup date',
      AppLanguage.hindi: 'पिकअप तारीख',
      AppLanguage.hinglish: 'Pickup date',
    },
    'notesOptional': {
      AppLanguage.english: 'Notes (optional)',
      AppLanguage.hindi: 'नोट्स (वैकल्पिक)',
      AppLanguage.hinglish: 'Notes (optional)',
    },
    'loadPosted': {
      AppLanguage.english: 'Load posted',
      AppLanguage.hindi: 'लोड पोस्ट हो गया',
      AppLanguage.hinglish: 'Load post ho gaya',
    },
    'myLoads': {
      AppLanguage.english: 'My Loads',
      AppLanguage.hindi: 'मेरे लोड',
      AppLanguage.hinglish: 'Mere Loads',
    },
    'noLoadsTitle': {
      AppLanguage.english: 'No loads posted yet',
      AppLanguage.hindi: 'अभी कोई लोड पोस्ट नहीं किया',
      AppLanguage.hinglish: 'Abhi koi load post nahi kiya',
    },
    'noLoadsSub': {
      AppLanguage.english: 'Post a load and nearby truckers will accept it.',
      AppLanguage.hindi: 'लोड पोस्ट करें, ट्रक वाले उसे स्वीकार करेंगे।',
      AppLanguage.hinglish: 'Load post karo, truck wale accept karenge.',
    },
    'noAvailableLoads': {
      AppLanguage.english: 'No open loads right now',
      AppLanguage.hindi: 'अभी कोई खुला लोड नहीं है',
      AppLanguage.hinglish: 'Abhi koi open load nahi hai',
    },
    'budgetNegotiable': {
      AppLanguage.english: 'Negotiable',
      AppLanguage.hindi: 'मोलभाव योग्य',
      AppLanguage.hinglish: 'Negotiable',
    },
    'accept': {
      AppLanguage.english: 'Accept',
      AppLanguage.hindi: 'स्वीकार करें',
      AppLanguage.hinglish: 'Accept Karo',
    },
    'loadAccepted': {
      AppLanguage.english: 'Load accepted',
      AppLanguage.hindi: 'लोड स्वीकार हो गया',
      AppLanguage.hinglish: 'Load accept ho gaya',
    },
    'loadUnavailable': {
      AppLanguage.english: 'This load is no longer available',
      AppLanguage.hindi: 'यह लोड अब उपलब्ध नहीं है',
      AppLanguage.hinglish: 'Ye load ab available nahi hai',
    },
    'needVehicleFirst': {
      AppLanguage.english: 'Add an active vehicle before accepting loads',
      AppLanguage.hindi: 'लोड स्वीकार करने से पहले एक सक्रिय वाहन जोड़ें',
      AppLanguage.hinglish: 'Load accept karne se pehle ek active vehicle add karo',
    },
    'chooseVehicle': {
      AppLanguage.english: 'Choose vehicle',
      AppLanguage.hindi: 'वाहन चुनें',
      AppLanguage.hinglish: 'Vehicle choose karo',
    },
    'viewBooking': {
      AppLanguage.english: 'View booking',
      AppLanguage.hindi: 'बुकिंग देखें',
      AppLanguage.hinglish: 'Booking dekho',
    },
    'statusOpen': {
      AppLanguage.english: 'Open',
      AppLanguage.hindi: 'खुला',
      AppLanguage.hinglish: 'Open',
    },
    'statusMatched': {
      AppLanguage.english: 'Matched',
      AppLanguage.hindi: 'मैच हुआ',
      AppLanguage.hinglish: 'Matched',
    },
    'statusClosed': {
      AppLanguage.english: 'Closed',
      AppLanguage.hindi: 'बंद',
      AppLanguage.hinglish: 'Closed',
    },

    // ---------------- Bookings ----------------
    'statusAccepted': {
      AppLanguage.english: 'Accepted',
      AppLanguage.hindi: 'स्वीकृत',
      AppLanguage.hinglish: 'Accepted',
    },
    'statusPickedUp': {
      AppLanguage.english: 'Picked up',
      AppLanguage.hindi: 'पिकअप हो गया',
      AppLanguage.hinglish: 'Pickup ho gaya',
    },
    'statusInTransit': {
      AppLanguage.english: 'In transit',
      AppLanguage.hindi: 'रास्ते में',
      AppLanguage.hinglish: 'Raaste mein',
    },
    'statusDelivered': {
      AppLanguage.english: 'Delivered',
      AppLanguage.hindi: 'डिलीवर हो गया',
      AppLanguage.hinglish: 'Deliver ho gaya',
    },
    'markPickedUp': {
      AppLanguage.english: 'Mark Picked Up',
      AppLanguage.hindi: 'पिकअप हुआ मार्क करें',
      AppLanguage.hinglish: 'Picked Up Mark Karo',
    },
    'markInTransit': {
      AppLanguage.english: 'Start Trip (In Transit)',
      AppLanguage.hindi: 'यात्रा शुरू करें',
      AppLanguage.hinglish: 'Trip Start Karo',
    },
    'markDelivered': {
      AppLanguage.english: 'Mark Delivered',
      AppLanguage.hindi: 'डिलीवर हुआ मार्क करें',
      AppLanguage.hinglish: 'Delivered Mark Karo',
    },
    'statusUpdated': {
      AppLanguage.english: 'Status updated',
      AppLanguage.hindi: 'स्थिति अपडेट हो गई',
      AppLanguage.hinglish: 'Status update ho gaya',
    },
    'tripDetails': {
      AppLanguage.english: 'Trip Details',
      AppLanguage.hindi: 'यात्रा विवरण',
      AppLanguage.hinglish: 'Trip Details',
    },
    'trackBooking': {
      AppLanguage.english: 'Track Booking',
      AppLanguage.hindi: 'बुकिंग ट्रैक करें',
      AppLanguage.hinglish: 'Booking Track Karo',
    },
    'tripCompleted': {
      AppLanguage.english: 'Trip completed',
      AppLanguage.hindi: 'यात्रा पूरी हुई',
      AppLanguage.hinglish: 'Trip complete ho gayi',
    },
    'noBookingsTitle': {
      AppLanguage.english: 'No bookings yet',
      AppLanguage.hindi: 'अभी कोई बुकिंग नहीं',
      AppLanguage.hinglish: 'Abhi koi booking nahi',
    },
    'noBookingsSub': {
      AppLanguage.english: 'When a driver accepts your load, it will appear here.',
      AppLanguage.hindi: 'जब कोई ड्राइवर आपका लोड स्वीकार करेगा, यहाँ दिखेगा।',
      AppLanguage.hinglish: 'Jab driver aapka load accept karega, yahan dikhega.',
    },
    'noTrips': {
      AppLanguage.english: 'No trips yet. Accept a load to start.',
      AppLanguage.hindi: 'अभी कोई यात्रा नहीं। शुरू करने के लिए लोड स्वीकार करें।',
      AppLanguage.hinglish: 'Abhi koi trip nahi. Shuru karne ke liye load accept karo.',
    },
    'bookingNotFound': {
      AppLanguage.english: 'Booking not found',
      AppLanguage.hindi: 'बुकिंग नहीं मिली',
      AppLanguage.hinglish: 'Booking nahi mili',
    },
    'vehicle': {
      AppLanguage.english: 'Vehicle',
      AppLanguage.hindi: 'वाहन',
      AppLanguage.hinglish: 'Vehicle',
    },
    'cargo': {
      AppLanguage.english: 'Cargo',
      AppLanguage.hindi: 'माल',
      AppLanguage.hinglish: 'Cargo',
    },
    'budget': {
      AppLanguage.english: 'Budget',
      AppLanguage.hindi: 'बजट',
      AppLanguage.hinglish: 'Budget',
    },
    'notes': {
      AppLanguage.english: 'Notes',
      AppLanguage.hindi: 'नोट्स',
      AppLanguage.hinglish: 'Notes',
    },
  };

  static String get(String key, AppLanguage language) {
    return data[key]?[language] ?? data[key]?[AppLanguage.english] ?? key;
  }
}

String tr(BuildContext context, String key) =>
    T.get(key, LanguageScope.of(context));

String trLanguageName(AppLanguage language) =>
    languageInfo[language]?.nativeName ?? 'English';

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

void showLanguageSelector(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
          child: ValueListenableBuilder<AppLanguage>(
            valueListenable: languageNotifier,
            builder: (context, selected, _) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    tr(context, 'language'),
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    tr(context, 'languageCount'),
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: AppLanguage.values.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 4),
                      itemBuilder: (context, index) {
                        final lang = AppLanguage.values[index];
                        final isSelected = lang == selected;
                        return ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          tileColor:
                              isSelected ? const Color(0xFFE8F1FF) : Colors.transparent,
                          leading: CircleAvatar(
                            backgroundColor: isSelected
                                ? const Color(0xFF1565C0)
                                : const Color(0xFFF2F4F7),
                            child: Icon(
                              Icons.language_rounded,
                              color: isSelected ? Colors.white : const Color(0xFF667085),
                            ),
                          ),
                          title: Text(
                            languageInfo[lang]!.nativeName,
                            style: TextStyle(
                              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                              color: const Color(0xFF111827),
                            ),
                          ),
                          subtitle: Text(languageInfo[lang]!.englishName),
                          trailing: isSelected
                              ? const Icon(Icons.check_circle_rounded, color: Color(0xFF1565C0))
                              : null,
                          onTap: () {
                            languageNotifier.value = lang;
                            Navigator.of(sheetContext).pop();
                          },
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
    },
  );
}

class LanguageButton extends StatelessWidget {
  const LanguageButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tr(context, 'language'),
      onPressed: () => showLanguageSelector(context),
      icon: const Icon(Icons.language_rounded),
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

    final phoneNumber = '+91${_phoneController.text.trim()}';
    setState(() => _isLoading = true);

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        verificationCompleted: (PhoneAuthCredential credential) async {
          try {
            await FirebaseAuth.instance.signInWithCredential(credential);
            if (!mounted) return;

            setState(() => _isLoading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(tr(context, 'phoneVerified')), behavior: SnackBarBehavior.floating),
            );

            await UserService.markRoleSelected('customer');
            final next = await resolveCustomerStart();

            if (!mounted) return;
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => next),
              (route) => false,
            );
          } on FirebaseAuthException catch (e) {
            if (!mounted) return;
            setState(() => _isLoading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(e.message ?? tr(context, 'otpFailed')), behavior: SnackBarBehavior.floating),
            );
          } catch (_) {
            if (!mounted) return;
            setState(() => _isLoading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(tr(context, 'otpFailed')), behavior: SnackBarBehavior.floating),
            );
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          if (!mounted) return;
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.message ?? tr(context, 'otpFailed')), behavior: SnackBarBehavior.floating),
          );
        },
        codeSent: (String verificationId, int? resendToken) {
          if (!mounted) return;
          setState(() => _isLoading = false);
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => OtpVerificationScreen(
                phoneNumber: _phoneController.text.trim(),
                verificationId: verificationId,
              ),
            ),
          );
        },
        codeAutoRetrievalTimeout: (String verificationId) {},
        timeout: const Duration(seconds: 60),
      );
    } catch (e) {
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
  final bool isDriver;

  const OtpVerificationScreen({
    super.key,
    required this.phoneNumber,
    required this.verificationId,
    this.isDriver = false,
  });

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  final _otpController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _verifyOtp() async {
    final otp = _otpController.text.trim();

    if (otp.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'invalidOtp')), behavior: SnackBarBehavior.floating),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: widget.verificationId,
        smsCode: otp,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);
      if (!mounted) return;

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

      String message = tr(context, 'otpFailed');
      if (e.code == 'invalid-verification-code') {
        message = tr(context, 'invalidOtp');
      } else if (e.code == 'session-expired') {
        message = tr(context, 'otpExpired');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
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
                '${tr(context, 'otpText')}\n+91 ${widget.phoneNumber}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, height: 1.5, color: Color(0xFF667085)),
              ),
              const SizedBox(height: 35),
              TextField(
                controller: _otpController,
                keyboardType: TextInputType.number,
                maxLength: 6,
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
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(tr(context, 'otpResendSoon')), behavior: SnackBarBehavior.floating),
                  );
                },
                child: Text(
                  tr(context, 'resendOtp'),
                  style: const TextStyle(color: Color(0xFF1565C0), fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
