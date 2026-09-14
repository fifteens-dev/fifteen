import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_text_styles.dart';
import '../../constants/app_dimensions.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/common/app_toast.dart';
import '../../services/live_activity_service.dart';

/// 開発者ツールタブ（管理者パネル内）
class DevToolsTab extends StatefulWidget {
  const DevToolsTab({super.key});

  @override
  State<DevToolsTab> createState() => _DevToolsTabState();
}

class _DevToolsTabState extends State<DevToolsTab> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _maxUsesController = TextEditingController(text: '10');
  bool _isLoading = false;
  String _statusMessage = '';

  // 管理者招待コードの追跡データ
  List<Map<String, dynamic>> _adminCodes = [];
  bool _isLoadingAdminCodes = false;

  @override
  void initState() {
    super.initState();
    _loadAdminCodes();
  }

  @override
  void dispose() {
    _codeController.dispose();
    _maxUsesController.dispose();
    super.dispose();
  }

  /// 管理者が作成した招待コードを読み込み
  Future<void> _loadAdminCodes() async {
    setState(() => _isLoadingAdminCodes = true);
    try {
      final snap = await _firestore
          .collection('invite_codes')
          .where('isAdminCode', isEqualTo: true)
          .get();
      if (mounted) {
        setState(() {
          _adminCodes = snap.docs
              .map((d) => {'id': d.id, ...d.data()})
              .toList()
            ..sort((a, b) {
              final aUsed = (a['usedCount'] as int?) ?? 0;
              final bUsed = (b['usedCount'] as int?) ?? 0;
              return bUsed.compareTo(aUsed);
            });
          _isLoadingAdminCodes = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingAdminCodes = false);
    }
  }

  Future<void> _executeAction({
    required String loadingMessage,
    required String successMessage,
    required String snackBarMessage,
    required Future<void> Function() action,
  }) async {
    setState(() {
      _isLoading = true;
      _statusMessage = loadingMessage;
    });

    try {
      await action();

      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = successMessage;
        });

        AppToast.show(context, snackBarMessage);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = '❌ エラー: $e';
        });

        AppToast.show(context, 'エラーが発生しました: $e');
      }
    }
  }

  /// Live Activity のアートワーク診断結果（端末の共有コンテナの中身）。
  String? _artworkDiag;
  bool _loadingDiag = false;

  /// アプリ側とウィジェット側のログをマージしたもの。
  String? _liveActivityLog;
  bool _loadingLog = false;

  Future<void> _loadLiveActivityLog() async {
    setState(() => _loadingLog = true);
    final log = await LiveActivityService().readLog();
    if (!mounted) return;
    setState(() {
      _loadingLog = false;
      _liveActivityLog = log.isEmpty ? '(ログなし)' : log;
    });
  }

  Future<void> _clearLiveActivityLog() async {
    await LiveActivityService().clearLog();
    if (!mounted) return;
    setState(() => _liveActivityLog = '(消去しました)');
    AppToast.show(context, 'ログを消去しました');
  }

  /// 共有コンテナの状態を取り込んで整形する。ジャケットがグレーのままになる
  /// 原因（ファイルが無い / 0 バイト / 画像として読めない）を切り分ける。
  Future<void> _loadArtworkDiagnostics() async {
    setState(() => _loadingDiag = true);
    final res = await LiveActivityService().artworkDiagnostics();
    if (!mounted) return;
    setState(() {
      _loadingDiag = false;
      if (res == null) {
        _artworkDiag = 'iOS 以外では利用できません';
        return;
      }
      final buf = StringBuffer();
      buf.writeln('App Group      : ${res['appGroupId']}');
      buf.writeln('保存ディレクトリ : ${res['storage'] ?? '-'}');
      buf.writeln('コンテナ        : ${res['containerAvailable'] == true ? 'OK' : '取得失敗'}');
      buf.writeln('日数           : ${res['dayCount']}');
      final days = (res['days'] as List?) ?? const [];
      for (final d in days) {
        final m = (d as Map).map((k, v) => MapEntry(k.toString(), v));
        buf.writeln(
          '  ${m['label']}${m['isToday'] == true ? '(今日)' : ''}'
          ' file=${m['imageFile']}'
          ' exists=${m['fileExists'] ?? '-'}'
          ' size=${m['fileSize'] ?? '-'}'
          ' decodable=${m['decodable'] ?? '-'}',
        );
      }
      final files = (res['filesInDirectory'] as List?) ?? const [];
      buf.writeln('ディレクトリ内   : ${files.length} ファイル ${files.join(', ')}');
      if (res['error'] != null) buf.writeln('error: ${res['error']}');
      _artworkDiag = buf.toString();
    });
  }

  Widget _buildArtworkDiagnostics() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Live Activity アートワーク診断',
          style: TextStyle(
              color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        const Text(
          'ロック画面のジャケットがグレーのままになる原因を切り分けます。',
          style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.5),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: _loadingDiag ? null : _loadArtworkDiagnostics,
              icon: const Icon(Icons.bug_report, size: 18),
              label: Text(_loadingDiag ? '取得中...' : '状態を取得'),
            ),
            const SizedBox(width: 8),
            if (_artworkDiag != null)
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _artworkDiag!));
                  AppToast.show(context, 'コピーしました');
                },
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('コピー'),
              ),
          ],
        ),
        if (_artworkDiag != null) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1E),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white12),
            ),
            child: SelectableText(
              _artworkDiag!,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 11, height: 1.6),
            ),
          ),
        ],

        const SizedBox(height: 16),
        const Text(
          'Live Activity ログ',
          style: TextStyle(
              color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        const Text(
          'アプリ側の記録。どの段階まで成功したかを追えます。'
          '（ウィジェットのプロセスからは書き込みが通らないため記録できません）',
          style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.5),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: _loadingLog ? null : _loadLiveActivityLog,
              icon: const Icon(Icons.receipt_long, size: 18),
              label: Text(_loadingLog ? '取得中...' : 'ログを取得'),
            ),
            const SizedBox(width: 8),
            if (_liveActivityLog != null)
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _liveActivityLog!));
                  AppToast.show(context, 'コピーしました');
                },
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('コピー'),
              ),
            const Spacer(),
            TextButton(
              onPressed: _clearLiveActivityLog,
              child: const Text('消去', style: TextStyle(color: Colors.white38)),
            ),
          ],
        ),
        if (_liveActivityLog != null) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 320),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1E),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white12),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                _liveActivityLog!,
                style: const TextStyle(
                    color: Colors.white70, fontSize: 10, height: 1.5),
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimensions.paddingLarge,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            _buildArtworkDiagnostics(),

            if (_statusMessage.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(AppDimensions.paddingMedium),
                decoration: BoxDecoration(
                  color: _statusMessage.contains('✅')
                      ? AppColors.success.withOpacity(0.1)
                      : AppColors.error.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _statusMessage.contains('✅')
                        ? AppColors.success
                        : AppColors.error,
                  ),
                ),
                child: Text(
                  _statusMessage,
                  style: TextStyle(
                    color: _statusMessage.contains('✅')
                        ? AppColors.success
                        : AppColors.error,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(height: AppDimensions.paddingLarge),
            ],

            // ── 管理者招待コード作成 ──
            const Text('管理者招待コード作成', style: AppTextStyles.heading),
            const SizedBox(height: AppDimensions.paddingMedium),
            TextField(
              controller: _codeController,
              style: const TextStyle(color: AppColors.textPrimary),
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: '招待コード',
                labelStyle: const TextStyle(color: AppColors.textSecondary),
                hintText: '例: BETA2026',
                hintStyle: TextStyle(color: AppColors.textSecondary.withOpacity(0.5)),
                enabledBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: AppColors.border),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: AppColors.accentBlue),
                ),
              ),
            ),
            const SizedBox(height: AppDimensions.paddingMedium),
            TextField(
              controller: _maxUsesController,
              style: const TextStyle(color: AppColors.textPrimary),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: '使用可能回数',
                labelStyle: const TextStyle(color: AppColors.textSecondary),
                hintText: '例: 10',
                hintStyle: TextStyle(color: AppColors.textSecondary.withOpacity(0.5)),
                enabledBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: AppColors.border),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: AppColors.accentBlue),
                ),
              ),
            ),
            const SizedBox(height: AppDimensions.paddingMedium),
            PrimaryButton(
              text: '招待コードを作成',
              onPressed: () async {
                final code = _codeController.text.trim().toUpperCase();
                final maxUses = int.tryParse(_maxUsesController.text.trim()) ?? 10;
                if (code.isEmpty) {
                  AppToast.show(context, '招待コードを入力してください');
                  return;
                }
                final adminUid = FirebaseAuth.instance.currentUser?.uid ?? '';
                await _executeAction(
                  loadingMessage: '招待コード「$code」を作成中...',
                  successMessage: '✅ 招待コード「$code」を作成しました（$maxUses回使用可能）',
                  snackBarMessage: '招待コード「$code」が作成されました',
                  action: () async {
                    await _firestore.collection('invite_codes').doc(code).set({
                      'code': code,
                      'maxUses': maxUses,
                      'usedCount': 0,
                      'isAdminCode': true,
                      'ownerUid': adminUid,
                      'createdAt': FieldValue.serverTimestamp(),
                    });
                  },
                );
                await _loadAdminCodes();
              },
              isLoading: _isLoading,
            ),

            const SizedBox(height: AppDimensions.paddingXLarge),

            // ── 管理者招待コード追跡 ──
            Row(
              children: [
                const Text('管理者コード追跡', style: AppTextStyles.heading),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.white, size: 20),
                  onPressed: _loadAdminCodes,
                ),
              ],
            ),
            const SizedBox(height: 8),
            _isLoadingAdminCodes
                ? const Center(child: CupertinoActivityIndicator(color: Colors.white, radius: 14))
                : _adminCodes.isEmpty
                    ? const Text('管理者作成コードがありません', style: TextStyle(color: Colors.grey))
                    : Column(
                        children: _adminCodes.map((code) {
                          final usedCount = (code['usedCount'] as int?) ?? 0;
                          final maxUses = (code['maxUses'] as int?) ?? 0;
                          final isFull = usedCount >= maxUses;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E1E2E),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isFull ? Colors.red.withOpacity(0.5) : Colors.green.withOpacity(0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        code['id'] as String,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          fontFamily: 'monospace',
                                          letterSpacing: 1.5,
                                        ),
                                      ),
                                      Text(
                                        isFull ? '上限達成' : '残り ${maxUses - usedCount} 回',
                                        style: TextStyle(
                                          color: isFull ? Colors.red[300] : Colors.grey,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isFull
                                        ? Colors.red.withOpacity(0.2)
                                        : Colors.green.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isFull ? Colors.red : Colors.green,
                                    ),
                                  ),
                                  child: Text(
                                    '$usedCount / $maxUses',
                                    style: TextStyle(
                                      color: isFull ? Colors.red : Colors.green,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),

            const SizedBox(height: AppDimensions.paddingXLarge),

            // ── Vibe通知テスト ──
            const Text('Vibe通知テスト', style: AppTextStyles.heading),
            const SizedBox(height: 8),
            const Text(
              '自分のアカウントにVibe通知をテスト送信します。\n（投稿済みチェックをスキップして送信）',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: AppDimensions.paddingMedium),
            PrimaryButton(
              text: '自分にVibe通知を送信',
              onPressed: () async {
                final uid = FirebaseAuth.instance.currentUser?.uid;
                if (uid == null) return;
                await _executeAction(
                  loadingMessage: 'Vibe通知を送信中...',
                  successMessage: '✅ Vibe通知を送信しました。通知センターを確認してください。',
                  snackBarMessage: 'Vibe通知を送信しました',
                  action: () async {
                    final result = await FirebaseFunctions.instance
                        .httpsCallable('testVibeNotification')
                        .call({
                      'targetUserId': uid,
                      'skipPostedCheck': true,
                    });
                    final data = result.data as Map<String, dynamic>;
                    if (data['notificationCount'] == 0) {
                      throw Exception('送信対象が0人でした: ${data['message']}');
                    }
                  },
                );
              },
              isLoading: _isLoading,
            ),

            const SizedBox(height: AppDimensions.paddingXLarge),
          ],
        ),
      ),
    );
  }
}
