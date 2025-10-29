import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'screens/phone_auth_screen.dart';
import 'screens/verification_code_screen.dart';
import 'screens/invite_code_screen.dart';
import 'screens/name_input_screen.dart';
import 'screens/username_creation_screen.dart';
import 'screens/profile_setup_screen.dart';
import 'screens/terms_of_service_screen.dart';
import 'screens/privacy_policy_screen.dart';
import 'screens/dev_tools_screen.dart';
import 'constants/app_colors.dart';

void main() async {
  // Flutter バインディングの初期化
  WidgetsFlutterBinding.ensureInitialized();

  // Firebaseの初期化（Webのみ、AndroidとiOSは自動初期化される）
  if (kIsWeb) {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: "AIzaSyDCmLAnjE41x_rHsf-8AoYwQ3IOQz2-Z6w",
        authDomain: "fifteens-39cfe.firebaseapp.com",
        projectId: "fifteens-39cfe",
        storageBucket: "fifteens-39cfe.firebasestorage.app",
        messagingSenderId: "344562966483",
        appId: "1:344562966483:web:73af472946c9242529d926",
        measurementId: "G-GEGD7ZZ950",
      ),
    );
  } else {
    await Firebase.initializeApp();
  }

  // ステータスバーの設定
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const FifteenApp());
}

class FifteenApp extends StatelessWidget {
  const FifteenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '15s',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.buttonPrimary,
          surface: AppColors.surface,
        ),
        useMaterial3: true,
      ),
      initialRoute: kDebugMode ? '/dev-tools' : '/',
      routes: {
        '/': (context) => const PhoneAuthScreen(),
        '/verification': (context) => const VerificationCodeScreen(),
        '/invite-code': (context) => const InviteCodeScreen(),
        '/name-input': (context) => const NameInputScreen(),
        '/username-creation': (context) => const UsernameCreationScreen(),
        '/profile-setup': (context) => const ProfileSetupScreen(),
        '/terms-of-service': (context) => const TermsOfServiceScreen(),
        '/privacy-policy': (context) => const PrivacyPolicyScreen(),
        '/dev-tools': (context) => const DevToolsScreen(),
      },
    );
  }
}
