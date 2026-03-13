import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/report_service.dart';

const _reasons = [
  'スパム',
  '不適切なコンテンツ',
  'ハラスメント・いじめ',
  '著作権侵害',
  'その他',
];

/// 通報ダイアログ（ボトムシート）を表示
Future<void> showReportDialog(
  BuildContext context, {
  required String reportedUserId,
  String? postId,
  String? commentId,
}) async {
  final currentUser = FirebaseAuth.instance.currentUser;
  if (currentUser == null) return;

  await showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => _ReportSheet(
      reportedUserId: reportedUserId,
      postId: postId,
      commentId: commentId,
      reporterId: currentUser.uid,
    ),
  );
}

class _ReportSheet extends StatefulWidget {
  final String reportedUserId;
  final String? postId;
  final String? commentId;
  final String reporterId;

  const _ReportSheet({
    required this.reportedUserId,
    required this.reporterId,
    this.postId,
    this.commentId,
  });

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  final ReportService _reportService = ReportService();
  bool _isSubmitting = false;

  Future<void> _submit(String reason) async {
    setState(() => _isSubmitting = true);
    try {
      if (widget.commentId != null) {
        await _reportService.reportComment(
          commentId: widget.commentId!,
          postId: widget.postId ?? '',
          reporterId: widget.reporterId,
          reportedUserId: widget.reportedUserId,
          reason: reason,
        );
      } else {
        await _reportService.reportPost(
          postId: widget.postId ?? '',
          reporterId: widget.reporterId,
          reportedUserId: widget.reportedUserId,
          reason: reason,
        );
      }
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('通報しました。ご報告ありがとうございます。'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('通報に失敗しました。もう一度お試しください。')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D2D),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ドラッグハンドル
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Container(
              width: 40,
              height: 3,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // タイトル
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 16, 24, 4),
            child: Text(
              '通報する理由を選択してください',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          const Divider(color: Colors.white12, height: 24),

          // 理由リスト
          ..._reasons.map((reason) => InkWell(
                onTap: _isSubmitting ? null : () => _submit(reason),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 14),
                  child: _isSubmitting
                      ? const Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white54,
                              strokeWidth: 2,
                            ),
                          ),
                        )
                      : Text(
                          reason,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                          ),
                        ),
                ),
              )),

          const Divider(color: Colors.white12, height: 1),

          // キャンセル
          InkWell(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              alignment: Alignment.center,
              child: const Text(
                'キャンセル',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
