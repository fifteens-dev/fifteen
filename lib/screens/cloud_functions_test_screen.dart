import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Cloud Functions テスト画面
///
/// プッシュ通知と公式通知のテストができます
class CloudFunctionsTestScreen extends StatefulWidget {
  const CloudFunctionsTestScreen({super.key});

  @override
  State<CloudFunctionsTestScreen> createState() => _CloudFunctionsTestScreenState();
}

class _CloudFunctionsTestScreenState extends State<CloudFunctionsTestScreen> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  bool _isLoading = false;
  String? _resultMessage;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  /// プッシュ通知のテスト
  /// push_notification_requests にドキュメントを追加して、Cloud Functionをトリガー
  Future<void> _testPushNotification() async {
    setState(() {
      _isLoading = true;
      _resultMessage = null;
    });

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('ログインが必要です');
      }

      // プッシュ通知リクエストを作成
      await FirebaseFirestore.instance
          .collection('push_notification_requests')
          .add({
        'recipientId': currentUser.uid,
        'notificationType': 'test',
        'senderUsername': 'テストシステム',
        'message': 'これはプッシュ通知のテストです',
        'postId': 'test-post-${DateTime.now().millisecondsSinceEpoch}',
        'createdAt': FieldValue.serverTimestamp(),
      });

      setState(() {
        _resultMessage = '✅ プッシュ通知リクエストを作成しました。\n'
            'Cloud Functionが処理を開始します。\n'
            'デバイスに通知が届くか確認してください。';
      });
    } catch (e) {
      setState(() {
        _resultMessage = '❌ エラー: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 公式通知のテスト（管理者のみ）
  /// HTTPSコール関数を呼び出し
  Future<void> _testOfficialNotification() async {
    if (_titleController.text.isEmpty || _bodyController.text.isEmpty) {
      setState(() {
        _resultMessage = '⚠️ タイトルと本文を入力してください';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _resultMessage = null;
    });

    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'sendOfficialNotification',
      );

      final result = await callable.call({
        'title': _titleController.text,
        'body': _bodyController.text,
      });

      setState(() {
        _resultMessage = '✅ 公式通知を送信しました\n'
            '${result.data['message']}';
      });
    } catch (e) {
      setState(() {
        if (e.toString().contains('permission-denied') ||
            e.toString().contains('管理者権限')) {
          _resultMessage = '❌ エラー: 管理者権限がありません\n'
              'この機能は管理者のみ使用できます。';
        } else {
          _resultMessage = '❌ エラー: $e';
        }
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cloud Functions テスト'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 説明
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cloud Functions テスト',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'このページでは、デプロイされたCloud Functionsの動作をテストできます。',
                      style: TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // プッシュ通知テスト
            Text(
              '1. プッシュ通知テスト',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Firestoreにリクエストを作成し、Cloud Functionがプッシュ通知を送信します。',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _testPushNotification,
              icon: const Icon(Icons.notifications_active),
              label: const Text('プッシュ通知をテスト'),
            ),
            const SizedBox(height: 32),

            // 公式通知テスト
            Text(
              '2. 公式通知テスト（管理者のみ）',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              '全ユーザーに公式通知を送信します。管理者権限が必要です。',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: '通知タイトル',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bodyController,
              decoration: const InputDecoration(
                labelText: '通知本文',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _testOfficialNotification,
              icon: const Icon(Icons.campaign),
              label: const Text('公式通知を送信'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
              ),
            ),
            const SizedBox(height: 24),

            // 結果表示
            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24.0),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_resultMessage != null)
              Card(
                color: _resultMessage!.startsWith('✅')
                    ? Colors.green.shade50
                    : _resultMessage!.startsWith('⚠️')
                        ? Colors.orange.shade50
                        : Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    _resultMessage!,
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ),

            const SizedBox(height: 24),

            // デバッグ情報
            Card(
              color: Colors.grey.shade100,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'デバッグ情報',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'ユーザーID: ${FirebaseAuth.instance.currentUser?.uid ?? "未ログイン"}',
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Functions URL: ${FirebaseFunctions.instance.app.options.projectId}',
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
