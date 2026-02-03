import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_box_transform/flutter_box_transform.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/track_model.dart';
import '../models/post_model.dart';
import '../models/post_theme.dart';
import '../widgets/post_card.dart';
import '../widgets/post_card_back_info.dart';
import '../widgets/post_creation/lyrics_card_layouts.dart';
import '../services/audio_player_service.dart';
import '../services/post_service.dart';
import '../services/storage_service.dart';
import '../services/lyrics_service.dart';
import '../services/itunes_search_service.dart';
import '../utils/color_extractor.dart';
import '../utils/current_user_helper.dart';
import '../utils/photo_helper.dart';
import '../widgets/shared/user_info_badge.dart';
import 'post_photo_selection_screen.dart';

/// 投稿プレビュー画面
class PostPreviewScreen extends StatefulWidget {
  final TrackModel track;
  final LyricsData? lyricsData;
  final Future<LyricsData?>? lyricsFuture; // バックグラウンド取得用
  final bool isVibe;
  final String? vibeTopicId;
  final String? vibeTopicTitle; // Vibeお題のタイトル
  final Color? preExtractedGradientStart;
  final Color? preExtractedGradientEnd;

  const PostPreviewScreen({
    super.key,
    required this.track,
    this.lyricsData,
    this.lyricsFuture,
    this.isVibe = false,
    this.vibeTopicId,
    this.vibeTopicTitle,
    this.preExtractedGradientStart,
    this.preExtractedGradientEnd,
  });

  @override
  State<PostPreviewScreen> createState() => _PostPreviewScreenState();
}

class _PostPreviewScreenState extends State<PostPreviewScreen> with SingleTickerProviderStateMixin {
  final ImagePicker _picker = ImagePicker();
  XFile? _selectedImage;

  // 音楽再生サービス
  final AudioPlayerService _audioService = AudioPlayerService();

  // 投稿関連サービス
  final PostService _postService = PostService();
  final StorageService _storageService = StorageService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _isPosting = false;

  // 歌詞カード関連
  int _selectedLayoutIndex = 0; // 選択されたレイアウト (0-4)
  Rect _rect = const Rect.fromLTWH(0, 0, 196, 126); // 歌詞カードの位置とサイズ
  Flip _flip = Flip.none; // 反転情報
  double _cardRotation = 0.0; // 回転角度（ラジアン）
  LyricsData? _lyricsData; // 取得した歌詞データ
  Future<LyricsData?>? _lyricsFuture; // バックグラウンド取得用Future

  // 反転アニメーション用
  late AnimationController _flipController;
  late Animation<double> _flipAnimation;
  bool _showFront = true; // 初期状態は表面
  Timer? _autoFlipTimer; // 自動反転用タイマー

  // アルバムアートから抽出した色（裏面のテーマ用）
  Color? _extractedGradientStart;
  Color? _extractedGradientEnd;
  bool _isColorExtracting = false;

  // 現在のユーザー情報
  String _currentUsername = '';
  String? _currentUserIconUrl;

  @override
  void initState() {
    super.initState();
    print('🎬 PostPreviewScreen initState()');
    print('  - track: ${widget.track.trackName} by ${widget.track.artistName}');

    // 現在のユーザー情報を取得
    _loadCurrentUserInfo();

    // 歌詞データの初期化
    _lyricsData = widget.lyricsData;
    _lyricsFuture = widget.lyricsFuture;

    // バックグラウンドで取得中の歌詞があれば、それを待つ
    if (_lyricsFuture != null) {
      print('🎵 バックグラウンドで歌詞取得中... 完了を待機します');
      _lyricsFuture!.then((lyricsData) {
        if (mounted) {
          setState(() {
            _lyricsData = lyricsData;
          });
          if (lyricsData != null) {
            print('✅ バックグラウンド歌詞取得完了: ${lyricsData.source}');
          }
        }
      });
    }

    _flipController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _flipAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _flipController, curve: Curves.easeInOut),
    );

    // 事前抽出された色があれば使用、なければ色抽出を実行
    if (widget.preExtractedGradientStart != null && widget.preExtractedGradientEnd != null) {
      print('✅ 事前抽出された色を使用します');
      _extractedGradientStart = widget.preExtractedGradientStart;
      _extractedGradientEnd = widget.preExtractedGradientEnd;
    } else {
      print('⚠️ 色が未抽出のため、バックグラウンドで抽出を開始します');
      _extractColorsFromAlbumArt();
    }

    // 2秒後に自動的にカードを裏返す（裏面で音楽再生開始）
    _autoFlipTimer = Timer(const Duration(seconds: 2), () {
      if (mounted && _showFront) {
        print('⏰ 2秒経過：カードを自動的に裏返します');
        _flipCard();
      }
    });
  }

  /// 現在のユーザー情報を取得
  Future<void> _loadCurrentUserInfo() async {
    final userInfo = await CurrentUserHelper.load();
    if (mounted) {
      setState(() {
        _currentUsername = userInfo.username;
        _currentUserIconUrl = userInfo.iconUrl;
      });
    }
  }

  /// 音楽のプレビューを再生
  Future<void> _playMusicPreview() async {
    var previewUrl = widget.track.previewUrl;

    // previewURLが空の場合、iTunesから取得
    if (previewUrl == null || previewUrl.isEmpty) {
      print('⚠️ Spotify previewURLが空のため、iTunesから取得します');
      previewUrl = await _getPreviewUrlFromItunes();
    }

    if (previewUrl != null && previewUrl.isNotEmpty) {
      try {
        print('🎵 音楽プレビューを再生開始: ${widget.track.trackName}');
        await _audioService.playPreview(previewUrl);
      } catch (e) {
        print('❌ 音楽プレビュー再生エラー: $e');
      }
    } else {
      print('⚠️ プレビューURLが取得できませんでした');
    }
  }

  /// iTunesからプレビューURLを取得
  Future<String?> _getPreviewUrlFromItunes() async {
    try {
      final itunesService = ITunesSearchService();
      final trackName = widget.track.trackName;
      final artistName = widget.track.artistName;

      print('🍎 iTunes APIからプレビューURL取得: $trackName - $artistName');

      final tracks = await itunesService.searchTracks(
        '$trackName $artistName',
        limit: 1,
      );

      if (tracks.isNotEmpty && tracks.first.previewUrl != null) {
        print('✅ iTunes APIからプレビューURL取得成功');
        return tracks.first.previewUrl;
      } else {
        print('❌ iTunes APIでプレビューURLが見つかりませんでした');
        return null;
      }
    } catch (e) {
      print('❌ iTunes API取得エラー: $e');
      return null;
    }
  }

  /// アルバムアートから色を抽出
  Future<void> _extractColorsFromAlbumArt() async {
    if (_isColorExtracting) return;

    setState(() {
      _isColorExtracting = true;
    });

    try {
      final imageUrl = widget.track.albumImageUrl;
      if (imageUrl.isNotEmpty) {
        // ColorExtractor を使用して色を抽出
        final extractedColors = await ColorExtractor.extractGradientColors(imageUrl);

        if (mounted) {
          setState(() {
            _extractedGradientStart = extractedColors.$1;
            _extractedGradientEnd = extractedColors.$2;
          });
        }
      }
    } catch (e) {
      debugPrint('Color extraction error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isColorExtracting = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _autoFlipTimer?.cancel();
    _flipController.dispose();
    // 音楽再生を停止
    _audioService.stop();
    super.dispose();
  }

  /// カードを反転
  void _flipCard() {
    if (_showFront) {
      _flipController.forward();
      // 裏面に切り替え → 音楽を再生
      _playMusicPreview();
    } else {
      _flipController.reverse();
      // 表面に切り替え → 音楽を停止
      _audioService.stop();
    }
    setState(() {
      _showFront = !_showFront;
    });
  }

  /// TrackModelからダミーのPostModelを作成（プレビュー用）
  PostModel _createDummyPost() {
    final now = DateTime.now();
    return PostModel(
      postId: 'preview_post',
      userId: 'preview_user',
      username: _currentUsername.isNotEmpty ? _currentUsername : 'ユーザー',
      userIconUrl: _currentUserIconUrl,
      track: widget.track,
      likeCount: 3,
      commentCount: 3,
      likedUserIds: [],
      createdAt: now,
      updatedAt: now,
      theme: PostTheme.defaultTheme, // デフォルトテーマを使用（色抽出は PostCard 内で実行される）
    );
  }

  /// 裏面用の動的テーマを生成
  PostTheme _getDynamicThemeForBack() {
    if (_extractedGradientStart != null && _extractedGradientEnd != null) {
      return ColorExtractor.createThemeFromColors(
        _extractedGradientStart!,
        _extractedGradientEnd!,
      );
    }
    return PostTheme.defaultTheme;
  }

  /// 写真を追加
  Future<void> _pickImage() async {
    print('📷 写真選択画面へ遷移');

    // 写真選択画面へ遷移
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => PostPhotoSelectionScreen(
          track: widget.track,
          lyricsData: _lyricsData, // 現在保持している歌詞データを渡す
          lyricsFuture: _lyricsFuture, // バックグラウンド取得Futureを渡す
          isVibe: widget.isVibe,
          vibeTopicId: widget.vibeTopicId,
          vibeTopicTitle: widget.vibeTopicTitle,
        ),
      ),
    );

    // 写真選択画面から戻ったら音楽を再開
    _playMusicPreview();

    print('📷 写真選択画面から戻りました');
    print('  - result: $result');

    // 選択された写真と歌詞カード情報を設定
    if (result != null) {
      print('✅ 写真が選択されました');
      setState(() {
        _selectedImage = result['image'] as XFile?;
        _selectedLayoutIndex = result['layoutIndex'] as int? ?? 0;
        final cardPosition = result['cardPosition'] as Offset? ?? Offset.zero;
        final cardScale = result['cardScale'] as double? ?? 1.0;
        _cardRotation = result['cardRotation'] as double? ?? 0.0;

        // 歌詞データを保存
        if (result.containsKey('lyricsData')) {
          _lyricsData = result['lyricsData'] as LyricsData?;
          print('  - lyricsData: ${_lyricsData != null ? "取得済み (${_lyricsData!.source})" : "なし"}');
        }

        // rectを更新（位置とスケールから計算）
        final baseSize = _getCardSizeBack();
        _rect = Rect.fromLTWH(
          cardPosition.dx,
          cardPosition.dy,
          baseSize.width * cardScale,
          baseSize.height * cardScale,
        );
      });
      print('  - layoutIndex: $_selectedLayoutIndex');
      print('  - rect: $_rect');
      print('  - cardRotation: $_cardRotation');
      print('  - image: ${_selectedImage != null ? "あり" : "なし"}');
    } else {
      print('❌ 写真の選択がキャンセルされました');
    }
  }

  /// 投稿確認ダイアログを表示
  Future<bool> _showPostConfirmDialog() async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        title: const Text(
          '投稿しますか？',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: const Text(
          'この内容で投稿します。よろしいですか？',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 14,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'キャンセル',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              '投稿する',
              style: TextStyle(
                color: Color(0xFF5D8FFF),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    ) ?? false;
  }

  /// 投稿を完了
  Future<void> _onPost() async {
    print('🚀 _onPost()が呼ばれました');

    // 確認ダイアログを表示
    print('📋 確認ダイアログを表示中...');
    final confirmed = await _showPostConfirmDialog();
    print('✅ ダイアログ結果: $confirmed');

    if (!confirmed) {
      print('❌ ユーザーがキャンセルしました');
      return;
    }

    if (_isPosting) {
      print('⚠️ 既に投稿処理中です');
      return;
    }

    print('📝 投稿処理を開始します');
    setState(() {
      _isPosting = true;
    });

    try {
      final currentUser = _auth.currentUser;
      final userId = currentUser?.uid ?? 'test_user_temp';
      // _loadCurrentUserInfoで取得済みのユーザー情報を使用
      final username = _currentUsername.isNotEmpty
          ? _currentUsername
          : currentUser?.displayName ?? 'ユーザー';
      final userIconUrl = _currentUserIconUrl;
      print('👤 ユーザー情報: userId=$userId, username=$username, userIconUrl=$userIconUrl');

      // 写真を処理（PhotoHelperを使用）
      String? photoUrl;
      if (_selectedImage != null) {
        try {
          photoUrl = await PhotoHelper.processPhoto(
            image: _selectedImage!,
            userId: userId,
            storageService: _storageService,
          );
        } catch (e) {
          print('❌ 写真処理エラー: $e');
          print('⚠️ 写真なしで投稿を続行します');
          photoUrl = null;
        }
      } else {
        print('⚠️ 写真が選択されていません');
      }

      // TrackModelをMapに変換
      print('🎵 楽曲データを変換中...');
      final trackData = widget.track.toMap();
      print('📋 楽曲データ: $trackData');

      // アルバムアートから色を抽出してテーマを生成
      PostTheme? extractedTheme;
      try {
        print('🎨 アルバムアートから色を抽出中...');
        final albumArtUrl = widget.track.albumImageUrl;
        extractedTheme = await ColorExtractor.extractThemeFromAlbumArt(albumArtUrl);

        if (extractedTheme != null) {
          print('✅ 色抽出完了: ${extractedTheme.gradientStart} → ${extractedTheme.gradientEnd}');
          print('   textColor: ${extractedTheme.textColor}, iconColor: ${extractedTheme.iconColor}');
        }
      } catch (e) {
        print('⚠️  色抽出エラー（デフォルトテーマを使用）: $e');
        extractedTheme = null; // エラー時はnull（Firestoreでデフォルトテーマが使われる）
      }

      // 投稿を作成
      print('💾 Firestoreに投稿を保存中...');
      print('  - userId: $userId');
      print('  - username: $username');
      print('  - photoUrl: ${PhotoHelper.formatPhotoUrlForLog(photoUrl)}');
      print('  - layoutIndex: $_selectedLayoutIndex');
      print('  - rect: $_rect');

      // rectからスケールを計算
      final baseSize = _getCardSizeBack();
      final cardScale = _rect.width / baseSize.width;

      print('📝 投稿データ: isVibe=${widget.isVibe}, vibeTopicId=${widget.vibeTopicId}, vibeTopicTitle=${widget.vibeTopicTitle}');
      final postId = await _postService.createPost(
        userId: userId,
        username: username,
        userIconUrl: userIconUrl,
        trackData: trackData,
        photoUrl: photoUrl,
        selectedLayoutIndex: _selectedLayoutIndex,
        cardPositionX: _rect.left,
        cardPositionY: _rect.top,
        cardScale: cardScale,
        cardRotation: _cardRotation,
        isVibe: widget.isVibe,
        vibeTopicId: widget.vibeTopicId,
        vibeTopicTitle: widget.vibeTopicTitle,
        theme: extractedTheme, // 抽出した色テーマを保存
      );
      print('✅ 投稿作成完了: postId=$postId');

      if (mounted) {
        print('🎉 投稿成功！ホーム画面に戻ります');
        setState(() {
          _isPosting = false;
        });

        // ホーム画面に戻る
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/home',
          (route) => false,
        );
      }
    } catch (e, stackTrace) {
      print('❌ 投稿エラー: $e');
      print('📍 スタックトレース: $stackTrace');

      if (mounted) {
        setState(() {
          _isPosting = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('投稿に失敗しました: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    print('🎨 PostPreviewScreen build()呼び出し');
    print('  - _selectedImage: ${_selectedImage != null ? "選択済み" : "未選択"}');
    print('  - _isPosting: $_isPosting');
    print('  - _selectedLayoutIndex: $_selectedLayoutIndex');
    print('  - _rect: $_rect');

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Column(
          children: [
            // ヘッダー
            _buildHeader(),

            // 投稿カードプレビュー（スクロール可能）
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: AnimatedBuilder(
                      animation: _flipAnimation,
                      builder: (context, child) {
                        final angle = _flipAnimation.value * pi;
                        final isFront = angle < pi / 2;

                        return Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()
                            ..setEntry(3, 2, 0.001)
                            ..rotateY(angle),
                          child: isFront
                              ? PostCard(
                                  post: _createDummyPost(),
                                  audioService: _audioService,
                                  showFrontOnly: true, // 表面のみ表示
                                  hideReactionCounts: true, // プレビューではカウント非表示
                                  onCardTap: _flipCard, // プレビュー画面の反転処理を実行
                                  preExtractedGradientStart: _extractedGradientStart, // 事前抽出した色を渡す
                                  preExtractedGradientEnd: _extractedGradientEnd, // 事前抽出した色を渡す
                                )
                              : _buildBackCard(),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// ヘッダー
  Widget _buildHeader() {
    // 写真が選択されているかチェック
    final bool isPhotoSelected = _selectedImage != null;
    final bool canPost = isPhotoSelected && !_isPosting;

    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 19),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 戻るボタン（矢印）- 投稿中は無効化
          GestureDetector(
            onTap: _isPosting ? null : () => Navigator.pop(context),
            child: Icon(
              Icons.arrow_back_ios,
              color: _isPosting ? Colors.grey : Colors.white,
              size: 20,
            ),
          ),

          // タイトル
          const Text(
            '新規投稿',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),

          // 投稿するボタン（写真が選択されている場合のみ有効、投稿中はローディング）
          _isPosting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Color(0xFF5D8FFF),
                    ),
                  ),
                )
              : GestureDetector(
                  onTap: canPost
                      ? () {
                          print('🔘 投稿するボタンがタップされました');
                          print('  - isPhotoSelected: $isPhotoSelected');
                          print('  - _isPosting: $_isPosting');
                          print('  - canPost: $canPost');
                          _onPost();
                        }
                      : () {
                          print('⚠️ 投稿ボタンが無効です');
                          print('  - isPhotoSelected: $isPhotoSelected');
                          print('  - _isPosting: $_isPosting');
                          print('  - canPost: $canPost');
                        },
                  child: Text(
                    '投稿する',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: canPost
                          ? const Color(0xFF5D8FFF)
                          : Colors.grey,
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  /// 投稿カード（裏面） - Figmaデザインに基づく
  Widget _buildBackCard() {
    const cardHeight = 644.0;
    const photoHeight = 484.0; // 写真エリアの高さ

    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()..rotateY(pi), // 裏面なので反転
      child: GestureDetector(
        onTap: _flipCard, // タップで表面に戻る
        child: Container(
          width: 363,
          height: cardHeight,
          decoration: BoxDecoration(
            color: const Color(0xFF121212),
            borderRadius: BorderRadius.circular(18),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              children: [
                // 上部エリア（写真選択部分）
                Positioned(
                  left: 0,
                  top: 0,
                  width: 363,
                  height: photoHeight,
                  child: _buildPhotoSectionBack(),
                ),

                // 下部エリア（楽曲情報）- bottomから配置してグラデーションが写真エリアと重なるようにする
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _buildInfoSectionBack(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 写真セクション（裏面）
  Widget _buildPhotoSectionBack() {
    return Stack(
      children: [
        // 白い枠
        Positioned(
          left: 0,
          top: 0,
          width: 363,
          height: 484,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 0.5),
              borderRadius: BorderRadius.circular(18),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(18.0),
                topRight: Radius.circular(18.0),
              ),
              child: Stack(
                children: [
                  // 選択された写真または写真追加ボタン
                  if (_selectedImage != null)
                    Positioned.fill(
                      child: kIsWeb
                          ? Image.network(
                              _selectedImage!.path,
                              fit: BoxFit.cover,
                            )
                          : Image.file(
                              File(_selectedImage!.path),
                              fit: BoxFit.cover,
                            ),
                    )
                  else
                    _buildAddPhotoButtonBack(),

                  // 歌詞カードプレビュー（写真選択後）
                  if (_selectedImage != null) _buildLyricsCardBack(),
                ],
              ),
            ),
          ),
        ),

        // ユーザー情報（左上）
        Positioned(
          left: 15,
          top: 15,
          child: _buildUserInfoBack(),
        ),
      ],
    );
  }

  /// 写真追加ボタン（裏面）
  Widget _buildAddPhotoButtonBack() {
    return Container(
      color: const Color(0xFF121212),
      child: Center(
        child: GestureDetector(
          onTap: _pickImage,
          child: Container(
            width: 120,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // +アイコン
                Container(
                  width: 25,
                  height: 25,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black,
                  ),
                  child: const Icon(
                    Icons.add,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 8),
                // テキスト
                const Text(
                  '写真を追加',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                    fontFamily: 'Noto Sans',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// ユーザー情報（裏面）
  Widget _buildUserInfoBack() {
    return UserInfoBadge(
      username: _currentUsername.isNotEmpty ? _currentUsername : 'ユーザー',
      iconUrl: _currentUserIconUrl,
      hashtagText: widget.isVibe && widget.vibeTopicTitle != null
          ? '#${widget.vibeTopicTitle}'
          : null,
    );
  }

  /// 情報セクション（裏面）- ホーム画面のPostCardと同じデザインを引き継ぐ
  Widget _buildInfoSectionBack() {
    final theme = _getDynamicThemeForBack();

    return PostCardBackInfo(
      track: widget.track,
      theme: theme,
      likeCount: 3,
      commentCount: 3,
      isLiked: false,
      showCounts: false, // プレビュー画面ではカウント非表示
      onLike: () {
        // プレビュー画面ではアクションなし
      },
      onComment: () {
        // プレビュー画面ではアクションなし
      },
      onAdd: () {
        // プレビュー画面ではアクションなし
      },
    );
  }



  /// 歌詞カードプレビュー（裏面）
  /// 歌詞カード（裏面・固定表示）
  Widget _buildLyricsCardBack() {
    // 共通ウィジェットを使用してレイアウトを表示
    final layoutType = LyricsCardLayout.getLayoutType(_selectedLayoutIndex);

    // rectから位置とスケールを取得
    final baseSize = _getCardSizeBack();
    final cardScale = _rect.width / baseSize.width;

    // 歌詞テキストを取得
    String? lyricsText;
    if (_lyricsData != null) {
      final lyricsService = LyricsService();
      lyricsText = lyricsService.truncateLyrics(
        _lyricsData!.plainLyrics,
        maxLines: 4,
      );
    }

    // 固定表示（操作不可）
    return Positioned(
      left: _rect.left,
      top: _rect.top,
      child: Transform.scale(
        scale: cardScale,
        alignment: Alignment.topLeft,
        child: Transform.rotate(
          angle: _cardRotation,
          alignment: Alignment.center,
          child: LyricsCardLayout(
            layoutType: layoutType,
            track: widget.track,
            lyricsText: lyricsText,
          ),
        ),
      ),
    );
  }

  /// カードサイズを取得（裏面用）
  Size _getCardSizeBack() {
    switch (_selectedLayoutIndex) {
      case 0:
        return const Size(196, 126); // レイアウト1
      case 1:
        return const Size(105, 147); // レイアウト2
      case 2:
        return const Size(172, 42); // レイアウト3
      case 3:
        return const Size(140, 152); // レイアウト4
      case 4:
        return const Size(130, 61); // レイアウト5
      default:
        return const Size(196, 126);
    }
  }


  // === 以下のレイアウトメソッド（_buildLayout1Back ~ _buildLayout5Back）は ===
  // === LyricsCardLayout 共通ウィジェットに移行済み ===
  // === lib/widgets/post_creation/lyrics_card_layouts.dart を参照 ===
}
