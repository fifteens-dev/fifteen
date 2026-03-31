import 'package:flutter/material.dart';
import '../utils/context_menu_builder.dart';

/// お問い合わせ画面
class ContactScreen extends StatefulWidget {
  const ContactScreen({super.key});

  @override
  State<ContactScreen> createState() => _ContactScreenState();
}

class _ContactScreenState extends State<ContactScreen> {
  final TextEditingController _messageController = TextEditingController();

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

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
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    const SizedBox(height: 17),

                    // テキスト入力エリア
                    _buildMessageInput(),

                    const Spacer(),

                    // 送信ボタン
                    _buildSendButton(),

                    const SizedBox(height: 16),
                  ],
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
              'お問い合わせ',
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

  /// テキスト入力エリア
  Widget _buildMessageInput() {
    return Container(
      height: 125,
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF5D5D5D)),
        borderRadius: BorderRadius.circular(15),
      ),
      child: TextField(
        controller: _messageController,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        contextMenuBuilder: buildTextContextMenu,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
        ),
        decoration: const InputDecoration(
          hintText: 'お困りの内容を教えてください',
          hintStyle: TextStyle(
            color: Color(0xFF99999B),
            fontSize: 12,
          ),
          border: InputBorder.none,
          contentPadding: EdgeInsets.all(13),
        ),
      ),
    );
  }

  /// 送信ボタン
  Widget _buildSendButton() {
    return GestureDetector(
      onTap: _handleSend,
      child: Container(
        width: double.infinity,
        height: 43,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(47),
        ),
        child: const Center(
          child: Text(
            '送信',
            style: TextStyle(
              color: Colors.black,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  /// 送信処理
  void _handleSend() {
    final message = _messageController.text.trim();
    if (message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('お問い合わせ内容を入力してください'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // TODO: 実際の送信処理を実装
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('お問い合わせを送信しました'),
        backgroundColor: Colors.green,
      ),
    );
    Navigator.pop(context);
  }
}
