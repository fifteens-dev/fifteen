import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../models/vibe_topic_model.dart';
import '../../services/admin_service.dart';
import '../../services/adl_service.dart';
import '../../widgets/common/app_toast.dart';

/// Vibeお題管理タブ
class VibeTopicManagementTab extends StatefulWidget {
  const VibeTopicManagementTab({super.key});

  @override
  State<VibeTopicManagementTab> createState() => _VibeTopicManagementTabState();
}

class _VibeTopicManagementTabState extends State<VibeTopicManagementTab> {
  final AdminService _adminService = AdminService();
  final AdlService _adlService = AdlService();
  bool _isRecomputingPostCounts = false;
  final TextEditingController _titleController = TextEditingController();

  /// 日付をフォーマット
  String _formatDate(DateTime date) {
    return '${date.year}年${date.month.toString().padLeft(2, '0')}月${date.day.toString().padLeft(2, '0')}日';
  }

  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  bool _isCreating = false;
  bool _newTopicIsAdlOnly = false;
  List<VibeTopicModel> _topics = [];
  bool _isLoadingTopics = true;

  @override
  void initState() {
    super.initState();
    _loadTopics();
  }

  Future<void> _loadTopics() async {
    setState(() => _isLoadingTopics = true);
    final topics = await _adminService.getAllVibeTopics();
    if (mounted) {
      setState(() {
        _topics = topics;
        _isLoadingTopics = false;
      });
    }
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF5D8FFF),
              surface: Color(0xFF1E1E1E),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _createTopic() async {
    if (_titleController.text.isEmpty) {
      AppToast.show(context, 'お題のタイトルを入力してください');
      return;
    }

    setState(() => _isCreating = true);

    try {
      await _adminService.createVibeTopic(
        title: _titleController.text,
        date: _selectedDate,
        isAdlOnly: _newTopicIsAdlOnly,
      );

      if (mounted) {
        AppToast.show(context, 'Vibeお題を作成しました');

        // フォームをクリア
        _titleController.clear();
        setState(() {
          _selectedDate = DateTime.now().add(const Duration(days: 1));
          _newTopicIsAdlOnly = false;
        });

        // 一覧を更新
        _loadTopics();
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, '作成に失敗しました: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }

  Future<void> _activateTopic(VibeTopicModel topic) async {
    try {
      await _adminService.updateVibeTopic(
        topicId: topic.topicId,
        status: VibeTopicStatus.active,
      );
      if (mounted) {
        AppToast.show(context, '「${topic.title}」をアクティブにしました');
        _loadTopics();
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, '更新に失敗しました: $e');
      }
    }
  }

  Future<void> _deleteTopic(VibeTopicModel topic) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'お題の削除',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          '「${topic.title}」を削除しますか？\nこの操作は取り消せません。',
          style: const TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('削除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _adminService.deleteVibeTopic(topic.topicId);

      if (mounted) {
        AppToast.show(context, 'お題を削除しました');
        _loadTopics();
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, '削除に失敗しました: $e');
      }
    }
  }

  Future<void> _editTopic(VibeTopicModel topic) async {
    final titleController = TextEditingController(text: topic.title);
    DateTime selectedDate = topic.date;
    bool isAdlOnly = topic.isAdlOnly;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text(
            'お題の編集',
            style: TextStyle(color: Colors.white),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'タイトル',
                    labelStyle: TextStyle(color: Colors.grey),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFF5D8FFF)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    '日付',
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                  subtitle: Text(
                    _formatDate(selectedDate),
                    style: const TextStyle(color: Colors.white),
                  ),
                  trailing: const Icon(Icons.calendar_today, color: Colors.grey),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                      builder: (context, child) {
                        return Theme(
                          data: Theme.of(context).copyWith(
                            colorScheme: const ColorScheme.dark(
                              primary: Color(0xFF5D8FFF),
                              surface: Color(0xFF1E1E1E),
                            ),
                          ),
                          child: child!,
                        );
                      },
                    );
                    if (picked != null) {
                      setDialogState(() => selectedDate = picked);
                    }
                  },
                ),
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  activeColor: const Color(0xFF5D8FFF),
                  title: const Text(
                    'ADL専用お題',
                    style: TextStyle(color: Colors.white, fontSize: 14),
                  ),
                  subtitle: const Text(
                    'ONにするとADL参加者にのみ表示されます',
                    style: TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                  value: isAdlOnly,
                  onChanged: (v) => setDialogState(() => isAdlOnly = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('キャンセル'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, {
                'title': titleController.text,
                'date': selectedDate,
                'isAdlOnly': isAdlOnly,
              }),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5D8FFF),
              ),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;

    try {
      await _adminService.updateVibeTopic(
        topicId: topic.topicId,
        title: result['title'],
        date: result['date'],
        isAdlOnly: result['isAdlOnly'],
      );

      if (mounted) {
        AppToast.show(context, 'お題を更新しました');
        _loadTopics();
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, '更新に失敗しました: $e');
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _recomputeVibePostCounts() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1C),
        title: const Text('Vibe投稿数を再集計しますか？',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: const Text(
          'posts を全走査して vibe_topics.postCount を実態に書き直します。\n'
          '検索画面で「0件」と表示されてしまうドリフトの修正用。',
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル',
                style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('実行',
                style: TextStyle(color: Color(0xFF5D8FFF))),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isRecomputingPostCounts = true);
    try {
      final result = await _adlService.recomputeVibeTopicPostCounts();
      if (!mounted) return;
      AppToast.show(context,
          '再集計: ${result['topicCount']}題 / 投稿あり${result['nonZeroCount']}題');
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, '再集計に失敗しました: $e');
    } finally {
      if (mounted) setState(() => _isRecomputingPostCounts = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 新規お題作成フォーム
          _buildSectionTitle('新規Vibeお題'),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _titleController,
            label: 'お題タイトル',
            hintText: '例: ドライブで聴きたい曲',
          ),
          const SizedBox(height: 12),
          _buildDatePicker(),
          const SizedBox(height: 12),
          _buildAdlOnlySwitch(
            value: _newTopicIsAdlOnly,
            onChanged: (v) => setState(() => _newTopicIsAdlOnly = v),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isCreating ? null : _createTopic,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5D8FFF),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isCreating
                  ? const CupertinoActivityIndicator(
                      color: Colors.white,
                      radius: 10,
                    )
                  : const Text(
                      'お題を作成',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),

          const SizedBox(height: 32),

          // お題一覧
          Row(
            children: [
              Expanded(child: _buildSectionTitle('Vibeお題一覧')),
              _isRecomputingPostCounts
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CupertinoActivityIndicator(color: Colors.white),
                    )
                  : TextButton.icon(
                      onPressed: _recomputeVibePostCounts,
                      icon: const Icon(Icons.refresh,
                          size: 16, color: Color(0xFF5D8FFF)),
                      label: const Text('投稿数再集計',
                          style:
                              TextStyle(color: Color(0xFF5D8FFF), fontSize: 12)),
                    ),
            ],
          ),
          const SizedBox(height: 16),
          _buildTopicList(),
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

  Widget _buildAdlOnlySwitch({
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        activeColor: const Color(0xFF8A2BE2),
        title: const Text(
          'ADL専用お題',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: const Text(
          'ONにするとADL班に参加しているユーザーにのみ表示されます',
          style: TextStyle(color: Colors.grey, fontSize: 11),
        ),
        value: value,
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildDatePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '実施日',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _selectDate,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today, color: Colors.grey),
                const SizedBox(width: 12),
                Text(
                  _formatDate(_selectedDate),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                const Icon(Icons.arrow_drop_down, color: Colors.grey),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTopicList() {
    if (_isLoadingTopics) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CupertinoActivityIndicator(color: Colors.white, radius: 14),
        ),
      );
    }

    if (_topics.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'お題がありません',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _topics.length,
      itemBuilder: (context, index) {
        final topic = _topics[index];
        final topicDate = DateTime(
          topic.date.year,
          topic.date.month,
          topic.date.day,
        );
        final isPast = topicDate.isBefore(today);
        final isToday = topicDate.isAtSameMomentAs(today);

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(12),
            border: isToday
                ? Border.all(color: const Color(0xFF5D8FFF), width: 2)
                : null,
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    topic.title,
                    style: TextStyle(
                      color: isPast ? Colors.grey : Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (topic.isAdlOnly) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8A2BE2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'ADL',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                if (isToday)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF5D8FFF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '本日',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  _formatDate(topic.date),
                  style: TextStyle(
                    color: isPast ? Colors.grey : Colors.white70,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  topic.status.displayName,
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // アーカイブ済みまたは投票中 → アクティブにするボタン
                if (topic.status != VibeTopicStatus.active)
                  IconButton(
                    icon: const Icon(Icons.play_circle_outline, color: Color(0xFF5D8FFF)),
                    tooltip: 'アクティブにする',
                    onPressed: () => _activateTopic(topic),
                  ),
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.grey),
                  onPressed: () => _editTopic(topic),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _deleteTopic(topic),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
