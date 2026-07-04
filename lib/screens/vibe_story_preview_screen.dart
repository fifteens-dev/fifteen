import 'dart:math';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';

import '../models/post_model.dart';
import '../models/track_model.dart';
import '../services/adl_service.dart';
import '../services/post_service.dart';
import '../services/storage_service.dart';
import '../services/user_service.dart';
import '../services/vibe_topic_service.dart';
import '../utils/photo_helper.dart';
import '../utils/two_finger_rotation_tracker.dart';
import '../widgets/post_creation/lyrics_card_layouts.dart';
import '../widgets/common/app_toast.dart';
import 'vibe_story_photo_grid_overlay.dart';

/// Vibe ストーリー投稿の「公開範囲選択 / 投稿プレビュー」画面。
///
/// Figma: node 4546:9255
/// - 背景: アルバムアートを強くぼかしたもの（opacity 0.75 / blur 29px）
/// - 中央: アルバムアート 236×236（shadow + 角丸 8px）
/// - 中央下: 楽曲名 + アーティスト名
/// - 左上: バツ（閉じる）ボタン
/// - 右上: 楽曲アイコン（円形）
/// - 左下: 投稿者アイコン（白枠 3px 角丸）
/// - 下部: 「全体に公開」(青→ピンクグラデ) / 「フォロワーのみ」(ダーク) ボタン
///
/// 表示は `pushWithSlideUp` で下からスライドインさせる。
class VibeStoryPreviewScreen extends StatefulWidget {
  final TrackModel track;
  final String? authorIconUrl;
  final ValueChanged<String>? onAudienceSelected; // 'public' / 'followers'

  const VibeStoryPreviewScreen({
    super.key,
    required this.track,
    this.authorIconUrl,
    this.onAudienceSelected,
  });

  @override
  State<VibeStoryPreviewScreen> createState() => _VibeStoryPreviewScreenState();

  /// 下からスライドインで遷移する便利メソッド
  static Future<T?> pushWithSlideUp<T>(
    BuildContext context, {
    required TrackModel track,
    String? authorIconUrl,
    ValueChanged<String>? onAudienceSelected,
  }) {
    return Navigator.of(context).push<T>(
      PageRouteBuilder<T>(
        transitionDuration: const Duration(milliseconds: 280),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        opaque: false,
        pageBuilder: (_, __, ___) => VibeStoryPreviewScreen(
          track: track,
          authorIconUrl: authorIconUrl,
          onAudienceSelected: onAudienceSelected,
        ),
        transitionsBuilder: (_, anim, __, child) {
          final curved = CurvedAnimation(
            parent: anim,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeIn,
          );
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          );
        },
      ),
    );
  }
}

class _VibeStoryPreviewScreenState extends State<VibeStoryPreviewScreen> {
  /// 投稿者アイコン枠から選択された写真（写真が選ばれていれば背景全面に表示）
  Uint8List? _selectedPhoto;

  /// 端末フォトライブラリの最新写真サムネ（左下ボタンの未選択時デフォルト）。
  /// 権限未許可なら null のまま。
  Uint8List? _latestGalleryThumb;

  // 投稿時に使うサービス
  final PostService _postService = PostService();
  final StorageService _storageService = StorageService();
  final VibeTopicService _vibeTopicService = VibeTopicService();
  final UserService _userService = UserService();
  bool _isPosting = false;

  // ── カード（アルバム + 楽曲名 + アーティスト名 を 1 つのグループとして扱う） ──
  //
  // 投稿フロー [post_final_preview_screen] と同じ仕様:
  //   - 中心座標 `cardCenter`、`cardScale`、`cardRotation` の 3 値で管理
  //   - 1 本指で pan（focalPointDelta × 0.7）
  //   - 2 本指で scale + rotation。最初 10° は回転ロック、水平で吸着など
  //
  // Vibe Story カードの基準サイズは投稿フローと統一する。
  // [LyricsCardLayout.largeAlbumArt] (index=1) のベース 105×147 をそのまま使い、
  // 初期表示では「ストーリー Figma の 236×286 相当」になるよう cardScale を約 2.25 倍に。
  // → 保存値 (cardPositionX/Y/Scale/Rotation/selectedLayoutIndex=1) はそのまま
  //    PostCard 裏面の歌詞カード描画で再現される。
  static const double _cardW = 105.0;
  static const double _cardH = 147.0;
  static const double _frameW = 402.0;
  static const double _frameH = 715.0;
  // largeAlbumArt の初期表示サイズ: 236 / 105 ≈ 2.248
  static const double _initialCardScale = 236.0 / 105.0;
  // Figma の初期中心: アルバム top=203, height=236 → 中央 y=321; 加えてテキスト分を含めた中心 y=346
  static const Offset _defaultCardCenter = Offset(201.0, 346.0);

  Offset _cardCenter = _defaultCardCenter;
  double _cardScale = _initialCardScale;
  double _cardRotation = 0.0;

  // 背景写真の pan/scale
  Offset _imageOffset = Offset.zero;
  double _imageScale = 1.0;

  // ── ジェスチャー一時値（投稿フロー仕様をそのまま移植） ──
  bool _isPhotoGestureMode = false;
  Offset _photoStartOffset = Offset.zero;
  double _photoStartScale = 1.0;
  Offset _photoStartFocalPoint = Offset.zero;

  double _startScale = 1.0;
  double _startRotation = 0.0;
  bool _isTwoFingerAccepted = false;

  // 2 指角度のラップ補正 + 初期 10° ロック処理は共通ユーティリティに委譲。
  final TwoFingerRotationTracker _rotationTracker = TwoFingerRotationTracker();
  final InitialRotationLock _rotationLock = InitialRotationLock();

  TrackModel get track => widget.track;
  String? get authorIconUrl => widget.authorIconUrl;
  ValueChanged<String>? get onAudienceSelected => widget.onAudienceSelected;

  @override
  void initState() {
    super.initState();
    _loadLatestGalleryThumb();
  }

  /// 端末フォトライブラリの最新写真サムネを取得。
  /// 権限がまだ問い合わせ済みでない場合はプロンプトを出さず、既に許可済みの
  /// ときだけ読み込む（初回はグリッドを開いたタイミングで許可を取る想定）。
  Future<void> _loadLatestGalleryThumb() async {
    try {
      final state = await PhotoManager.getPermissionState(
        requestOption: const PermissionRequestOption(),
      );
      if (!state.isAuth && !state.hasAccess) return;
      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        filterOption: FilterOptionGroup(
          imageOption: const FilterOption(
            sizeConstraint: SizeConstraint(ignoreSize: true),
          ),
          orders: const [
            OrderOption(type: OrderOptionType.createDate, asc: false),
          ],
        ),
      );
      if (albums.isEmpty) return;
      final assets = await albums.first.getAssetListRange(start: 0, end: 1);
      if (assets.isEmpty) return;
      final thumb = await assets.first
          .thumbnailDataWithSize(const ThumbnailSize(120, 120));
      if (!mounted || thumb == null) return;
      setState(() => _latestGalleryThumb = thumb);
    } catch (_) {
      // 権限なし・端末環境差で失敗しても静かに投稿者アイコンへフォールバック
    }
  }

  Future<void> _openPhotoPicker() async {
    await VibeStoryPhotoGridOverlay.show<void>(
      context,
      onPhotoSelected: (bytes) {
        if (mounted) {
          setState(() {
            _selectedPhoto = bytes;
            // 新しい写真に切り替わったら写真の pan/scale をリセット
            _imageOffset = Offset.zero;
            _imageScale = 1.0;
          });
        }
      },
    );
  }

  /// 投稿ボタン押下: 写真を圧縮 → アップロード → posts に Vibe 投稿として作成。
  /// `audience` で公開範囲を指定（'public' / 'followers'）。
  ///
  /// 投稿フロー (post_final_preview_screen) と同じ軽量化を適用:
  /// - 写真は [PhotoHelper.compressForUpload] でリサイズ + JPEG 再エンコード
  /// - ユーザー情報 / お題 / アップロードを **Future.wait で並列実行**
  /// - getDownloadURL と Firestore createPost も並列
  /// - createPost には photoUrl=null で先に書き、URL 取得後に updatePostPhotoUrl
  Future<void> _submitPost(String audience) async {
    if (_selectedPhoto == null || _isPosting) return;
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      AppToast.show(context, 'ログインが必要です');
      return;
    }
    setState(() => _isPosting = true);

    try {
      // Phase 1: 写真圧縮 / ユーザー / お題 / 班判定を並列実行
      final results = await Future.wait<dynamic>([
        PhotoHelper.compressForUpload(_selectedPhoto!),
        _userService.getUser(currentUser.uid),
        AdlService()
            .isCurrentUserAdlParticipant()
            .then((forAdl) => _vibeTopicService.getTodaysTopic(forAdl: forAdl)),
      ]);
      final compressed = results[0] as (Uint8List, int, int);
      final me = results[1] as dynamic;
      final topic = results[2];

      final username = (me?.username as String?) ?? '';
      final iconUrl = me?.profileImageUrl as String?;
      final adlTeamId = me?.adlTeamId as String?;
      // photoWidth/Height は使わない（natW/H=0 で旧方式パスを使うため）
      final (processedBytes, _, __) = compressed;

      // Phase 2: 圧縮済みバイトを Storage にアップロード（Reference のみ取得）
      final uploadResult = await PhotoHelper.uploadCompressedSplit(
        imageBytes: processedBytes,
        userId: currentUser.uid,
        storageService: _storageService,
      );

      // Phase 3: URL 取得と posts への書き込みを並列
      final urlFuture = uploadResult.storageRef!
          .getDownloadURL()
          .then<String?>((url) => url)
          .catchError((_) => null);
      // ── 写真とカードの編集状態を PostCard 裏面 (363×645) 座標系に変換 ──
      // フレーム 402×715 → カード 363×645、縮尺は約 0.903（横）/ 0.902（縦）。
      const sx = 363.0 / 402.0;
      const sy = 645.0 / 715.0;

      // 写真: PostCard 裏面の旧方式パス（BoxFit.cover + translate + scale）に渡す
      final savedImageOffsetX = _imageOffset.dx * sx;
      final savedImageOffsetY = _imageOffset.dy * sy;
      final savedImageScale = _imageScale;

      // カード（アルバム + 楽曲名 + アーティスト名）:
      // PostCard 裏面の歌詞カード描画は
      //   Positioned(left=cardPositionX, top=cardPositionY)
      //   + Transform.scale(cardScale, topLeft)
      //   + Transform.rotate(cardRotation, center)
      // で配置される。ストーリープレビューでは中心 (_cardCenter) で表示しているので
      // 左上座標を計算する。
      final displayedW = _cardW * _cardScale * sx;
      final displayedH = _cardH * _cardScale * sy;
      final savedCardCenterX = _cardCenter.dx * sx;
      final savedCardCenterY = _cardCenter.dy * sy;
      final savedCardPositionX = savedCardCenterX - displayedW / 2;
      final savedCardPositionY = savedCardCenterY - displayedH / 2;
      // PostCard 側の cardScale はベース 105×147 に対する倍率。
      // sx ≈ sy なので片方の縮尺で十分（横基準で揃える）。
      final savedCardScale = _cardScale * sx;

      final postIdFuture = _postService.createPost(
        userId: currentUser.uid,
        username: username,
        userIconUrl: iconUrl,
        trackData: widget.track.toMap(),
        // photoUrl は後追いで update する
        photoUrl: null,
        // 写真: 旧方式パスで描画させる（BoxFit.cover + translate + scale）
        imageOffsetX: savedImageOffsetX,
        imageOffsetY: savedImageOffsetY,
        imageScale: savedImageScale,
        imageNaturalWidth: 0,
        imageNaturalHeight: 0,
        // 歌詞カード: 投稿フロー裏面と同じ LyricsCardLayout.largeAlbumArt (index=1)
        selectedLayoutIndex: 1,
        cardPositionX: savedCardPositionX,
        cardPositionY: savedCardPositionY,
        cardScale: savedCardScale,
        cardRotation: _cardRotation,
        isVibe: topic != null,
        vibeTopicId: (topic as dynamic)?.topicId as String?,
        vibeTopicTitle: (topic as dynamic)?.title as String?,
        adlTeamId: adlTeamId,
        audience: audience,
        audioStartMs: 0,
        audioDurationSec: 15,
      );

      final phaseResults = await Future.wait<dynamic>([urlFuture, postIdFuture]);
      final photoUrl = phaseResults[0] as String?;
      final postId = phaseResults[1] as String;

      if (photoUrl != null) {
        // ignore: unawaited_futures
        _postService.updatePostPhotoUrl(postId: postId, photoUrl: photoUrl);
      }

      if (!mounted) return;
      AppToast.show(
        context,
        audience == PostAudience.followers
            ? 'フォロワー限定で投稿しました'
            : '全体に投稿しました',
      );
      Navigator.of(context).pop();
      widget.onAudienceSelected?.call(audience);
    } catch (e) {
      if (mounted) {
        AppToast.show(context, '投稿に失敗しました: $e');
        setState(() => _isPosting = false);
      }
    }
  }

  // ── ジェスチャー判定（投稿フロー _isInPhotoZone をそのまま移植） ──

  /// カードグループの外側（写真ゾーン）か判定。
  /// `scale` はフレーム（402×715）→ 画面の比率。
  bool _isInPhotoZone(Offset localPoint, double scale) {
    // フレーム外なら無効
    if (localPoint.dy < 0 || localPoint.dy > _frameH * scale) return false;
    if (localPoint.dx < 0 || localPoint.dx > _frameW * scale) return false;

    // カードグループの矩形（中心 + scale + rotation）に対して当たり判定
    final halfW = _cardW * _cardScale / 2;
    final halfH = _cardH * _cardScale / 2;
    final cx = _cardCenter.dx * scale;
    final cy = _cardCenter.dy * scale;
    final dx = localPoint.dx - cx;
    final dy = localPoint.dy - cy;
    final angle = -_cardRotation;
    final rx = dx * cos(angle) - dy * sin(angle);
    final ry = dx * sin(angle) + dy * cos(angle);
    return !(rx.abs() <= halfW * scale && ry.abs() <= halfH * scale);
  }

  bool _isInCardHitArea(Offset localFocal, double scale) {
    return localFocal.dx >= 0 &&
        localFocal.dx <= _frameW * scale &&
        localFocal.dy >= 0 &&
        localFocal.dy <= _frameH * scale;
  }

  void _onGestureScaleStart(ScaleStartDetails details, double scale) {
    if (_isInPhotoZone(details.localFocalPoint, scale)) {
      // 写真ゾーン: 1本指でも 2本指でも pan + scale
      _isPhotoGestureMode = true;
      _photoStartOffset = _imageOffset;
      _photoStartScale = _imageScale;
      _photoStartFocalPoint = details.localFocalPoint;
      return;
    }
    // カードゾーン
    _isPhotoGestureMode = false;
    _startScale = _cardScale;
    _startRotation = _cardRotation;
    _rotationTracker.reset();
    _rotationLock.reset();
    _isTwoFingerAccepted = false;
    if (details.pointerCount >= 2 &&
        _isInCardHitArea(details.localFocalPoint, scale)) {
      _isTwoFingerAccepted = true;
    }
  }

  void _onGestureScaleUpdate(ScaleUpdateDetails details, double scale) {
    if (_isPhotoGestureMode) {
      if (_selectedPhoto == null) return; // 写真なしのときは背景操作なし
      // Vibe Story の背景写真は BoxFit.cover で中央配置されているので、
      // Transform.scale(alignment: center) + Transform.translate(offset) で扱う。
      // → 平行移動: 指のドラッグ量だけ動かす（中心基準のシンプルな pan）
      // → 拡大: 中心基準で start * details.scale
      final newScale = (_photoStartScale * details.scale).clamp(0.5, 5.0);
      final panDelta = details.localFocalPoint - _photoStartFocalPoint;
      setState(() {
        _imageOffset = _photoStartOffset + panDelta;
        _imageScale = newScale;
      });
      return;
    }

    double newScale = _cardScale;
    double newRotation = _cardRotation;

    // 2 指の上下/左右入れ替わりによる ±π ジャンプを補正してから累積
    _rotationTracker.ingest(details.rotation);

    if (details.pointerCount >= 2) {
      if (!_isTwoFingerAccepted &&
          _isInCardHitArea(details.localFocalPoint, scale)) {
        _isTwoFingerAccepted = true;
        _startScale = _cardScale;
        _startRotation = _cardRotation;
      }
      if (_isTwoFingerAccepted) {
        newScale = (_startScale * (1.0 + (details.scale - 1.0) * 0.6))
            .clamp(0.3, 3.0);

        // 回転計算: 初期 10° ロック + 解除後の damping 0.6 適用
        newRotation = _rotationLock.computeRotation(
          startRotation: _startRotation,
          accumulated: _rotationTracker.accumulated,
        );
      }
    }

    // 中心移動（focalPointDelta × 0.7）。
    // delta はスクリーン基準なので scale で割ってカード座標に戻す。
    final newCenter = Offset(
      _cardCenter.dx + details.focalPointDelta.dx * 0.7 / scale,
      _cardCenter.dy + details.focalPointDelta.dy * 0.7 / scale,
    );

    setState(() {
      _cardCenter = newCenter;
      _cardScale = newScale;
      _cardRotation = newRotation;
    });
  }

  void _onGestureScaleEnd(ScaleEndDetails details) {
    if (_isPhotoGestureMode) {
      setState(() => _isPhotoGestureMode = false);
      return;
    }
    setState(() {
      _isTwoFingerAccepted = false;
      // 初期中心に近ければスナップ
      if ((_cardCenter - _defaultCardCenter).distance <= 40.0) {
        _cardCenter = _defaultCardCenter;
        HapticFeedback.lightImpact();
      }
    });
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Figma 基準: 全画面 402×874、プレビューカード 402×715 (top=63)、ボタン top=787
            final w = constraints.maxWidth;
            // 基準幅 402 に対する縮尺
            final scale = w / 402.0;
            return Stack(
              children: [
                // 1. 中央プレビューカード（背景写真 + カードグループ）
                //   focal point からカード上/外で操作対象を分岐。
                //   回転は `_ingestRotation` でラップ補正済みの累積角度を使う
                //   ことで 2 指の上下/左右入れ替わり時の ±π ジャンプを防ぐ。
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: 715 * scale,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onScaleStart: (d) => _onGestureScaleStart(d, scale),
                    onScaleUpdate: (d) => _onGestureScaleUpdate(d, scale),
                    onScaleEnd: _onGestureScaleEnd,
                    child: _buildPreviewCard(scale),
                  ),
                ),
                // 2. 左上: 閉じるボタン
                Positioned(
                  left: 11 * scale,
                  top: 11 * scale,
                  width: 44 * scale,
                  height: 44 * scale,
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).maybePop(),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withValues(alpha: 0.35),
                      ),
                      alignment: Alignment.center,
                      child: Icon(Icons.close,
                          color: Colors.white, size: 22 * scale),
                    ),
                  ),
                ),
                // 3. 右上: 楽曲アイコン円（内側にアルバム小）
                Positioned(
                  right: 13 * scale,
                  top: 11 * scale,
                  width: 44 * scale,
                  height: 44 * scale,
                  child: _buildTrackBadge(scale),
                ),
                // 4. 左下: 写真選択ボタン（投稿者アイコンが入った枠）
                //   → タップで写真グリッドオーバーレイを下からフェードイン
                Positioned(
                  left: 21 * scale,
                  top: 660 * scale,
                  width: 34 * scale,
                  height: 34 * scale,
                  child: GestureDetector(
                    onTap: _openPhotoPicker,
                    behavior: HitTestBehavior.opaque,
                    child: _buildAuthorAvatar(scale),
                  ),
                ),
                // 5. 下部ボタン群: 全体に公開 / フォロワーのみ
                Positioned(
                  left: 16 * scale,
                  top: 724 * scale, // 715 (カード下端) + 9 ≒ Figma top=787 相当
                  width: 180 * scale,
                  height: 45 * scale,
                  child: _buildPublicButton(context, scale),
                ),
                Positioned(
                  left: 212 * scale,
                  top: 724 * scale,
                  width: 180 * scale,
                  height: 45 * scale,
                  child: _buildFollowersButton(context, scale),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────
  // パーツ
  // ────────────────────────────────────────────────────────────

  Widget _buildPreviewCard(double scale) {
    final art = track.albumImageUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(23 * scale),
      child: Stack(
        children: [
          // 1. カード全面の背景
          //    - 写真選択済み: 選択写真を cover で全画面 + ユーザーの pan/scale を反映
          //    - 未選択: アルバムアートを淡くぼかして表示
          Positioned.fill(
            child: _selectedPhoto != null
                ? ClipRect(
                    child: Transform.translate(
                      offset: _imageOffset,
                      child: Transform.scale(
                        scale: _imageScale,
                        alignment: Alignment.center,
                        child: Image.memory(
                          _selectedPhoto!,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        ),
                      ),
                    ),
                  )
                : (art.isEmpty
                    ? Container(color: const Color(0xFF1F1F1F))
                    : CachedNetworkImage(
                        imageUrl: art,
                        fit: BoxFit.cover,
                        color: Colors.white.withValues(alpha: 0.75),
                        colorBlendMode: BlendMode.modulate,
                        placeholder: (_, __) =>
                            Container(color: const Color(0xFF1F1F1F)),
                        errorWidget: (_, __, ___) =>
                            Container(color: const Color(0xFF1F1F1F)),
                      )),
          ),
          // 2. ぼかしオーバーレイ（未選択時のみ：背景アルバムの柔らかさ用）
          if (_selectedPhoto == null)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.55),
                      Colors.white.withValues(alpha: 0.25),
                    ],
                  ),
                ),
              ),
            ),
          // 3. カードグループ: `LyricsCardLayout.largeAlbumArt` (105×147 ベース) を
          //    使う。投稿フロー裏面と完全に同じレイアウトなので、保存値をそのまま
          //    PostCard 裏面で再現できる。
          //    - cardScale: 初期値 _initialCardScale (≈ 2.25) で 236×286 相当の表示
          //    - cardRotation: そのまま
          //    - Positioned の width/height は基準サイズ × 画面scale（_cardScale は含めない）
          //      _cardScale は内側 Transform.scale で適用する。
          Positioned(
            left: _cardCenter.dx * scale - _cardW * scale / 2,
            top: _cardCenter.dy * scale - _cardH * scale / 2,
            width: _cardW * scale,
            height: _cardH * scale,
            child: Transform.scale(
              scale: _cardScale,
              alignment: Alignment.center,
              child: Transform.rotate(
                angle: _cardRotation,
                alignment: Alignment.center,
                child: _buildCardGroup(scale),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// カードグループ: 投稿フロー裏面と同じ [LyricsCardLayout.largeAlbumArt] (105×147)
  /// を使う。ベースサイズの 105×147 を画面 scale で拡大しただけのウィジェット。
  /// 外側で _cardScale × _cardRotation を Transform で適用する。
  Widget _buildCardGroup(double scale) {
    return SizedBox(
      width: _cardW * scale,
      height: _cardH * scale,
      child: Transform.scale(
        scale: scale,
        alignment: Alignment.topLeft,
        child: LyricsCardLayout(
          layoutType: LyricsCardLayoutType.largeAlbumArt,
          track: track,
        ),
      ),
    );
  }

  /// 右上の楽曲アイコン（円形、内側にアルバム小）
  Widget _buildTrackBadge(double scale) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black.withValues(alpha: 0.4),
      ),
      padding: EdgeInsets.all(9 * scale),
      child: ClipOval(
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3 * scale),
          ),
          child: ClipOval(
            child: track.albumImageUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: track.albumImageUrl,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) =>
                        const ColoredBox(color: Color(0xFF1F1F1F)),
                  )
                : const ColoredBox(color: Color(0xFF1F1F1F)),
          ),
        ),
      ),
    );
  }

  /// 写真選択ボタン（プレビューカード内・左下）。
  /// Figma 仕様（4546:8813）: 白枠 3px 角丸 8px の単純なサムネ。
  /// バッジやアイコンは載せない。
  ///   - 選択済み: 選んだ写真をサムネとして表示
  ///   - 未選択かつ端末フォト権限あり: フォトライブラリの最新写真
  ///   - 権限なし等: 投稿者アイコン
  Widget _buildAuthorAvatar(double scale) {
    final Widget inner = _selectedPhoto != null
        ? Image.memory(_selectedPhoto!, fit: BoxFit.cover, gaplessPlayback: true)
        : _latestGalleryThumb != null
            ? Image.memory(_latestGalleryThumb!,
                fit: BoxFit.cover, gaplessPlayback: true)
            : (authorIconUrl != null && authorIconUrl!.isNotEmpty)
                ? CachedNetworkImage(
                    imageUrl: authorIconUrl!,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) =>
                        Container(color: const Color(0xFF2A2A2A)),
                  )
                : Container(color: const Color(0xFF2A2A2A));
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8 * scale),
        border: Border.all(color: Colors.white, width: 3 * scale),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(5 * scale),
        child: inner,
      ),
    );
  }

  /// ボタンの有効/無効判定。写真未選択 or 投稿中はタップ不可。
  bool get _canSubmit => _selectedPhoto != null && !_isPosting;

  Widget _buildPublicButton(BuildContext context, double scale) {
    return Opacity(
      opacity: _canSubmit ? 1.0 : 0.45,
      child: GestureDetector(
        onTap: _canSubmit ? () => _submitPost(PostAudience.public) : null,
        behavior: HitTestBehavior.opaque,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30 * scale),
            gradient: const LinearGradient(
              colors: [Color(0xFF1937EF), Color(0xFFFE1F56)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
          child: Row(
            children: [
              SizedBox(width: 16 * scale),
              SizedBox(
                width: 24 * scale,
                height: 24 * scale,
                child: _isPosting
                    ? const CupertinoActivityIndicator(
                        color: Colors.white, radius: 8)
                    : Image.asset(
                        'assets/icons/Vibe.png',
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Icon(
                          Icons.music_note,
                          color: Colors.white,
                          size: 18 * scale,
                        ),
                      ),
              ),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.only(right: 24 * scale),
                    child: Text(
                      '全体に公開',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10 * scale,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFollowersButton(BuildContext context, double scale) {
    return Opacity(
      opacity: _canSubmit ? 1.0 : 0.45,
      child: GestureDetector(
        onTap: _canSubmit ? () => _submitPost(PostAudience.followers) : null,
        behavior: HitTestBehavior.opaque,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF2E2F2F),
            borderRadius: BorderRadius.circular(30 * scale),
          ),
          child: Row(
            children: [
              SizedBox(width: 16 * scale),
              SizedBox(
                width: 24 * scale,
                height: 24 * scale,
                child: _isPosting
                    ? const CupertinoActivityIndicator(
                        color: Colors.white, radius: 8)
                    : ClipOval(
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: Colors.white,
                                width: 3 * scale * 0.5),
                          ),
                          child: ClipOval(
                            child: (authorIconUrl != null &&
                                    authorIconUrl!.isNotEmpty)
                                ? CachedNetworkImage(
                                    imageUrl: authorIconUrl!,
                                    fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) =>
                                        Container(color: const Color(0xFF555)),
                                  )
                                : Container(color: const Color(0xFF555555)),
                          ),
                        ),
                      ),
              ),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.only(right: 24 * scale),
                    child: Text(
                      'フォロワーのみ',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10 * scale,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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
