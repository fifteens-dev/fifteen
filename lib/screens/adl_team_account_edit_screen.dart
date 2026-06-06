import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter/material.dart';
import '../models/adl_team_model.dart';
import '../services/adl_service.dart';
import '../services/storage_service.dart';
import '../utils/context_menu_builder.dart';
import '../widgets/common/app_toast.dart';
import '../widgets/dialogs/glass_popup.dart';

/// ADL班のアカウント編集画面（管理者用）。
/// 画面トップにアイコン編集、下に名前（編集不可）と紹介文を縦に並べる。
class AdlTeamAccountEditScreen extends StatefulWidget {
  final AdlTeamModel team;
  final String displayName;

  const AdlTeamAccountEditScreen({
    super.key,
    required this.team,
    required this.displayName,
  });

  @override
  State<AdlTeamAccountEditScreen> createState() =>
      _AdlTeamAccountEditScreenState();
}

class _AdlTeamAccountEditScreenState extends State<AdlTeamAccountEditScreen> {
  final AdlService _adlService = AdlService();
  final StorageService _storageService = StorageService();
  final TextEditingController _descController = TextEditingController();

  Uint8List? _selectedImageBytes;
  String? _currentProfileImageUrl;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _currentProfileImageUrl = widget.team.profileImageUrl;
    _descController.text = widget.team.description ?? '';
  }

  @override
  void dispose() {
    _descController.dispose();
    super.dispose();
  }

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
        AppToast.show(context, '写真を選択しました');
      }
    } else if (result == 'camera') {
      AppToast.show(context, 'カメラ機能は今後実装予定です');
    }
  }

  Future<void> _handleSave() async {
    setState(() => _isSaving = true);
    try {
      String? profileImageUrl = _currentProfileImageUrl;
      if (_selectedImageBytes != null) {
        profileImageUrl = await _storageService.uploadAdlTeamImage(
          teamId: widget.team.teamId,
          imageBytes: _selectedImageBytes!,
        );
      }
      await _adlService.updateTeamProfile(
        teamId: widget.team.teamId,
        profileImageUrl: profileImageUrl,
        description: _descController.text.trim(),
      );
      if (!mounted) return;
      FocusScope.of(context).unfocus();
      setState(() => _isSaving = false);
      final navigator = Navigator.of(context);
      AppToast.show(context, '班プロフィールを保存しました');
      await Future.delayed(const Duration(milliseconds: 100));
      if (mounted) navigator.pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        AppToast.show(context, '保存に失敗しました: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    const SizedBox(height: 14),
                    _buildProfilePhoto(),
                    const SizedBox(height: 50),
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

  Widget _buildHeader() {
    return Container(
      height: 45,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, color: Colors.white, size: 28),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Text(
              widget.displayName,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          TextButton(
            onPressed: _isSaving ? null : _handleSave,
            child: _isSaving
                ? const CupertinoActivityIndicator(
                    color: Color(0xFF5D8FFF),
                    radius: 10,
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

  Widget _buildProfilePhoto() {
    return GestureDetector(
      onTap: _showPhotoOptionsDialog,
      child: SizedBox(
        width: 148,
        height: 148,
        child: Stack(
          children: [
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
                      : (_currentProfileImageUrl != null &&
                              _currentProfileImageUrl!.isNotEmpty)
                          ? CachedNetworkImage(
                              imageUrl: _currentProfileImageUrl!,
                              width: 123,
                              height: 123,
                              fit: BoxFit.cover,
                              errorWidget: (context, url, error) =>
                                  _initialPlaceholder(),
                            )
                          : _initialPlaceholder(),
                ),
              ),
            ),
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

  Widget _initialPlaceholder() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1937EF), Color(0xFFFE1F56)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        widget.displayName.isNotEmpty
            ? widget.displayName.substring(0, 1).toUpperCase()
            : '?',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 48,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildProfileInfo() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          // 名前（編集不可）
          _buildInfoRow(
            label: '名前',
            value: widget.displayName,
            onTap: null,
          ),
          // 紹介文
          _buildInfoRow(
            label: '紹介文',
            value: _descController.text,
            onTap: () => _showEditDialog('紹介文', _descController),
            showBottomDivider: true,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required String label,
    required String value,
    required VoidCallback? onTap,
    bool showBottomDivider = false,
  }) {
    final isReadOnly = onTap == null;
    return Column(
      children: [
        Container(height: 1, color: const Color(0xFF3C3C3C)),
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
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
                Expanded(
                  child: Text(
                    value,
                    style: TextStyle(
                      color: isReadOnly ? Colors.white54 : Colors.white,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (showBottomDivider)
          Container(height: 1, color: const Color(0xFF3C3C3C)),
      ],
    );
  }

  void _showEditDialog(String title, TextEditingController target) {
    showCupertinoDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _EditDialog(title: title, initialValue: target.text),
    ).then((result) {
      if (result != null && mounted) {
        setState(() {
          target.text = result;
        });
      }
    });
  }
}

class _EditDialog extends StatefulWidget {
  final String title;
  final String initialValue;
  const _EditDialog({required this.title, required this.initialValue});

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
          maxLines: 4,
          minLines: 1,
          contextMenuBuilder: buildTextContextMenu,
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
