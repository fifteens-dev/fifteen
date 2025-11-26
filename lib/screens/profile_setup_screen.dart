import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show Uint8List;
import '../constants/app_colors.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';
import '../services/storage_service.dart';

/// プロフィール設定画面
class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final AuthService _authService = AuthService();
  final UserService _userService = UserService();
  final StorageService _storageService = StorageService();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  Uint8List? _selectedImageBytes;

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

  Future<void> _loadUserData() async {
    // 前の画面から名前とユーザーネームを受け取る
    await Future.delayed(Duration.zero);
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;

    if (args != null) {
      // 前の画面からのデータを使用
      setState(() {
        _nameController.text = args['name'] ?? '';
        _usernameController.text = args['username'] ?? '';
        _bioController.text = ''; // 自己紹介は空欄
        _isLoading = false;
      });
      return;
    }

    // 引数がない場合はFirestoreから読み込み
    final currentUser = _authService.currentUser;
    if (currentUser == null) {
      // Web開発用：Firebase認証がない場合はダミーデータを使用
      setState(() {
        _nameController.text = '後藤　太郎';
        _usernameController.text = 'taroooooda';
        _bioController.text = '';
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
          _bioController.text = ''; // bioフィールドは今後追加予定
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

  /// 写真オプションダイアログを表示
  Future<void> _showPhotoOptionsDialog() async {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: 245,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.9),
              borderRadius: BorderRadius.circular(32),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 写真ライブラリオプション
                InkWell(
                  onTap: () async {
                    Navigator.pop(context); // ダイアログを閉じる
                    // 写真選択画面を開く
                    final result = await Navigator.pushNamed(context, '/photo-picker');
                    if (result != null && mounted && result is Uint8List) {
                      // 選択された画像を保存
                      setState(() {
                        _selectedImageBytes = result;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('写真を選択しました'),
                          backgroundColor: AppColors.success,
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                  child: Container(
                    height: 45,
                    padding: const EdgeInsets.symmetric(horizontal: 23, vertical: 12),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.photo_outlined,
                          size: 20,
                          color: Colors.black,
                        ),
                        const SizedBox(width: 11),
                        Text(
                          '写真ライブラリ',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w400,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // 写真を撮るオプション
                InkWell(
                  onTap: () {
                    Navigator.pop(context); // ダイアログを閉じる
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('カメラ機能は今後実装予定です'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  child: Container(
                    height: 45,
                    padding: const EdgeInsets.symmetric(horizontal: 23, vertical: 12),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.camera_alt,
                          size: 20,
                          color: Colors.black,
                        ),
                        const SizedBox(width: 11),
                        Text(
                          '写真を撮る',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w400,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleNext() async {
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

    final currentUser = _authService.currentUser;

    // Web開発用：Firebase認証がない場合は保存せず次の画面へ
    if (currentUser == null) {
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/music-connection');
      }
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      // プロフィール画像をアップロード（選択されている場合）
      String? profileImageUrl;
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
        // bio: bio, // TODO: UserServiceにbioフィールドを追加
      );

      if (mounted) {
        setState(() {
          _isSaving = false;
        });
        // 音楽ライブラリ接続画面への遷移
        Navigator.of(context).pushReplacementNamed('/music-connection');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('プロフィールの保存に失敗しました: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ヘッダー
            _buildHeader(),

            // メインコンテンツ
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      const SizedBox(height: 14),

                      // プロフィール画像
                      _buildProfileImage(),

                      const SizedBox(height: 50),

                      // 編集可能な情報フィールド
                      _buildEditableField('名前', _nameController),
                      _buildDivider(),

                      _buildEditableField('ユーザー名', _usernameController),
                      _buildDivider(),

                      _buildEditableField('自己紹介', _bioController),
                      _buildDivider(),

                      const SizedBox(height: 28),

                      // 次へボタン
                      _buildNextButton(),

                      const SizedBox(height: 40),
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

  /// ヘッダー（戻るボタン + ユーザー名 + 通知ベル）
  Widget _buildHeader() {
    return Container(
      height: 45,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          // 戻るボタン
          IconButton(
            icon: const Icon(
              Icons.chevron_left,
              color: Colors.white,
              size: 28,
            ),
            onPressed: () => Navigator.pop(context),
          ),

          // ユーザー名（中央）
          Expanded(
            child: Center(
              child: Text(
                _usernameController.text.isEmpty ? 'プロフィール設定' : _usernameController.text,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ),

          // 通知ベル
          IconButton(
            icon: const Icon(
              Icons.notifications_outlined,
              color: Colors.white,
              size: 24,
            ),
            onPressed: () {
              // TODO: 通知画面への遷移
            },
          ),
        ],
      ),
    );
  }

  /// プロフィール画像エリア
  Widget _buildProfileImage() {
    return SizedBox(
      width: 148,
      height: 148,
      child: Stack(
        children: [
          // メインのプロフィール画像
          Container(
            width: 148,
            height: 148,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _selectedImageBytes != null
                  ? Colors.transparent
                  : const Color(0xFF7C7C7C),
            ),
            child: _selectedImageBytes != null
                ? ClipOval(
                    child: Image.memory(
                      _selectedImageBytes!,
                      width: 148,
                      height: 148,
                      fit: BoxFit.cover,
                    ),
                  )
                : const Icon(
                    Icons.account_circle,
                    size: 148,
                    color: Color(0xFF6B6B6B),
                  ),
          ),

          // カメラアイコン（右下）
          Positioned(
            right: 0,
            bottom: 0,
            child: GestureDetector(
              onTap: _showPhotoOptionsDialog,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF9D9D9D),
                  border: Border.all(
                    color: AppColors.background,
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.camera_alt,
                  size: 18,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 編集可能なフィールド（ラベルと入力欄）
  Widget _buildEditableField(String label, TextEditingController controller) {
    return Container(
      height: 49,
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                color: Colors.white,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              style: const TextStyle(
                fontSize: 16,
                color: Colors.white,
                fontWeight: FontWeight.w400,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 区切り線
  Widget _buildDivider() {
    return Container(
      height: 1,
      color: const Color(0xFF4A4A4A),
    );
  }

  /// 次へボタン
  Widget _buildNextButton() {
    return GestureDetector(
      onTap: _isSaving ? null : _handleNext,
      child: Container(
        width: double.infinity,
        height: 43,
        decoration: BoxDecoration(
          color: _isSaving ? Colors.grey : Colors.white,
          borderRadius: BorderRadius.circular(47),
        ),
        child: Center(
          child: _isSaving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Colors.black,
                    strokeWidth: 2,
                  ),
                )
              : const Text(
                  '次へ',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                  ),
                ),
        ),
      ),
    );
  }
}
