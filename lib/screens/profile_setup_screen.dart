import 'package:flutter/material.dart';
import 'dart:io';
import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';
import '../constants/app_dimensions.dart';
import '../widgets/common_input_field.dart';
import '../widgets/primary_button.dart';

/// プロフィール設定画面
class ProfileSetupScreen extends StatefulWidget {
  final String username;
  final String name;

  const ProfileSetupScreen({
    super.key,
    this.username = 'taroooooda',
    this.name = '後藤　太郎',
  });

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final TextEditingController _bioController = TextEditingController();
  File? _profileImage;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _bioController.text = 'aoyama'; // デモ用の初期値
  }

  @override
  void dispose() {
    _bioController.dispose();
    super.dispose();
  }

  void _handleImagePick() {
    // TODO: 画像選択機能を実装
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('画像選択機能は開発中です'),
      ),
    );
  }

  void _handleNext() {
    setState(() {
      _isLoading = true;
    });

    // TODO: プロフィール情報を保存してホーム画面へ遷移
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('プロフィール設定が完了しました！'),
            backgroundColor: AppColors.success,
          ),
        );
        // TODO: ホーム画面への遷移を実装
      }
    });
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
        title: Text(widget.username, style: AppTextStyles.heading),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.paddingLarge,
          ),
          child: Column(
            children: [
              const SizedBox(height: 40),
              // プロフィール画像
              Stack(
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.surface,
                      border: Border.all(
                        color: AppColors.border,
                        width: 2,
                      ),
                    ),
                    child: _profileImage != null
                        ? ClipOval(
                            child: Image.file(
                              _profileImage!,
                              fit: BoxFit.cover,
                            ),
                          )
                        : const Icon(
                            Icons.person,
                            size: 60,
                            color: AppColors.textSecondary,
                          ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: GestureDetector(
                      onTap: _handleImagePick,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.buttonPrimary,
                        ),
                        child: const Icon(
                          Icons.camera_alt,
                          color: AppColors.buttonText,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppDimensions.paddingXLarge),
              // プロフィール情報表示
              _buildProfileInfoRow('名前', widget.name),
              const SizedBox(height: AppDimensions.paddingMedium),
              _buildProfileInfoRow('ユーザー名', widget.username),
              const SizedBox(height: AppDimensions.paddingMedium),
              // 自己紹介
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8.0),
                    child: Text(
                      '自己紹介',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  CommonInputField(
                    controller: _bioController,
                    hintText: '自己紹介を入力',
                    keyboardType: TextInputType.multiline,
                    maxLines: 3,
                    maxLength: 150,
                  ),
                ],
              ),
              const SizedBox(height: AppDimensions.paddingXLarge),
              PrimaryButton(
                text: '次へ',
                onPressed: _handleNext,
                isLoading: _isLoading,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileInfoRow(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.paddingMedium,
        vertical: AppDimensions.paddingMedium,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppColors.border,
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 16,
            ),
          ),
          Text(
            value,
            style: AppTextStyles.body,
          ),
        ],
      ),
    );
  }
}
