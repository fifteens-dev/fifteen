import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';
import '../constants/app_dimensions.dart';
import '../widgets/primary_button.dart';
import '../widgets/common_input_field.dart';
import '../services/post_service.dart';
import '../services/user_service.dart';
import '../models/track_model.dart';

/// 投稿作成画面
class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _formKey = GlobalKey<FormState>();
  final _trackNameController = TextEditingController();
  final _artistNameController = TextEditingController();
  final _albumImageUrlController = TextEditingController();

  final PostService _postService = PostService();
  final UserService _userService = UserService();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _isLoading = false;

  @override
  void dispose() {
    _trackNameController.dispose();
    _artistNameController.dispose();
    _albumImageUrlController.dispose();
    super.dispose();
  }

  /// 投稿を作成
  Future<void> _createPost() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      _showMessage('ログインしてください');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // ユーザー情報を取得
      final userModel = await _userService.getUser(currentUser.uid);
      if (userModel == null) {
        _showMessage('ユーザー情報の取得に失敗しました');
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // トラック情報を作成
      final track = TrackModel(
        trackId: DateTime.now().millisecondsSinceEpoch.toString(),
        trackName: _trackNameController.text.trim(),
        artistName: _artistNameController.text.trim(),
        albumImageUrl: _albumImageUrlController.text.trim(),
      );

      // 投稿を作成
      await _postService.createPost(
        userId: currentUser.uid,
        username: userModel.username ?? 'Unknown',
        userIconUrl: userModel.profileImageUrl,
        trackData: track.toMap(),
      );

      if (mounted) {
        _showMessage('投稿が完了しました！');
        Navigator.of(context).pop(); // 前の画面に戻る
      }
    } catch (e) {
      _showMessage('投稿に失敗しました: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// メッセージを表示
  void _showMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('投稿作成', style: AppTextStyles.appTitle),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.paddingLarge,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 24),

                // 説明テキスト
                const Text(
                  '共有したい音楽のトラック情報を入力してください',
                  style: AppTextStyles.body,
                ),
                const SizedBox(height: 32),

                // 曲名入力
                const Text(
                  '曲名',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                CommonInputField(
                  controller: _trackNameController,
                  hintText: '例: いとしのエリー',
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return '曲名を入力してください';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),

                // アーティスト名入力
                const Text(
                  'アーティスト名',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                CommonInputField(
                  controller: _artistNameController,
                  hintText: '例: サザンオールスターズ',
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'アーティスト名を入力してください';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),

                // アルバム画像URL入力（オプション）
                const Text(
                  'アルバム画像URL（オプション）',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                CommonInputField(
                  controller: _albumImageUrlController,
                  hintText: 'https://example.com/album.jpg',
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 8),
                Text(
                  '※ 画像URLを入力しない場合は、デフォルトのアイコンが表示されます',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 48),

                // 投稿ボタン
                PrimaryButton(
                  text: '投稿する',
                  onPressed: _createPost,
                  isLoading: _isLoading,
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
