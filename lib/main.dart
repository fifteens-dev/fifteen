import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
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
import 'screens/home_screen.dart';
import 'screens/create_post_screen.dart';
import 'screens/photo_picker_screen.dart';
import 'screens/music_selection_screen.dart';
import 'constants/app_colors.dart';
import 'services/fcm_handler_service.dart';
import 'services/auth_service.dart';
import 'services/settings_service.dart';
import 'services/post_service.dart';
import 'services/user_service.dart';
import 'models/post_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// バックグラウンドFCMハンドラー（top-level 必須・runApp前に登録する）
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (kDebugMode) {
    print('🔔 バックグラウンドメッセージ受信: ${message.messageId}');
  }
}

/// アプリ全体で使用するNavigatorKey（FCM通知タップ時の画面遷移用）
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

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

  // バックグラウンドメッセージハンドラーをログイン状態に関わらず登録
  // （runApp より前・top-level 関数で登録する必要がある）
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // iOS: フォアグラウンド時も通知バナー・サウンドを表示するよう設定
  // （アプリ内カスタムバナーに加えてシステム通知も表示する）
  await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );

  // FCM初期化（ログイン済みユーザーがいる場合）
  try {
    final authService = AuthService();
    final currentUser = authService.currentUser;
    if (currentUser != null) {
      SettingsService().configure(currentUser.uid);
      final fcmHandler = FCMHandlerService();
      await fcmHandler.initialize(currentUser.uid, navigatorKey: navigatorKey);
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

/// OS標準フォント（iOS: SF Pro, Android: Roboto）をそのまま使用
TextTheme _buildTextTheme(TextTheme base) {
  return base;
}

class FifteenApp extends StatelessWidget {
  const FifteenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: '15s',
      debugShowCheckedModeBanner: false,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.noScaling,
        ),
        child: child!,
      ),
      locale: const Locale('ja', 'JP'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ja', 'JP'),
      ],
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
      SettingsService().configure(user.uid);
      // ログイン済み：Firestoreにユーザーデータがあるか確認
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (!mounted) return;
        if (doc.exists) {
          // 登録進捗に応じてナビゲート
          final data = doc.data() ?? {};
          final username = data['username'] as String?;
          final name = data['name'] as String?;

          if (username != null && username.isNotEmpty) {
            // ホーム画面に移動する前に投稿データを事前取得
            List<PostModel>? initialPosts;
            try {
              final userService = UserService();
              final postService = PostService();
              final userModel = await userService.getUser(user.uid);
              final followingIds = userModel?.following ?? [];
              final allTargetIds = [...followingIds, user.uid];
              initialPosts = await postService.getPostsForFollowing(
                  allTargetIds, limit: 50);
            } catch (_) {
              // 取得失敗時はホーム画面側でリロード
            }
            if (!mounted) return;
            Navigator.pushReplacement(
              context,
              PageRouteBuilder(
                pageBuilder: (_, __, ___) =>
                    HomeScreen(initialPosts: initialPosts),
                transitionDuration: Duration.zero,
                reverseTransitionDuration: Duration.zero,
              ),
            );
          } else if (name != null && name.isNotEmpty) {
            Navigator.pushReplacementNamed(
              context,
              '/username-creation',
              arguments: {'name': name},
            );
          } else {
            Navigator.pushReplacementNamed(context, '/name-input');
          }
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
      backgroundColor: Color(0xFF121212),
      body: Center(
        child: Text(
          '15s',
          style: TextStyle(
            color: Colors.white,
            fontSize: 42,
            fontWeight: FontWeight.w700,
            letterSpacing: -1.0,
          ),
        ),
      ),
    );
  }
}
