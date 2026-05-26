import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'providers/post_ui_state.dart';
import 'providers/current_user_provider.dart';
import 'providers/saved_items_provider.dart';
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
import 'services/deep_link_service.dart';
import 'services/auth_service.dart';
import 'services/settings_service.dart';
import 'services/post_service.dart';
import 'services/font_service.dart';
import 'tutorial/tutorial.dart';
import 'services/user_service.dart';
import 'services/vibe_topic_service.dart';
import 'models/post_model.dart';

/// バックグラウンドFCMハンドラー（top-level 必須・runApp前に登録する）
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (kDebugMode) {
    print('🔔 バックグラウンドメッセージ受信: ${message.messageId}');
  }
}

/// アプリ全体で使用するNavigatorKey（FCM通知タップ時の画面遷移用）
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// ルート変化を監視するオブザーバー（画面復帰時のデータ更新に使用）
final RouteObserver<ModalRoute<void>> routeObserver = RouteObserver<ModalRoute<void>>();

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

  // ステータスバーの設定
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  // SF Pro フォントをロード（iOS のみ・失敗時はフォールバック）
  await FontService.loadSFPro();

  // チュートリアル状態をロード（永続化されたステップを復元）
  await TutorialController.instance.ensureInitialized();

  // runApp を先に呼んで「15s」をすぐ表示し、FCM初期化はバックグラウンドで実行
  runApp(const FifteenApp());
  _initializePostLaunch();
}

/// runApp後にバックグラウンドで実行するFCM等の初期化処理
/// 黒い画面を減らすため、runApp前に await しない
Future<void> _initializePostLaunch() async {
  // iOS: フォアグラウンド時も通知バナー・サウンドを表示するよう設定
  await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );

  // ディープリンクハンドラを初期化（Instagram Storiesなどからの帰還リンク対応）
  await DeepLinkService().initialize(navigatorKey);

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
}

/// iOS: Hiragino Sans を明示指定し全ウェイト(W0-W9)を有効化
/// Android: Noto Sans JP にフォールバック
TextTheme _buildTextTheme(TextTheme base) {
  // iOS: SF Pro（ネイティブロード済み）、Android: Inter
  final fontFamily = Platform.isIOS ? 'SFPro' : GoogleFonts.inter().fontFamily;
  return base.apply(
    fontFamily: fontFamily,
    fontFamilyFallback: ['Hiragino Sans', 'Noto Sans JP', 'Roboto'],
  );
}

class FifteenApp extends StatelessWidget {
  const FifteenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => PostUIState()),
        ChangeNotifierProvider(create: (_) => CurrentUserProvider()..ensureLoaded()),
        ChangeNotifierProvider(create: (_) => SavedItemsProvider()),
      ],
      child: MaterialApp(
      navigatorKey: navigatorKey,
      navigatorObservers: [routeObserver],
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
        fontFamily: Platform.isIOS ? 'SFPro' : GoogleFonts.inter().fontFamily,
        fontFamilyFallback: const ['Hiragino Sans', 'Noto Sans JP', 'Roboto'],
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
      ),
    );
  }
}

/// Vibeデータ（お題＋ランキング）を取得するヘルパー
Future<Map<String, dynamic>> _fetchVibeData(
    VibeTopicService vibeTopicService, PostService postService) async {
  try {
    final topic = await vibeTopicService.getTodaysTopic();
    if (topic == null) return {'topic': null, 'ranking': []};
    final ranking = await postService.calculateVibeRanking(
      topic.topicId,
      DateTime.now(),
      limit: 10,
    );
    return {'topic': topic, 'ranking': ranking};
  } catch (_) {
    return {'topic': null, 'ranking': []};
  }
}

/// ログイン状態を確認して適切な画面に遷移するゲート
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  // スプラッシュ開始時刻（最小表示時間の計算用）
  final DateTime _splashStart = DateTime.now();
  static const _minSplashDuration = Duration(milliseconds: 500);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAuthState();
    });
  }

  /// 最小表示時間に達するまで待機
  Future<void> _waitForMinSplash() async {
    final elapsed = DateTime.now().difference(_splashStart);
    final remaining = _minSplashDuration - elapsed;
    if (remaining > Duration.zero) await Future.delayed(remaining);
  }

  Future<void> _checkAuthState() async {
    if (!mounted) return;

    final authService = AuthService();
    final user = authService.currentUser;

    if (user != null) {
      SettingsService().configure(user.uid);
      // ログイン済み：Firestoreにユーザーデータがあるか確認（1回のみ）
      try {
        final userService = UserService();
        final userModel = await userService.getUser(user.uid);

        if (!mounted) return;
        if (userModel != null) {
          // 登録完了済みならホーム、未完了なら認証フロー先頭から再開
          final username = userModel.username;

          if (username != null && username.isNotEmpty) {
            // ホーム画面に移動する前に投稿データを事前取得
            List<PostModel>? initialPosts;
            Map<String, dynamic>? initialVibeData;
            bool initialHasPostedToday = false;
            try {
              final postService = PostService();
              final vibeTopicService = VibeTopicService();
              final followingIds = userModel.following;
              final allTargetIds = [...followingIds, user.uid];

              // 投稿・Vibe・今日の投稿チェックを並列取得
              final results = await Future.wait([
                postService.getPostsForFollowing(allTargetIds, limit: 50),
                _fetchVibeData(vibeTopicService, postService),
                postService.hasUserPostedToday(user.uid),
              ]);
              initialPosts = results[0] as List<PostModel>;
              initialVibeData = results[1] as Map<String, dynamic>;
              initialHasPostedToday = results[2] as bool;
            } catch (_) {
              // 取得失敗時はホーム画面側でリロード
            }
            await _waitForMinSplash();
            if (!mounted) return;
            Navigator.pushReplacement(
              context,
              PageRouteBuilder(
                pageBuilder: (_, __, ___) => HomeScreen(
                  initialPosts: initialPosts,
                  initialVibeData: initialVibeData,
                  initialUserModel: userModel,
                  initialHasPostedToday: initialHasPostedToday,
                ),
                transitionDuration: Duration.zero,
                reverseTransitionDuration: Duration.zero,
              ),
            );
          } else {
            // 登録未完了 → 認証フロー先頭（電話番号入力）から開始
            await _waitForMinSplash();
            if (!mounted) return;
            Navigator.pushReplacementNamed(context, '/phone-auth');
          }
        } else {
          // userDocなし（Firebase Auth セッションのみ） → 認証フロー先頭から
          await _waitForMinSplash();
          if (!mounted) return;
          Navigator.pushReplacementNamed(context, '/phone-auth');
        }
      } catch (e) {
        await _waitForMinSplash();
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/phone-auth');
      }
    } else {
      // 未ログイン → 認証画面へ
      await _waitForMinSplash();
      if (!mounted) return;
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
