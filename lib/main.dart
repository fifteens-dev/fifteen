import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'screens/phone_auth_screen.dart';
import 'screens/verification_code_screen.dart';
import 'screens/invite_code_screen.dart';
import 'screens/name_input_screen.dart';
import 'screens/username_creation_screen.dart';
import 'screens/profile_setup_screen.dart';
import 'screens/music_connection_screen.dart';
import 'screens/first_timeline_screen.dart';
import 'screens/terms_of_service_screen.dart';
import 'screens/privacy_policy_screen.dart';
import 'screens/dev_tools_screen.dart';
import 'screens/home_screen.dart';
import 'screens/create_post_screen.dart';
import 'screens/photo_picker_screen.dart';
import 'screens/music_selection_screen.dart';
import 'constants/app_colors.dart';
import 'services/fcm_handler_service.dart';
import 'services/auth_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() async {
  // Flutter バインディングの初期化
  WidgetsFlutterBinding.ensureInitialized();

  // .envファイルの読み込み
  await dotenv.load(fileName: ".env");

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

  // FCM初期化（ログイン済みユーザーがいる場合）
  try {
    final authService = AuthService();
    final currentUser = authService.currentUser;
    if (currentUser != null) {
      final fcmHandler = FCMHandlerService();
      await fcmHandler.initialize(currentUser.uid);
      if (kDebugMode) {
        print('✅ FCM初期化完了: userId=${currentUser.uid}');
      }
    } else {
      if (kDebugMode) {
        print('⏭️ FCM初期化スキップ: ユーザー未ログイン');
      }
    }
  } catch (e) {
    if (kDebugMode) {
      print('⚠️ FCM初期化エラー: $e');
    }
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

/// Noto Sans（英語）+ Noto Sans JP（日本語フォールバック）のTextThemeを構築
/// 英語 → Noto Sans で描画（ラテン文字をカバー）
/// 日本語 → Noto Sans に無いグリフなので Noto Sans JP にフォールバック
TextTheme _buildTextTheme(TextTheme base) {
  final notoSansJpFamily = GoogleFonts.notoSansJp().fontFamily!;
  final fallback = [notoSansJpFamily];
  final notoSans = GoogleFonts.notoSansTextTheme(base);
  return TextTheme(
    displayLarge: notoSans.displayLarge?.copyWith(fontFamilyFallback: fallback),
    displayMedium: notoSans.displayMedium?.copyWith(fontFamilyFallback: fallback),
    displaySmall: notoSans.displaySmall?.copyWith(fontFamilyFallback: fallback),
    headlineLarge: notoSans.headlineLarge?.copyWith(fontFamilyFallback: fallback),
    headlineMedium: notoSans.headlineMedium?.copyWith(fontFamilyFallback: fallback),
    headlineSmall: notoSans.headlineSmall?.copyWith(fontFamilyFallback: fallback),
    titleLarge: notoSans.titleLarge?.copyWith(fontFamilyFallback: fallback),
    titleMedium: notoSans.titleMedium?.copyWith(fontFamilyFallback: fallback),
    titleSmall: notoSans.titleSmall?.copyWith(fontFamilyFallback: fallback),
    bodyLarge: notoSans.bodyLarge?.copyWith(fontFamilyFallback: fallback),
    bodyMedium: notoSans.bodyMedium?.copyWith(fontFamilyFallback: fallback),
    bodySmall: notoSans.bodySmall?.copyWith(fontFamilyFallback: fallback),
    labelLarge: notoSans.labelLarge?.copyWith(fontFamilyFallback: fallback),
    labelMedium: notoSans.labelMedium?.copyWith(fontFamilyFallback: fallback),
    labelSmall: notoSans.labelSmall?.copyWith(fontFamilyFallback: fallback),
  );
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
        textTheme: _buildTextTheme(ThemeData(brightness: Brightness.dark).textTheme),
        useMaterial3: true,
      ),
      initialRoute: '/', // 認証状態チェックから開始
      routes: {
        '/': (context) => const AuthGate(),
        '/phone-auth': (context) => const PhoneAuthScreen(),
        '/verification': (context) => const VerificationCodeScreen(),
        '/invite-code': (context) => const InviteCodeScreen(),
        '/name-input': (context) => const NameInputScreen(),
        '/username-creation': (context) => const UsernameCreationScreen(),
        '/profile-setup': (context) => const ProfileSetupScreen(),
        '/music-connection': (context) => const MusicConnectionScreen(),
        '/first-timeline': (context) => const FirstTimelineScreen(),
        '/terms-of-service': (context) => const TermsOfServiceScreen(),
        '/privacy-policy': (context) => const PrivacyPolicyScreen(),
        '/dev-tools': (context) => const DevToolsScreen(),
        '/home': (context) => const HomeScreen(),
        '/create-post': (context) => const CreatePostScreen(),
        '/photo-picker': (context) => const PhotoPickerScreen(),
        '/music-selection': (context) => const MusicSelectionScreen(),
      },
    );
  }
}

/// ログイン状態を確認して適切な画面に遷移するゲート
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAuthState();
    });
  }

  Future<void> _checkAuthState() async {
    if (!mounted) return;

    final authService = AuthService();
    final user = authService.currentUser;

    if (user != null) {
      // ログイン済み：Firestoreにユーザーデータがあるか確認
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (!mounted) return;
        if (doc.exists) {
          Navigator.pushReplacementNamed(context, '/home');
        } else {
          Navigator.pushReplacementNamed(context, '/invite-code');
        }
      } catch (e) {
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/phone-auth');
      }
    } else {
      // 未ログイン → 認証画面へ
      Navigator.pushReplacementNamed(context, '/phone-auth');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    );
  }
}
