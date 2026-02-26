import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// 招待統計タブ
/// ユーザーごとの招待数（何人を招待したか）を一覧表示
class InvitationStatsTab extends StatefulWidget {
  const InvitationStatsTab({super.key});

  @override
  State<InvitationStatsTab> createState() => _InvitationStatsTabState();
}

class _InvitationStatsTabState extends State<InvitationStatsTab> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<_InviteStats> _stats = [];
  bool _isLoading = true;
  String? _error;

  // ソート方向
  _SortMode _sortMode = _SortMode.usedDesc;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      // inviteCodeを持つ全ユーザーを取得
      final usersSnap = await _firestore
          .collection('users')
          .where('inviteCode', isNotEqualTo: null)
          .get();

      if (usersSnap.docs.isEmpty) {
        setState(() { _stats = []; _isLoading = false; });
        return;
      }

      // 各ユーザーのinvite_codesドキュメントを並列取得
      final futures = usersSnap.docs.map((userDoc) async {
        final data = userDoc.data();
        final code = data['inviteCode'] as String?;
        if (code == null || code.isEmpty) return null;

        int usedCount = 0;
        int maxUses = 3;
        try {
          final codeDoc = await _firestore
              .collection('invite_codes')
              .doc(code)
              .get();
          if (codeDoc.exists) {
            usedCount = (codeDoc.data()?['usedCount'] as int?) ?? 0;
            maxUses = (codeDoc.data()?['maxUses'] as int?) ?? 3;
          }
        } catch (_) {}

        return _InviteStats(
          uid: userDoc.id,
          name: data['name'] as String? ?? '名前未設定',
          username: data['username'] as String? ?? '',
          profileImageUrl: data['profileImageUrl'] as String?,
          inviteCode: code,
          usedCount: usedCount,
          maxUses: maxUses,
        );
      }).toList();

      final results = await Future.wait(futures);
      final stats = results.whereType<_InviteStats>().toList();
      _applySorting(stats);

      if (mounted) setState(() { _stats = stats; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  void _applySorting(List<_InviteStats> list) {
    switch (_sortMode) {
      case _SortMode.usedDesc:
        list.sort((a, b) => b.usedCount.compareTo(a.usedCount));
      case _SortMode.usedAsc:
        list.sort((a, b) => a.usedCount.compareTo(b.usedCount));
      case _SortMode.nameAsc:
        list.sort((a, b) => a.displayName.compareTo(b.displayName));
    }
  }

  void _changeSortMode(_SortMode mode) {
    setState(() {
      _sortMode = mode;
      _applySorting(_stats);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildSummaryBar(),
        _buildToolbar(),
        Expanded(child: _buildBody()),
      ],
    );
  }

  /// 上部サマリーバー（全体の招待数合計）
  Widget _buildSummaryBar() {
    final total = _stats.fold(0, (sum, s) => sum + s.usedCount);
    final totalUsers = _stats.length;
    final fullyUsed = _stats.where((s) => s.usedCount >= s.maxUses).length;

    return Container(
      color: const Color(0xFF1E1E2E),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          _buildSummaryItem('招待済み合計', '$total 人'),
          const SizedBox(width: 24),
          _buildSummaryItem('コード保有者', '$totalUsers 人'),
          const SizedBox(width: 24),
          _buildSummaryItem('上限達成', '$fullyUsed 人'),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(color: Colors.grey, fontSize: 11)),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
      ],
    );
  }

  /// ツールバー（ソート＋更新ボタン）
  Widget _buildToolbar() {
    return Container(
      color: const Color(0xFF1A1A2A),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          const Text('並び替え:',
              style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(width: 8),
          _buildSortChip('招待数↓', _SortMode.usedDesc),
          const SizedBox(width: 6),
          _buildSortChip('招待数↑', _SortMode.usedAsc),
          const SizedBox(width: 6),
          _buildSortChip('名前順', _SortMode.nameAsc),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white, size: 20),
            tooltip: '更新',
            onPressed: _isLoading ? null : _loadStats,
          ),
        ],
      ),
    );
  }

  Widget _buildSortChip(String label, _SortMode mode) {
    final selected = _sortMode == mode;
    return GestureDetector(
      onTap: () => _changeSortMode(mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? Colors.blueAccent : Colors.grey[800],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.grey[400],
            fontSize: 12,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white));
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 12),
            Text(_error!,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
                onPressed: _loadStats, child: const Text('再試行')),
          ],
        ),
      );
    }
    if (_stats.isEmpty) {
      return const Center(
        child: Text('招待コードを持つユーザーがいません',
            style: TextStyle(color: Colors.grey)),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _stats.length,
      separatorBuilder: (_, __) =>
          const Divider(color: Color(0xFF2A2A3A), height: 1),
      itemBuilder: (context, index) => _buildStatRow(_stats[index]),
    );
  }

  Widget _buildStatRow(_InviteStats stat) {
    final remaining = stat.maxUses - stat.usedCount;
    final progress = stat.usedCount / stat.maxUses;
    final isFull = stat.usedCount >= stat.maxUses;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          // アバター
          _buildAvatar(stat),
          const SizedBox(width: 12),

          // 名前・コード
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stat.displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (stat.username.isNotEmpty)
                  Text('@${stat.username}',
                      style: const TextStyle(
                          color: Colors.grey, fontSize: 11)),
                const SizedBox(height: 2),
                // 招待コード
                Row(
                  children: [
                    const Icon(Icons.vpn_key,
                        color: Colors.grey, size: 11),
                    const SizedBox(width: 4),
                    Text(
                      stat.inviteCode,
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 11,
                        fontFamily: 'monospace',
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // 招待数バー＋カウント
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // カウントバッジ
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isFull
                      ? Colors.red.withValues(alpha: 0.2)
                      : Colors.green.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isFull ? Colors.red : Colors.green,
                    width: 1,
                  ),
                ),
                child: Text(
                  '${stat.usedCount} / ${stat.maxUses}',
                  style: TextStyle(
                    color: isFull ? Colors.red : Colors.green,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              // プログレスバー
              SizedBox(
                width: 80,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress.clamp(0.0, 1.0),
                    backgroundColor: Colors.grey[800],
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isFull ? Colors.red : Colors.blueAccent,
                    ),
                    minHeight: 6,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                isFull ? '上限達成' : '残り $remaining 人',
                style: TextStyle(
                  color: isFull ? Colors.red[300] : Colors.grey,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(_InviteStats stat) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.grey[800],
      ),
      child: ClipOval(
        child: stat.profileImageUrl != null && stat.profileImageUrl!.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: stat.profileImageUrl!,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => _buildAvatarPlaceholder(stat),
              )
            : _buildAvatarPlaceholder(stat),
      ),
    );
  }

  Widget _buildAvatarPlaceholder(_InviteStats stat) {
    final initial = stat.displayName.isNotEmpty
        ? stat.displayName[0].toUpperCase()
        : '?';
    return Container(
      color: Colors.blueGrey[700],
      child: Center(
        child: Text(initial,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold)),
      ),
    );
  }
}

/// 招待統計データクラス
class _InviteStats {
  final String uid;
  final String name;
  final String username;
  final String? profileImageUrl;
  final String inviteCode;
  final int usedCount;
  final int maxUses;

  const _InviteStats({
    required this.uid,
    required this.name,
    required this.username,
    required this.profileImageUrl,
    required this.inviteCode,
    required this.usedCount,
    required this.maxUses,
  });

  String get displayName =>
      name.isNotEmpty ? name : (username.isNotEmpty ? username : '名前未設定');
}

enum _SortMode { usedDesc, usedAsc, nameAsc }
