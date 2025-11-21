import 'package:flutter/material.dart';

/// アカウント編集画面
class AccountEditScreen extends StatefulWidget {
  const AccountEditScreen({super.key});

  @override
  State<AccountEditScreen> createState() => _AccountEditScreenState();
}

class _AccountEditScreenState extends State<AccountEditScreen> {
  // ダミーデータ（実際にはFirestoreから取得）
  String _name = '後藤　太郎';
  String _username = 'taroooooda';
  String _bio = 'aoyama';

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
                child: Column(
                  children: [
                    const SizedBox(height: 14),

                    // プロフィール画像
                    _buildProfilePhoto(),

                    const SizedBox(height: 50),

                    // プロフィール情報
                    _buildProfileInfo(),
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
          // タイトル（ユーザーID）
          Expanded(
            child: Text(
              _username,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          // 保存ボタン
          TextButton(
            onPressed: () {
              // TODO: 保存処理
              Navigator.pop(context);
            },
            child: const Text(
              '保存',
              style: TextStyle(
                color: Color(0xFF5D8FFF),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// プロフィール画像
  Widget _buildProfilePhoto() {
    return GestureDetector(
      onTap: () {
        // TODO: 画像選択処理
      },
      child: SizedBox(
        width: 148,
        height: 148,
        child: Stack(
          children: [
            // プロフィール画像
            Center(
              child: Container(
                width: 123,
                height: 123,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.grey[800],
                ),
                child: ClipOval(
                  child: Icon(
                    Icons.person,
                    size: 60,
                    color: Colors.grey[600],
                  ),
                ),
              ),
            ),
            // カメラアイコン
            Positioned(
              right: 13,
              bottom: 13,
              child: Container(
                width: 34,
                height: 34,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
                child: const Icon(
                  Icons.camera_alt,
                  size: 20,
                  color: Colors.black,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// プロフィール情報
  Widget _buildProfileInfo() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          // 名前
          _buildInfoRow(
            label: '名前',
            value: _name,
            onTap: () => _showEditDialog('名前', _name, (value) {
              setState(() => _name = value);
            }),
          ),
          // ユーザー名
          _buildInfoRow(
            label: 'ユーザー名',
            value: _username,
            onTap: () => _showEditDialog('ユーザー名', _username, (value) {
              setState(() => _username = value);
            }),
          ),
          // 自己紹介
          _buildInfoRow(
            label: '自己紹介',
            value: _bio,
            onTap: () => _showEditDialog('自己紹介', _bio, (value) {
              setState(() => _bio = value);
            }),
            showBottomDivider: true,
          ),
        ],
      ),
    );
  }

  /// 情報行
  Widget _buildInfoRow({
    required String label,
    required String value,
    required VoidCallback onTap,
    bool showBottomDivider = false,
  }) {
    return Column(
      children: [
        // 上部の区切り線
        Container(
          height: 1,
          color: const Color(0xFF3C3C3C),
        ),
        // コンテンツ
        InkWell(
          onTap: onTap,
          child: Container(
            height: 49,
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: [
                SizedBox(
                  width: 84,
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // 下部の区切り線（最後の項目のみ）
        if (showBottomDivider)
          Container(
            height: 1,
            color: const Color(0xFF3C3C3C),
          ),
      ],
    );
  }

  /// 編集ダイアログ
  void _showEditDialog(String title, String currentValue, Function(String) onSave) {
    final controller = TextEditingController(text: currentValue);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text(
          title,
          style: const TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: '$titleを入力',
            hintStyle: TextStyle(color: Colors.grey[600]),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white54),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF5D8FFF)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'キャンセル',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          TextButton(
            onPressed: () {
              onSave(controller.text);
              Navigator.pop(context);
            },
            child: const Text(
              '保存',
              style: TextStyle(color: Color(0xFF5D8FFF)),
            ),
          ),
        ],
      ),
    );
  }
}
