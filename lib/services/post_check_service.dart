import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/post_model.dart';
import '../utils/campus_vibe_utils.dart';
import 'post_fetch_service.dart';
import 'music_memory_cycle_service.dart';

/// 投稿の存在チェックと日付フィルタリングを担当するサービス
class PostCheckService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _postsCollection = 'posts';
  final PostFetchService _fetchService = PostFetchService();

  /// 特定ユーザーが指定した日に投稿しているかチェック
  Future<bool> hasUserPostedOnDate(String userId, DateTime date) async {
    try {
      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59);

      final snapshot = await _firestore
          .collection(_postsCollection)
          .where('userId', isEqualTo: userId)
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();

      return snapshot.docs.isNotEmpty;
    } catch (e) {
      if (kDebugMode) {
        print('Error checking if user posted on date: $e');
      }
      return false;
    }
  }

  /// 特定ユーザーが今週末（金〜日）に投稿しているかチェック（Campus Vibe用）
  Future<bool> hasUserPostedInCurrentWeekend(String userId) async {
    try {
      final range = CampusVibeUtils.weekendRange();
      final snapshot = await _firestore
          .collection(_postsCollection)
          .where('userId', isEqualTo: userId)
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(range.start))
          .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(range.end))
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();
      return snapshot.docs.isNotEmpty;
    } catch (e) {
      if (kDebugMode) print('Error checking weekend post: $e');
      return false;
    }
  }

  /// 特定ユーザーが今日投稿しているかチェック
  Future<bool> hasUserPostedToday(String userId) async {
    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59);

      final snapshot = await _firestore
          .collection(_postsCollection)
          .where('userId', isEqualTo: userId)
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();

      return snapshot.docs.isNotEmpty;
    } catch (e) {
      if (kDebugMode) {
        print('Error checking if user posted today: $e');
      }
      return false;
    }
  }

  /// 現在の Music Memory サイクルで「期限内（Late でない）投稿」をしているか。
  /// これが true のユーザーだけが、他人の投稿の裏側閲覧＋リアクションを許可される。
  /// （Late 投稿者・未投稿者は表面のみ = false）
  Future<bool> hasOnTimePostInCurrentCycle(String userId) async {
    try {
      final cutoff = MusicMemoryCycleService().currentCycleStart;
      final snapshot = await _firestore
          .collection(_postsCollection)
          .where('userId', isEqualTo: userId)
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(cutoff))
          .orderBy('createdAt', descending: true)
          .limit(10)
          .get();
      return snapshot.docs.any((d) {
        final m = d.data();
        return m['isMoodPost'] == true && m['isLate'] != true;
      });
    } catch (e) {
      if (kDebugMode) {
        print('Error checking on-time post in cycle: $e');
      }
      return false;
    }
  }

  /// 現在の Music Memory サイクルで既に（Late 含む）投稿しているか。
  /// 投稿フローの「初回 / 次回以降」出し分けに使う（未投稿=初回）。
  Future<bool> hasAnyPostInCurrentCycle(String userId) async {
    try {
      final cutoff = MusicMemoryCycleService().currentCycleStart;
      final snapshot = await _firestore
          .collection(_postsCollection)
          .where('userId', isEqualTo: userId)
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(cutoff))
          .orderBy('createdAt', descending: true)
          .limit(10)
          .get();
      return snapshot.docs.any((d) => d.data()['isMoodPost'] == true);
    } catch (e) {
      if (kDebugMode) {
        print('Error checking any post in cycle: $e');
      }
      return false;
    }
  }

  /// フォロー中のユーザーの誰かが、現サイクルで投稿しているか。
  ///
  /// Live Activity の「まだ投稿していません」→「友達があなたを待っています」
  /// の切り替え判定に使う。件数は要らないので、1 件見つかった時点で打ち切る。
  Future<bool> hasFollowingPostedInCurrentCycle(List<String> followingIds) async {
    if (followingIds.isEmpty) return false;
    final cutoff = MusicMemoryCycleService().currentCycleStart;
    try {
      for (var i = 0; i < followingIds.length; i += 30) {
        final batch = followingIds.skip(i).take(30).toList();
        final snapshot = await _firestore
            .collection(_postsCollection)
            .where('userId', whereIn: batch)
            .where('createdAt', isGreaterThan: Timestamp.fromDate(cutoff))
            .orderBy('createdAt', descending: true)
            .limit(5)
            .get();
        final hit = snapshot.docs.any((d) {
          final m = d.data();
          return m['isDummyPost'] != true && m['isVibe'] != true;
        });
        if (hit) return true;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error checking following posts in cycle: $e');
      }
    }
    return false;
  }

  /// 特定ユーザーの今日の投稿を取得
  Future<List<PostModel>> getTodaysPosts(String userId) async {
    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59);

      final snapshot = await _firestore
          .collection(_postsCollection)
          .where('userId', isEqualTo: userId)
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
          .orderBy('createdAt', descending: true)
          .get();

      final posts = snapshot.docs
          .map((doc) => PostModel.fromFirestore(doc))
          .toList();
      return await _fetchService.applyLatestUserInfo(posts);
    } catch (e) {
      if (kDebugMode) {
        print('Error getting today\'s posts: $e');
      }
      return [];
    }
  }

  /// 特定ユーザーの今日以外の投稿を取得
  Future<List<PostModel>> getPostsExcludingToday(String userId, {int limit = 20}) async {
    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);

      final snapshot = await _firestore
          .collection(_postsCollection)
          .where('userId', isEqualTo: userId)
          .where('createdAt', isLessThan: Timestamp.fromDate(startOfDay))
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();

      final posts = snapshot.docs
          .map((doc) => PostModel.fromFirestore(doc))
          .toList();
      return await _fetchService.applyLatestUserInfo(posts);
    } catch (e) {
      if (kDebugMode) {
        print('Error getting posts excluding today: $e');
      }
      return [];
    }
  }
}
