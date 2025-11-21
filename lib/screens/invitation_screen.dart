import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 招待画面
class InvitationScreen extends StatelessWidget {
  const InvitationScreen({super.key});

  // ダミーデータ（実際にはFirebaseから取得）
  final String _invitationCode = 'TEST123';
  final int _remainingInvitations = 2;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Column(
          children: [
            // ヘッダー
            _buildHeader(context),

            // メインコンテンツ
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      const SizedBox(height: 17),

                      // 招待コードカード
                      _buildInvitationCard(context),
                    ],
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
  Widget _buildHeader(BuildContext context) {
    return Container(
      height: 45,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          // 戻るボタン
          IconButton(
            icon: const Icon(Icons.chevron_left, color: Colors.white, size: 28),
            onPressed: () => Navigator.pop(context),
          ),
          // タイトル
          const Expanded(
            child: Text(
              '招待',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          // スペーサー（バランス用）
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  /// 招待コードカード
  Widget _buildInvitationCard(BuildContext context) {
    return Container(
      height: 75,
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(15),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: () => _copyInvitationCode(context),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 招待コード（コピーアイコン付き）
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // コピーアイコン
                  _buildCopyIcon(),
                  const SizedBox(width: 8),
                  // 招待コード
                  Text(
                    _invitationCode,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // 残り人数
              Text(
                '残り：$_remainingInvitations人',
                style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// コピーアイコン（2枚の紙が重なったアイコン）
  Widget _buildCopyIcon() {
    return SizedBox(
      width: 20,
      height: 20,
      child: Stack(
        children: [
          // 後ろの紙
          Positioned(
            left: 0,
            top: 0,
            child: Container(
              width: 14,
              height: 16,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 1.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // 前の紙
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 14,
              height: 16,
              decoration: BoxDecoration(
                color: Colors.grey[800],
                border: Border.all(color: Colors.white, width: 1.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 招待コードをコピー
  void _copyInvitationCode(BuildContext context) {
    Clipboard.setData(ClipboardData(text: _invitationCode));
    _showCopiedToast(context);
  }

  /// コピー完了トースト表示
  void _showCopiedToast(BuildContext context) {
    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => _CopiedToast(
        onDismiss: () {
          overlayEntry.remove();
        },
      ),
    );

    overlay.insert(overlayEntry);
  }
}

/// コピー完了トースト
class _CopiedToast extends StatefulWidget {
  final VoidCallback onDismiss;

  const _CopiedToast({required this.onDismiss});

  @override
  State<_CopiedToast> createState() => _CopiedToastState();
}

class _CopiedToastState extends State<_CopiedToast>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _controller.forward();

    // 2秒後に自動で消える
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        _controller.reverse().then((_) {
          widget.onDismiss();
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 100,
      left: 0,
      right: 0,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.grey[800],
              borderRadius: BorderRadius.circular(9),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // チェックマークアイコン
                Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                  ),
                  child: const Icon(
                    Icons.check,
                    color: Color(0xFF424242),
                    size: 16,
                  ),
                ),
                const SizedBox(width: 12),
                // テキスト
                const Text(
                  'コピーしました',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
