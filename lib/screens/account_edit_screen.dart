import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show Uint8List;
import 'package:firebase_auth/firebase_auth.dart';
import '../services/user_service.dart';
import '../services/storage_service.dart';
import '../widgets/dialogs/glass_popup.dart';
import '../utils/context_menu_builder.dart';
import '../widgets/common/app_toast.dart';

/// アカウント編集画面
class AccountEditScreen extends StatefulWidget {
  const AccountEditScreen({super.key});

  @override
  State<AccountEditScreen> createState() => _AccountEditScreenState();
}

class _AccountEditScreenState extends State<AccountEditScreen> {
  final UserService _userService = UserService();
  final StorageService _storageService = StorageService();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();
  final TextEditingController _universityController = TextEditingController();

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
    _universityController.dispose();
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
          _universityController.text = userData.university ?? '';
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

  // ヘッダーのユーザー名表示用
  String get _username => _usernameController.text;

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
        AppToast.show(context, '写真を選択しました');
      }
    } else if (result == 'camera') {
      AppToast.show(context, 'カメラ機能は今後実装予定です');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF121212),
        body: Center(
          child: CupertinoActivityIndicator(color: Colors.white, radius: 14),
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
    final university = _universityController.text.trim();

    // バリデーション
    if (name.isEmpty) {
      AppToast.show(context, '名前を入力してください');
      return;
    }

    if (username.isEmpty) {
      AppToast.show(context, 'ユーザー名を入力してください');
      return;
    }

    if (!RegExp(r'^[a-zA-Z0-9_.]+$').hasMatch(username)) {
      AppToast.show(context, 'ユーザー名は英数字・アンダースコア・ドットのみ使用できます');
      return;
    }
    if (username.length < 3 || username.length > 20) {
      AppToast.show(context, 'ユーザー名は3〜20文字で入力してください');
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
        university: university,
      );

      if (mounted) {
        // キーボードを先に閉じる
        FocusScope.of(context).unfocus();
        setState(() {
          _isSaving = false;
        });
        final navigator = Navigator.of(context);
        AppToast.show(context, 'プロフィールを保存しました');
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
        AppToast.show(context, '保存に失敗しました: $e');
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
            onTap: () => _showEditDialog('ユーザー名', _usernameController, isUsername: true),
          ),
          // 自己紹介
          _buildInfoRow(
            label: '自己紹介',
            value: _bioController.text,
            onTap: () => _showEditDialog('自己紹介', _bioController),
          ),
          // 大学
          _buildInfoRow(
            label: '大学',
            value: _universityController.text,
            onTap: _showUniversityPicker,
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

  /// 大学選択ピッカー
  void _showUniversityPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _UniversityPickerSheet(
        current: _universityController.text,
      ),
    ).then((result) {
      if (result != null && mounted) {
        setState(() {
          _universityController.text = result as String;
        });
      }
    });
  }

  /// 編集ダイアログ
  void _showEditDialog(String title, TextEditingController targetController, {bool isUsername = false}) {
    showCupertinoDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => _EditDialog(
        title: title,
        initialValue: targetController.text,
        isUsername: isUsername,
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
  final bool isUsername;

  const _EditDialog({
    required this.title,
    required this.initialValue,
    this.isUsername = false,
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
          placeholder: widget.isUsername
              ? '英数字・_・.のみ'
              : '${widget.title}を入力',
          clearButtonMode: OverlayVisibilityMode.editing,
          keyboardType: widget.isUsername
              ? TextInputType.visiblePassword
              : TextInputType.text,
          autocorrect: !widget.isUsername,
          enableSuggestions: !widget.isUsername,
          inputFormatters: widget.isUsername
              ? [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_.]'))]
              : null,
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

/// 大学選択ボトムシート
class _UniversityPickerSheet extends StatefulWidget {
  final String current;
  const _UniversityPickerSheet({required this.current});

  @override
  State<_UniversityPickerSheet> createState() => _UniversityPickerSheetState();
}

class _UniversityPickerSheetState extends State<_UniversityPickerSheet> {
  static const _universities = [
    // ── 旧帝国大学 ──
    '北海道大学', '東北大学', '東京大学', '名古屋大学', '京都大学', '大阪大学', '九州大学',
    // ── 主要国立大学 ──
    '筑波大学', '一橋大学', '東京工業大学', '神戸大学', '千葉大学', '横浜国立大学',
    '埼玉大学', '東京外国語大学', '東京農工大学', '電気通信大学', '東京海洋大学',
    '金沢大学', '新潟大学', '信州大学', '静岡大学', '岐阜大学', '三重大学',
    '広島大学', '岡山大学', '山口大学', '熊本大学', '長崎大学', '鹿児島大学',
    '富山大学', '福井大学', '山梨大学', '徳島大学', '香川大学', '愛媛大学', '高知大学',
    '島根大学', '鳥取大学', '秋田大学', '山形大学', '福島大学', '弘前大学', '岩手大学',
    '大分大学', '宮崎大学', '琉球大学',
    // ── 公立大学 ──
    '大阪公立大学', '東京都立大学', '横浜市立大学', '名古屋市立大学', '京都府立大学',
    '兵庫県立大学', '広島市立大学', '北九州市立大学', '静岡県立大学', '愛知県立大学',
    // ── 主要私立大学（関東） ──
    '慶應義塾大学', '早稲田大学', '上智大学', '東京理科大学', '明治大学', '青山学院大学',
    '立教大学', '中央大学', '法政大学', '学習院大学', '成蹊大学', '成城大学',
    '武蔵大学', '明治学院大学', '獨協大学', '國學院大學', '駒澤大学', '専修大学',
    '東洋大学', '日本大学', '東海大学', '神奈川大学', '芝浦工業大学', '工学院大学',
    '東京電機大学', '玉川大学', '帝京大学', '大東文化大学', '亜細亜大学',
    '國士舘大学', '拓殖大学', '文教大学', '武蔵野大学', '昭和女子大学',
    '東京女子大学', '日本女子大学', '聖心女子大学', '津田塾大学', '白百合女子大学',
    '北里大学', '順天堂大学', '杏林大学', '東邦大学', '東京医科大学',
    // ── 主要私立大学（関西） ──
    '同志社大学', '立命館大学', '関西大学', '関西学院大学', '近畿大学', '龍谷大学',
    '佛教大学', '京都産業大学', '甲南大学', '摂南大学', '追手門学院大学',
    '桃山学院大学', '大阪経済大学', '大阪工業大学', '大阪薬科大学',
    '兵庫医科大学', '神戸学院大学', '流通科学大学',
    // ── 主要私立大学（その他） ──
    '北海学園大学', '東北学院大学', '東北福祉大学', '日本福祉大学', '名城大学',
    '中京大学', '愛知大学', '南山大学', '西南学院大学', '福岡大学', '久留米大学',
  ];

  late List<String> _filtered;
  late TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _filtered = List.from(_universities);
    _searchController = TextEditingController();
    _searchController.addListener(_onSearch);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearch() {
    final q = _searchController.text.trim();
    setState(() {
      _filtered = q.isEmpty
          ? List.from(_universities)
          : _universities.where((u) => u.contains(q)).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      height: MediaQuery.of(context).size.height * 0.75 + bottom,
      decoration: const BoxDecoration(
        color: Color(0xFF1C1C1C),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // ハンドル
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          // タイトル
          const Text(
            '大学を選択',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          // 検索フィールド
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: CupertinoTextField(
              controller: _searchController,
              placeholder: '大学名を検索',
              placeholderStyle: const TextStyle(color: Colors.white38),
              style: const TextStyle(color: Colors.white),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF2C2C2E),
                borderRadius: BorderRadius.circular(10),
              ),
              prefix: const Padding(
                padding: EdgeInsets.only(left: 10),
                child: Icon(Icons.search, color: Colors.white38, size: 18),
              ),
              clearButtonMode: OverlayVisibilityMode.editing,
            ),
          ),
          const SizedBox(height: 8),
          // 大学リスト
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.only(bottom: 16 + bottom),
              itemCount: _filtered.length,
              separatorBuilder: (_, __) => const Divider(
                height: 1,
                color: Color(0xFF2C2C2E),
                indent: 16,
                endIndent: 16,
              ),
              itemBuilder: (_, i) {
                final name = _filtered[i];
                final isSelected = name == widget.current;
                return InkWell(
                  onTap: () => Navigator.pop(context, name),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: TextStyle(
                              color: isSelected ? const Color(0xFF5D8FFF) : Colors.white,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        if (isSelected)
                          const Icon(Icons.check, color: Color(0xFF5D8FFF), size: 18),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
