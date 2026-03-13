import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class ReportService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _reportsCollection = 'reports';

  /// 投稿を通報
  Future<void> reportPost({
    required String postId,
    required String reporterId,
    required String reportedUserId,
    required String reason,
  }) async {
    try {
      await _firestore.collection(_reportsCollection).add({
        'type': 'post',
        'postId': postId,
        'reporterId': reporterId,
        'reportedUserId': reportedUserId,
        'reason': reason,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (kDebugMode) print('Error reporting post: $e');
      rethrow;
    }
  }

  /// コメントを通報
  Future<void> reportComment({
    required String commentId,
    required String postId,
    required String reporterId,
    required String reportedUserId,
    required String reason,
  }) async {
    try {
      await _firestore.collection(_reportsCollection).add({
        'type': 'comment',
        'commentId': commentId,
        'postId': postId,
        'reporterId': reporterId,
        'reportedUserId': reportedUserId,
        'reason': reason,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (kDebugMode) print('Error reporting comment: $e');
      rethrow;
    }
  }
}
