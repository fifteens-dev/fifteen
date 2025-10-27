import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/phone_auth_screen.dart';
import 'screens/verification_code_screen.dart';
import 'screens/invite_code_screen.dart';
import 'screens/name_input_screen.dart';
import 'screens/username_creation_screen.dart';
import 'screens/profile_setup_screen.dart';
import 'screens/terms_of_service_screen.dart';
import 'screens/privacy_policy_screen.dart';
import 'constants/app_colors.dart';

void main() {
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
      initialRoute: '/',
      routes: {
        '/': (context) => const PhoneAuthScreen(),
        '/verification': (context) => const VerificationCodeScreen(),
        '/invite-code': (context) => const InviteCodeScreen(),
        '/name-input': (context) => const NameInputScreen(),
        '/username-creation': (context) => const UsernameCreationScreen(),
        '/profile-setup': (context) => const ProfileSetupScreen(),
        '/terms-of-service': (context) => const TermsOfServiceScreen(),
        '/privacy-policy': (context) => const PrivacyPolicyScreen(),
      },
    );
  }
}
