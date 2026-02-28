import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/vibe_topic_model.dart';
import '../services/vibe_topic_service.dart';
import '../constants/app_colors.dart';
import '../constants/predefined_vibe_topics.dart';

/// Vibeお題投票画面
class VibeTopicVotingScreen extends StatefulWidget {
  const VibeTopicVotingScreen({super.key});

  @override
  State<VibeTopicVotingScreen> createState() => _VibeTopicVotingScreenState();
}

class _VibeTopicVotingScreenState extends State<VibeTopicVotingScreen> {
  final VibeTopicService _vibeTopicService = VibeTopicService();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  List<VibeTopicModel> _votingTopics = [];
  String? _userVotedTopicId;
  bool _isLoading = true;
  bool _isVoting = false;

  @override
  void initState() {
    super.initState();
    _loadVotingData();
  }

  /// 投票データを読み込み
  Future<void> _loadVotingData() async {
    setState(() => _isLoading = true);

    try {
      final userId = _auth.currentUser?.uid;

      // 投票中のお題候補を取得
      final topics = await _vibeTopicService.getVotingTopics();

      // ユーザーの投票状況を取得
      String? votedTopicId;
      if (userId != null) {
        votedTopicId = await _vibeTopicService.getUserVote(userId);
      }

      if (mounted) {
        setState(() {
          _votingTopics = topics;
          _userVotedTopicId = votedTopicId;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading voting data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// お題に投票
  Future<void> _voteForTopic(String topicId) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      _showErrorDialog('ログインが必要です');
      return;
    }

    setState(() => _isVoting = true);

    try {
      // 楽観的UI更新
      final previousVote = _userVotedTopicId;
      setState(() {
        _userVotedTopicId = topicId;
        // voteCountを更新
        _votingTopics = _votingTopics.map((topic) {
          if (topic.topicId == topicId) {
            return topic.copyWith(voteCount: topic.voteCount + 1);
          } else if (topic.topicId == previousVote) {
            return topic.copyWith(voteCount: topic.voteCount - 1);
          }
          return topic;
        }).toList();
      });

      // Firestoreに保存
      await _vibeTopicService.voteForTopic(userId, topicId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('投票しました'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('Error voting: $e');
      // エラー時は元に戻す
      await _loadVotingData();
      if (mounted) {
        _showErrorDialog('投票に失敗しました');
      }
    } finally {
      if (mounted) {
        setState(() => _isVoting = false);
      }
    }
  }

  void _showErrorDialog(String message) {
    showCupertinoDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('エラー'),
        content: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(message),
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          '明日のVibeを投票',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _votingTopics.isEmpty
              ? _buildEmptyState()
              : _buildVotingList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 80,
            color: Colors.white.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            '投票中のお題がありません',
            style: TextStyle(
              fontSize: 16,
              color: Colors.white.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '事前定義されたお題から選択できます',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withOpacity(0.5),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _showPredefinedTopics,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5D8FFF),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('お題を選ぶ'),
          ),
        ],
      ),
    );
  }

  /// 事前定義されたお題リストを表示
  void _showPredefinedTopics() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '明日のお題を選択',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: PredefinedVibeTopics.topics.length,
                itemBuilder: (context, index) {
                  final topic = PredefinedVibeTopics.topics[index];
                  return ListTile(
                    title: Text(
                      topic,
                      style: const TextStyle(color: Colors.white),
                    ),
                    trailing: const Icon(
                      Icons.arrow_forward_ios,
                      color: Colors.white54,
                      size: 16,
                    ),
                    onTap: () async {
                      Navigator.pop(context);
                      await _createAndVoteForTopic(topic);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// お題を作成して投票
  Future<void> _createAndVoteForTopic(String title) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      _showErrorDialog('ログインが必要です');
      return;
    }

    setState(() => _isVoting = true);

    try {
      // 明日の日付でお題を作成
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final topicId = await _vibeTopicService.createTopic(title, tomorrow);

      // 作成したお題に投票
      await _vibeTopicService.voteForTopic(userId, topicId);

      // データを再読み込み
      await _loadVotingData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('「$title」に投票しました'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('Error creating and voting for topic: $e');
      if (mounted) {
        _showErrorDialog('投票に失敗しました');
      }
    } finally {
      if (mounted) {
        setState(() => _isVoting = false);
      }
    }
  }

  Widget _buildVotingList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _votingTopics.length,
      itemBuilder: (context, index) {
        final topic = _votingTopics[index];
        final isVoted = _userVotedTopicId == topic.topicId;

        return _buildTopicCard(topic, isVoted);
      },
    );
  }

  Widget _buildTopicCard(VibeTopicModel topic, bool isVoted) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF202020),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isVoted ? const Color(0xFF5D8FFF) : const Color(0xFF4C4C4C),
          width: isVoted ? 2 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isVoting ? null : () => _voteForTopic(topic.topicId),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // 選択アイコン
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isVoted ? const Color(0xFF5D8FFF) : Colors.white.withOpacity(0.3),
                      width: 2,
                    ),
                    color: isVoted ? const Color(0xFF5D8FFF) : Colors.transparent,
                  ),
                  child: isVoted
                      ? const Icon(
                          Icons.check,
                          size: 16,
                          color: Colors.white,
                        )
                      : null,
                ),
                const SizedBox(width: 16),

                // お題タイトルと得票数
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        topic.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${topic.voteCount}票',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ),

                // 投票ボタン
                if (isVoted)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF5D8FFF).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      '投票済み',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF5D8FFF),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
