import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../services/admin_service.dart';
import '../../widgets/common/app_toast.dart';

/// 一斉通知タブ
class BroadcastNotificationTab extends StatefulWidget {
  const BroadcastNotificationTab({super.key});

  @override
  State<BroadcastNotificationTab> createState() =>
      _BroadcastNotificationTabState();
}

class _BroadcastNotificationTabState extends State<BroadcastNotificationTab> {
  final AdminService _adminService = AdminService();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _bodyController = TextEditingController();

  String _selectedActionType = 'announcement';
  bool _isSending = false;
  List<Map<String, dynamic>> _notificationHistory = [];
  bool _isLoadingHistory = true;

  final List<Map<String, String>> _actionTypes = [
    {'value': 'announcement', 'label': 'お知らせ'},
    {'value': 'vibe', 'label': 'Vibe関連'},
    {'value': 'update', 'label': 'アップデート'},
    {'value': 'event', 'label': 'イベント'},
  ];

  @override
  void initState() {
    super.initState();
    _loadNotificationHistory();
  }

  Future<void> _loadNotificationHistory() async {
    setState(() => _isLoadingHistory = true);
    final history = await _adminService.getBroadcastNotificationHistory();
    if (mounted) {
      setState(() {
        _notificationHistory = history;
        _isLoadingHistory = false;
      });
    }
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}/${dateTime.month.toString().padLeft(2, '0')}/${dateTime.day.toString().padLeft(2, '0')} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _sendNotification() async {
    if (_titleController.text.isEmpty || _bodyController.text.isEmpty) {
      AppToast.show(context, 'タイトルと本文を入力してください');
      return;
    }

    // 確認ダイアログ
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          '一斉通知の送信',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '以下の内容で全ユーザーに通知を送信しますか？',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Text(
              'タイトル: ${_titleController.text}',
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              '本文: ${_bodyController.text}',
              style: const TextStyle(color: Colors.white70),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5D8FFF),
            ),
            child: const Text('送信'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSending = true);

    try {
      await _adminService.sendBroadcastNotification(
        title: _titleController.text,
        body: _bodyController.text,
        actionType: _selectedActionType,
      );

      if (mounted) {
        AppToast.show(context, '一斉通知を送信しました');

        // フォームをクリア
        _titleController.clear();
        _bodyController.clear();
        setState(() => _selectedActionType = 'announcement');

        // 履歴を更新
        _loadNotificationHistory();
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, '送信に失敗しました: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 新規通知フォーム
          _buildSectionTitle('新規一斉通知'),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _titleController,
            label: 'タイトル',
            hintText: '通知のタイトルを入力',
          ),
          const SizedBox(height: 12),
          _buildTextField(
            controller: _bodyController,
            label: '本文',
            hintText: '通知の本文を入力',
            maxLines: 4,
          ),
          const SizedBox(height: 12),
          _buildDropdown(),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSending ? null : _sendNotification,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5D8FFF),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isSending
                  ? const CupertinoActivityIndicator(
                      color: Colors.white,
                      radius: 10,
                    )
                  : const Text(
                      '通知を送信',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),

          const SizedBox(height: 32),

          // 送信履歴
          _buildSectionTitle('送信履歴'),
          const SizedBox(height: 16),
          _buildNotificationHistory(),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hintText,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: maxLines,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: const TextStyle(color: Colors.grey),
            filled: true,
            fillColor: const Color(0xFF1E1E1E),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF5D8FFF)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '通知タイプ',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(12),
          ),
          child: DropdownButton<String>(
            value: _selectedActionType,
            isExpanded: true,
            dropdownColor: const Color(0xFF1E1E1E),
            underline: const SizedBox(),
            style: const TextStyle(color: Colors.white),
            items: _actionTypes.map((type) {
              return DropdownMenuItem<String>(
                value: type['value'],
                child: Text(type['label']!),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => _selectedActionType = value);
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildNotificationHistory() {
    if (_isLoadingHistory) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CupertinoActivityIndicator(color: Colors.white, radius: 14),
        ),
      );
    }

    if (_notificationHistory.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            '送信履歴がありません',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _notificationHistory.length,
      itemBuilder: (context, index) {
        final notification = _notificationHistory[index];
        final sentAt = notification['sentAt']?.toDate();
        final dateStr = sentAt != null
            ? _formatDateTime(sentAt)
            : '不明';

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      notification['title'] ?? '',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF5D8FFF).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      notification['actionType'] ?? 'announcement',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF5D8FFF),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                notification['body'] ?? '',
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Text(
                dateStr,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
