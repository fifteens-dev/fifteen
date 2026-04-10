import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// 通報管理タブ
/// 投稿・コメントへの通報一覧と対応ステータス管理
class ReportsTab extends StatefulWidget {
  const ReportsTab({super.key});

  @override
  State<ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<ReportsTab> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // フィルター: 'all' | 'pending' | 'reviewed'
  String _filter = 'pending';

  // インデックス不要にするため、全件取得してクライアント側でフィルタリング
  Stream<QuerySnapshot> get _reportsStream {
    return _firestore
        .collection('reports')
        .orderBy('createdAt', descending: true)
        .limit(200)
        .snapshots();
  }

  Future<void> _markAsReviewed(String docId) async {
    await _firestore.collection('reports').doc(docId).update({
      'status': 'reviewed',
      'reviewedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _dismiss(String docId) async {
    await _firestore.collection('reports').doc(docId).update({
      'status': 'dismissed',
      'reviewedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // フィルターチップ
        _buildFilterRow(),

        // 通報一覧
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _reportsStream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CupertinoActivityIndicator(color: Colors.white54, radius: 14),
                );
              }
              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    'エラー: ${snapshot.error}',
                    style: const TextStyle(color: Colors.red),
                  ),
                );
              }

              final allDocs = snapshot.data?.docs ?? [];
              // クライアント側でステータスフィルタリング
              final docs = _filter == 'all'
                  ? allDocs
                  : allDocs.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      return data['status'] == _filter;
                    }).toList();

              if (docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle_outline,
                          color: Colors.white24, size: 48),
                      const SizedBox(height: 12),
                      Text(
                        _filter == 'pending' ? '未対応の通報はありません' : '通報がありません',
                        style: const TextStyle(color: Colors.white54),
                      ),
                    ],
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final doc = docs[index];
                  return _ReportCard(
                    docId: doc.id,
                    data: doc.data() as Map<String, dynamic>,
                    onReviewed: () => _markAsReviewed(doc.id),
                    onDismissed: () => _dismiss(doc.id),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFilterRow() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Row(
        children: [
          _FilterChip(
            label: '未対応',
            selected: _filter == 'pending',
            onTap: () => setState(() => _filter = 'pending'),
            color: Colors.orange,
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: '対応済み',
            selected: _filter == 'reviewed',
            onTap: () => setState(() => _filter = 'reviewed'),
            color: Colors.green,
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: '全て',
            selected: _filter == 'all',
            onTap: () => setState(() => _filter = 'all'),
            color: Colors.white54,
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color color;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : Colors.white24,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? color : Colors.white54,
            fontSize: 12,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  final String docId;
  final Map<String, dynamic> data;
  final VoidCallback onReviewed;
  final VoidCallback onDismissed;

  const _ReportCard({
    required this.docId,
    required this.data,
    required this.onReviewed,
    required this.onDismissed,
  });

  String get _type => data['type'] as String? ?? 'post';
  String get _reason => data['reason'] as String? ?? '-';
  String get _status => data['status'] as String? ?? 'pending';
  String get _reportedUserId => data['reportedUserId'] as String? ?? '-';
  String get _postId => data['postId'] as String? ?? '-';
  String? get _commentId => data['commentId'] as String?;

  String get _timeAgo {
    final ts = data['createdAt'];
    if (ts == null) return '';
    final dt = (ts as Timestamp).toDate();
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 0) return '${diff.inDays}日前';
    if (diff.inHours > 0) return '${diff.inHours}時間前';
    if (diff.inMinutes > 0) return '${diff.inMinutes}分前';
    return 'たった今';
  }

  bool get _isPending => _status == 'pending';

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isPending ? Colors.orange.withValues(alpha: 0.3) : Colors.white12,
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ヘッダー行
          Row(
            children: [
              _TypeBadge(type: _type),
              const SizedBox(width: 8),
              _StatusBadge(status: _status),
              const Spacer(),
              Text(
                _timeAgo,
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // 通報理由
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('理由', style: TextStyle(color: Colors.white38, fontSize: 12)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _reason,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ],
          ),

          const SizedBox(height: 6),

          // 通報先ユーザー
          Row(
            children: [
              const Text('対象ユーザー', style: TextStyle(color: Colors.white38, fontSize: 12)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _reportedUserId,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),

          const SizedBox(height: 4),

          // 投稿ID / コメントID
          Row(
            children: [
              Text(
                _commentId != null ? 'コメントID' : '投稿ID',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _commentId ?? _postId,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),

          // アクションボタン（未対応時のみ）
          if (_isPending) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onDismissed,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    '却下',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: onReviewed,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.withValues(alpha: 0.8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    '対応済みにする',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  final String type;
  const _TypeBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    final isComment = type == 'comment';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: (isComment ? Colors.deepOrange : Colors.red).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isComment ? Colors.deepOrange : Colors.red,
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isComment ? Icons.comment_outlined : Icons.article_outlined,
            color: isComment ? Colors.deepOrange : Colors.red,
            size: 11,
          ),
          const SizedBox(width: 4),
          Text(
            isComment ? 'コメント' : '投稿',
            style: TextStyle(
              color: isComment ? Colors.deepOrange : Colors.red,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    switch (status) {
      case 'reviewed':
        color = Colors.green;
        label = '対応済み';
        break;
      case 'dismissed':
        color = Colors.white38;
        label = '却下';
        break;
      default:
        color = Colors.orange;
        label = '未対応';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
