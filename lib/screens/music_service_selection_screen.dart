import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../models/music_service_type.dart';
import '../services/music_service_manager.dart';
import '../services/apple_music_service.dart';
import '../widgets/dialogs/bottom_sheet_dialog.dart';
import '../widgets/common/app_toast.dart';

/// 音楽サービス選択画面
class MusicServiceSelectionScreen extends StatefulWidget {
  const MusicServiceSelectionScreen({super.key});

  @override
  State<MusicServiceSelectionScreen> createState() =>
      _MusicServiceSelectionScreenState();
}

class _MusicServiceSelectionScreenState
    extends State<MusicServiceSelectionScreen> {
  final MusicServiceManager _manager = MusicServiceManager();
  MusicServiceType? _selectedService;
  bool _isAuthenticated = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCurrentService();
  }

  Future<void> _loadCurrentService() async {
    setState(() => _isLoading = true);

    final service = await _manager.getSelectedService();
    final authenticated = await _manager.isAuthenticated();

    if (mounted) {
      setState(() {
        _selectedService = service;
        _isAuthenticated = authenticated;
        _isLoading = false;
      });
    }
  }

  Future<void> _selectService(MusicServiceType service) async {
    setState(() => _isLoading = true);

    await _manager.setSelectedService(service);

    if (service != MusicServiceType.none) {
      // ログインを試みる
      final success = await _manager.login();

      if (mounted) {
        if (success) {
          // Apple Musicの場合はサブスクリプション確認
          if (service == MusicServiceType.appleMusic) {
            final hasSubscription =
                await AppleMusicService().checkSubscriptionAccess();
            if (mounted && !hasSubscription) {
              await BottomSheetDialog.showAppleMusicNoSubscription(context);
            } else if (mounted) {
              AppToast.show(context, '${service.displayName}に連携しました');
            }
          } else {
            AppToast.show(context, '${service.displayName}に連携しました');
          }
        } else {
          AppToast.show(context, '${service.displayName}の連携に失敗しました');
        }
      }
    }

    await _loadCurrentService();
  }

  Future<void> _disconnect() async {
    setState(() => _isLoading = true);

    await _manager.logout();
    await _manager.setSelectedService(MusicServiceType.none);

    if (mounted) {
      AppToast.show(context, '音楽サービスとの連携を解除しました');
    }

    await _loadCurrentService();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          '音楽サービス連携',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(
              child: CupertinoActivityIndicator(color: Color(0xFF5D8FFF), radius: 14),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 現在の連携状態
                  if (_selectedService != MusicServiceType.none &&
                      _isAuthenticated) ...[
                    _buildCurrentServiceCard(),
                    const SizedBox(height: 24),
                  ],

                  // 説明
                  const Text(
                    '音楽サービスと連携すると',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildFeatureItem('キュレーションされたプレイリストにアクセス'),
                  _buildFeatureItem('より正確なおすすめ楽曲の取得'),
                  _buildFeatureItem('プレミアム音質でのプレビュー再生'),
                  const SizedBox(height: 32),

                  // サービス選択
                  const Text(
                    '音楽サービスを選択',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),

                  _buildServiceCard(
                    service: MusicServiceType.spotify,
                    title: 'Spotify',
                    description: '世界最大の音楽ストリーミングサービス',
                    iconPath: 'assets/icons/Spotify.png',
                  ),
                  const SizedBox(height: 12),

                  _buildServiceCard(
                    service: MusicServiceType.appleMusic,
                    title: 'Apple Music',
                    description: 'Appleの音楽ストリーミングサービス',
                    iconPath: 'assets/icons/Apple_Music.png',
                  ),
                  const SizedBox(height: 32),

                  // 連携解除ボタン
                  if (_selectedService != MusicServiceType.none &&
                      _isAuthenticated)
                    Center(
                      child: TextButton(
                        onPressed: _disconnect,
                        child: const Text(
                          '連携を解除',
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFFE53935),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildCurrentServiceCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF4CAF50),
          width: 2,
        ),
      ),
      child: Row(
        children: [
          if (_selectedService!.iconPath.isNotEmpty)
            Image.asset(
              _selectedService!.iconPath,
              width: 40,
              height: 40,
            ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _selectedService!.displayName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  '連携済み',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF4CAF50),
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.check_circle,
            color: Color(0xFF4CAF50),
            size: 24,
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const Icon(
            Icons.check,
            color: Color(0xFF5D8FFF),
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF9F9F9F),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceCard({
    required MusicServiceType service,
    required String title,
    required String description,
    required String iconPath,
  }) {
    final isSelected = _selectedService == service && _isAuthenticated;

    return GestureDetector(
      onTap: () => _selectService(service),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF5D8FFF) : const Color(0xFF2D2D2D),
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Image.asset(
              iconPath,
              width: 48,
              height: 48,
              errorBuilder: (context, error, stackTrace) {
                return const Icon(
                  Icons.music_note,
                  color: Colors.white,
                  size: 48,
                );
              },
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF9F9F9F),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              isSelected ? Icons.check_circle : Icons.arrow_forward_ios,
              color: isSelected ? const Color(0xFF5D8FFF) : const Color(0xFF9F9F9F),
              size: isSelected ? 24 : 16,
            ),
          ],
        ),
      ),
    );
  }
}
