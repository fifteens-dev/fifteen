import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../models/post_model.dart';
import '../models/track_model.dart';
import '../models/user_model.dart';
import '../services/save_service.dart';
import '../widgets/common/app_toast.dart';

/// ユーザーの「保存」状態を一元管理する単一のソース・オブ・トゥルース。
///
/// 保存対象は2系統あるが（投稿の保存と楽曲の保存）、UI上はどちらも
/// 「その楽曲が保存されているか」で表示する。
///
/// - postId ベース: 投稿カードからの保存（users.savedPosts / posts.savedByUserIds）
/// - trackId ベース: アーティストプロフィールからの保存（users.savedTracksData）
///
/// すべての画面はこのプロバイダーを通して読み書きする。
/// SaveService を直接呼ぶのはこのファイルだけ。
class SavedItemsProvider extends ChangeNotifier {
  final SaveService _saveService = SaveService();

  String? _userId;

  /// 保存済みの投稿ID
  final Set<String> _savedPostIds = {};

  /// 保存済みの楽曲（trackId → TrackModel）
  final Map<String, TrackModel> _savedTracks = {};

  /// 書き込み中の postId/trackId（連打防止）
  final Set<String> _pendingPostIds = {};
  final Set<String> _pendingTrackIds = {};

  // ──────── 初期化 ────────

  /// ユーザー情報から保存状態を初期化する。
  /// 起動時 / リフレッシュ時に呼ぶ。
  void initialize({
    required String userId,
    required UserModel user,
  }) {
    _userId = userId;
    _savedPostIds
      ..clear()
      ..addAll(user.savedPosts);

    _savedTracks.clear();
    for (final entry in user.savedTracksData.entries) {
      final data = entry.value;
      if (data is! Map) continue;
      final map = Map<String, dynamic>.from(data);
      final trackId = map['trackId']?.toString() ?? entry.key;
      if (trackId.isEmpty) continue;
      _savedTracks[trackId] = TrackModel(
        trackId: trackId,
        trackName: map['trackName']?.toString() ?? '',
        artistName: map['artistName']?.toString() ?? '',
        albumImageUrl: map['albumImageUrl']?.toString() ?? '',
        previewUrl: map['previewUrl']?.toString(),
      );
    }
    notifyListeners();
  }

  /// ログアウト等で全部クリアする。
  void clear() {
    _userId = null;
    _savedPostIds.clear();
    _savedTracks.clear();
    _pendingPostIds.clear();
    _pendingTrackIds.clear();
    notifyListeners();
  }

  // ──────── 読み取り ────────

  bool isPostSaved(String postId) => _savedPostIds.contains(postId);

  bool isTrackSaved(String trackId) => _savedTracks.containsKey(trackId);

  /// 投稿が「楽曲としても投稿としても」保存されていないかチェック。
  /// post.postId が savedPosts にある、または post.track.trackId が savedTracksData にあれば true。
  bool isPostOrTrackSaved(PostModel post) =>
      isPostSaved(post.postId) || isTrackSaved(post.track.trackId);

  /// 保存済み投稿IDの読み取り専用ビュー
  Set<String> get savedPostIds => Set.unmodifiable(_savedPostIds);

  /// 保存済み楽曲の読み取り専用ビュー
  Map<String, TrackModel> get savedTracks => Map.unmodifiable(_savedTracks);

  // ──────── 書き込み ────────

  /// 投稿の保存をトグルする。
  ///
  /// 既に楽曲として（savedTracksData）保存済みの場合はそちらを解除する。
  /// それ以外の場合は投稿保存（savedPosts）をトグルする。
  Future<void> togglePostSave(PostModel post) async {
    final uid = _userId;
    if (uid == null) return;

    // 楽曲として保存されている場合は楽曲側を解除
    if (isTrackSaved(post.track.trackId) && !isPostSaved(post.postId)) {
      await toggleTrackSave(post.track);
      return;
    }

    if (_pendingPostIds.contains(post.postId)) return;
    _pendingPostIds.add(post.postId);

    final wasSaved = isPostSaved(post.postId);
    if (wasSaved) {
      _savedPostIds.remove(post.postId);
    } else {
      _savedPostIds.add(post.postId);
    }
    notifyListeners();

    try {
      await _saveService.toggleSavePost(
        userId: uid,
        postId: post.postId,
        currentlySaved: wasSaved,
      );
    } catch (e) {
      // ロールバック
      if (wasSaved) {
        _savedPostIds.add(post.postId);
      } else {
        _savedPostIds.remove(post.postId);
      }
      notifyListeners();
      rethrow;
    } finally {
      _pendingPostIds.remove(post.postId);
    }
  }

  /// 楽曲の保存をトグルする（trackId ベース）。
  Future<void> toggleTrackSave(TrackModel track) async {
    final uid = _userId;
    if (uid == null) return;
    if (_pendingTrackIds.contains(track.trackId)) return;
    _pendingTrackIds.add(track.trackId);

    final wasSaved = isTrackSaved(track.trackId);
    if (wasSaved) {
      _savedTracks.remove(track.trackId);
    } else {
      _savedTracks[track.trackId] = track;
    }
    notifyListeners();

    try {
      await _saveService.toggleSaveTrack(
        userId: uid,
        track: track,
        currentlySaved: wasSaved,
      );
    } catch (e) {
      // ロールバック
      if (wasSaved) {
        _savedTracks[track.trackId] = track;
      } else {
        _savedTracks.remove(track.trackId);
      }
      notifyListeners();
      rethrow;
    } finally {
      _pendingTrackIds.remove(track.trackId);
    }
  }

  /// 保存済みの楽曲リスト（savedAt 降順は維持しない、Mapの挿入順）
  List<TrackModel> get savedTracksList => _savedTracks.values.toList();

  // ──────── テスト/デバッグ用 ────────

  @visibleForTesting
  void debugSetState({
    Set<String>? savedPostIds,
    Map<String, TrackModel>? savedTracks,
    String? userId,
  }) {
    if (userId != null) _userId = userId;
    if (savedPostIds != null) {
      _savedPostIds
        ..clear()
        ..addAll(savedPostIds);
    }
    if (savedTracks != null) {
      _savedTracks
        ..clear()
        ..addAll(savedTracks);
    }
    notifyListeners();
  }

  // ──────── トースト付きヘルパー（全画面共通） ────────

  /// 投稿の保存をトグルし、結果に応じて「保存しました／保存を解除しました」を表示する。
  /// 失敗時は「保存に失敗しました」を表示する。
  /// 全画面の保存ボタンタップから呼ぶこと。
  static Future<void> togglePostWithToast(
    BuildContext context,
    PostModel post,
  ) async {
    final provider = context.read<SavedItemsProvider>();
    final wasSaved = provider.isPostOrTrackSaved(post);
    try {
      await provider.togglePostSave(post);
      if (context.mounted) {
        AppToast.show(context, wasSaved ? '保存を解除しました' : '保存しました');
      }
    } catch (_) {
      if (context.mounted) {
        AppToast.show(context, '保存に失敗しました');
      }
    }
  }

  /// 楽曲（投稿に紐付かない）の保存をトグルし、トースト表示する。
  static Future<void> toggleTrackWithToast(
    BuildContext context,
    TrackModel track,
  ) async {
    final provider = context.read<SavedItemsProvider>();
    final wasSaved = provider.isTrackSaved(track.trackId);
    try {
      await provider.toggleTrackSave(track);
      if (context.mounted) {
        AppToast.show(context, wasSaved ? '保存を解除しました' : '保存しました');
      }
    } catch (_) {
      if (context.mounted) {
        AppToast.show(context, '保存に失敗しました');
      }
    }
  }
}

