import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show Uint8List;
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';
import '../services/storage_service.dart';
import '../models/user_model.dart';
import '../constants/app_colors.dart';
import '../widgets/dialogs/glass_popup.dart';

/// アカウント編集画面
class AccountEditScreen extends StatefulWidget {
  const AccountEditScreen({super.key});

  @override
  State<AccountEditScreen> createState() => _AccountEditScreenState();
}

class _AccountEditScreenState extends State<AccountEditScreen> {
  final AuthService _authService = AuthService();
  final UserService _userService = UserService();
  final StorageService _storageService = StorageService();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  Uint8List? _selectedImageBytes;
  String? _currentProfileImageUrl;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  /// ユーザーデータを読み込み
  Future<void> _loadUserData() async {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      final userData = await _userService.getUser(currentUser.uid);
      if (mounted && userData != null) {
        setState(() {
          _nameController.text = userData.name ?? '';
          _usernameController.text = userData.username ?? '';
          _bioController.text = userData.bio ?? '';
          _currentProfileImageUrl = userData.profileImageUrl;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // 便利メソッド：TextControllerからStringを取得
  String get _name => _nameController.text;
  String get _username => _usernameController.text;
  String get _bio => _bioController.text;

  /// 写真オプションダイアログを表示
  Future<void> _showPhotoOptionsDialog() async {
    final screenSize = MediaQuery.of(context).size;
    final result = await GlassPopup.show<String>(
      context: context,
      position: Offset(screenSize.width / 2 - 110, screenSize.height / 2 - 44),
      width: 220,
      items: const [
        GlassPopupItem<String>(
          value: 'library',
          label: '写真ライブラリ',
          icon: Icons.photo_outlined,
        ),
        GlassPopupItem<String>(
          value: 'camera',
          label: '写真を撮る',
          icon: Icons.camera_alt,
        ),
      ],
    );

    if (result == 'library') {
      final pickerResult = await Navigator.pushNamed(context, '/photo-picker');
      if (pickerResult != null && mounted && pickerResult is Uint8List) {
        setState(() {
          _selectedImageBytes = pickerResult;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('写真を選択しました'),
            backgroundColor: AppColors.success,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } else if (result == 'camera') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('カメラ機能は今後実装予定です'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF121212),
        body: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

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

  /// 保存処理
  Future<void> _handleSave() async {
    final name = _nameController.text.trim();
    final username = _usernameController.text.trim();
    final bio = _bioController.text.trim();

    // バリデーション
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('名前を入力してください'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ユーザー名を入力してください'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      Navigator.pop(context);
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      // プロフィール画像をアップロード（選択されている場合）
      String? profileImageUrl = _currentProfileImageUrl;
      if (_selectedImageBytes != null) {
        profileImageUrl = await _storageService.uploadProfileImage(
          userId: currentUser.uid,
          imageBytes: _selectedImageBytes!,
        );
      }

      // Firestoreに保存
      await _userService.updateUser(
        uid: currentUser.uid,
        name: name,
        username: username,
        profileImageUrl: profileImageUrl,
        bio: bio,
      );

      if (mounted) {
        // キーボードを先に閉じる
        FocusScope.of(context).unfocus();
        setState(() {
          _isSaving = false;
        });
        final messenger = ScaffoldMessenger.of(context);
        final navigator = Navigator.of(context);
        messenger.showSnackBar(
          const SnackBar(
            content: Text('プロフィールを保存しました'),
            backgroundColor: AppColors.success,
          ),
        );
        // キーボードが完全に閉じてから画面を戻す
        await Future.delayed(const Duration(milliseconds: 100));
        if (mounted) {
          navigator.pop();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存に失敗しました: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
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
            onPressed: _isSaving ? null : _handleSave,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Color(0xFF5D8FFF),
                      strokeWidth: 2,
                    ),
                  )
                : const Text(
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
      onTap: _showPhotoOptionsDialog,
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
                  child: _selectedImageBytes != null
                      ? Image.memory(
                          _selectedImageBytes!,
                          width: 123,
                          height: 123,
                          fit: BoxFit.cover,
                        )
                      : _currentProfileImageUrl != null
                          ? CachedNetworkImage(
                              imageUrl: _currentProfileImageUrl!,
                              width: 123,
                              height: 123,
                              fit: BoxFit.cover,
                              errorWidget: (context, url, error) {
                                return Icon(
                                  Icons.person,
                                  size: 60,
                                  color: Colors.grey[600],
                                );
                              },
                            )
                          : Icon(
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
            value: _nameController.text,
            onTap: () => _showEditDialog('名前', _nameController),
          ),
          // ユーザー名
          _buildInfoRow(
            label: 'ユーザー名',
            value: _usernameController.text,
            onTap: () => _showEditDialog('ユーザー名', _usernameController),
          ),
          // 自己紹介
          _buildInfoRow(
            label: '自己紹介',
            value: _bioController.text,
            onTap: () => _showEditDialog('自己紹介', _bioController),
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
  void _showEditDialog(String title, TextEditingController targetController) {
    showCupertinoDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => _EditDialog(
        title: title,
        initialValue: targetController.text,
      ),
    ).then((result) {
      if (result != null && mounted) {
        setState(() {
          targetController.text = result;
        });
      }
    });
  }
}

/// 編集ダイアログ（独立したStatefulWidgetでcontrollerのライフサイクルを管理）
class _EditDialog extends StatefulWidget {
  final String title;
  final String initialValue;

  const _EditDialog({
    required this.title,
    required this.initialValue,
  });

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoAlertDialog(
      title: Text(widget.title),
      content: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: CupertinoTextField(
          controller: _controller,
          autofocus: true,
          placeholder: '${widget.title}を入力',
          clearButtonMode: OverlayVisibilityMode.editing,
        ),
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('保存'),
        ),
      ],
    );
  }
}
