import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../constants/adl_teams.dart';
import '../constants/app_colors.dart';
import '../models/adl_team_model.dart';
import '../models/post_model.dart';
import 'adl_team_members_screen.dart';
import 'adl_team_settings_screen.dart';
import 'post_detail_screen.dart';

/// ADL班アカウントのプロフィール画面（班員投稿のグリッド表示）。
///
/// 班アカウント（users/{teamId}）のプロフィール代替として機能する。
/// 班員（followers）が投稿した posts（adlTeamId == teamId）を一覧表示する。
class AdlTeamPlaylistScreen extends StatefulWidget {
  final String teamId;

  const AdlTeamPlaylistScreen({
    super.key,
    required this.teamId,
  });

  /// 旧 API: AdlTeamModel を直接渡す呼び出しもサポートする。
  factory AdlTeamPlaylistScreen.fromTeam({
    Key? key,
    required AdlTeamModel team,
  }) =>
      AdlTeamPlaylistScreen(key: key, teamId: team.teamId);

  @override
  State<AdlTeamPlaylistScreen> createState() => _AdlTeamPlaylistScreenState();
}

class _AdlTeamPlaylistScreenState extends State<AdlTeamPlaylistScreen> {
  final _db = FirebaseFirestore.instance;
  AdlTeamModel? _team;
  List<PostModel>? _posts;
  bool _isLoadingTeam = true;
  bool _isLoadingPosts = true;
  bool _isTeamMember = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
    _loadMembership();
  }

  /// 現在のユーザーがこの班に所属しているか判定。
  /// 所属している場合のみ歯車（設定）アイコンを表示する。
  Future<void> _loadMembership() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final snap = await _db.collection('users').doc(uid).get();
      final myTeamId = snap.data()?['adlTeamId'] as String?;
      if (mounted) {
        setState(() => _isTeamMember = myTeamId == widget.teamId);
      }
    } catch (_) {}
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadTeam(), _loadPosts()]);
  }

  Future<void> _loadTeam() async {
    try {
      final snap = await _db.collection('adl_teams').doc(widget.teamId).get();
      if (!mounted) return;
      setState(() {
        _team = snap.exists ? AdlTeamModel.fromFirestore(snap) : null;
        _isLoadingTeam = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingTeam = false);
    }
  }

  Future<void> _loadPosts() async {
    try {
      final snap = await _db
          .collection('posts')
          .where('adlTeamId', isEqualTo: widget.teamId)
          .orderBy('createdAt', descending: true)
          .get();
      if (!mounted) return;
      setState(() {
        _posts = snap.docs.map(PostModel.fromFirestore).toList();
        _isLoadingPosts = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _posts = const [];
          _isLoadingPosts = false;
        });
      }
    }
  }

  Future<void> _refresh() async {
    // 既存コンテンツを保持したまま再取得する（リフレッシュ中の暗転を防ぐ）
    await _loadAll();
  }

  @override
  Widget build(BuildContext context) {
    final displayName = _team?.name ?? AdlTeamDefinitions.displayNameOf(widget.teamId);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          '@${widget.teamId}',
          style: const TextStyle(
            fontSize: 14,
            color: Colors.grey,
            fontWeight: FontWeight.w500,
          ),
        ),
        actions: [
          if (_isTeamMember && _team != null)
            IconButton(
              icon: const Icon(Icons.settings_outlined, color: Colors.white),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AdlTeamSettingsScreen(
                      team: _team!,
                      displayName: displayName,
                      onChanged: _loadTeam,
                    ),
                  ),
                );
                // 設定画面から戻ったら最新化
                _loadTeam();
              },
            ),
        ],
      ),
      body: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          CupertinoSliverRefreshControl(onRefresh: _refresh),
          SliverToBoxAdapter(
            child: _Header(
              displayName: displayName,
              memberCount: _team?.memberCount ?? 0,
              likeCount: _team?.likeCount ?? 0,
              postCount: _posts?.length ?? 0,
              isLoading: _isLoadingTeam,
              profileImageUrl: _team?.profileImageUrl,
              description: _team?.description,
              onTapMembers: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AdlTeamMembersScreen(
                      teamId: widget.teamId,
                      teamDisplayName: displayName,
                    ),
                  ),
                );
              },
            ),
          ),
          _buildGrid(),
        ],
      ),
    );
  }

  Widget _buildGrid() {
    if (_isLoadingPosts) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: CupertinoActivityIndicator(color: Colors.white),
        ),
      );
    }
    final posts = _posts ?? const [];
    if (posts.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Text(
            'まだ投稿がありません',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.all(1),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 1,
          crossAxisSpacing: 1,
          childAspectRatio: 9 / 16,
        ),
        delegate: SliverChildBuilderDelegate(
          (_, i) {
            final post = posts[i];
            return _PostThumb(
              post: post,
              onTap: () {
                final uid = FirebaseAuth.instance.currentUser?.uid;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PostDetailScreen(
                      post: post,
                      currentUserId: uid,
                    ),
                  ),
                );
              },
            );
          },
          childCount: posts.length,
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String displayName;
  final int memberCount;
  final int likeCount;
  final int postCount;
  final bool isLoading;
  final VoidCallback onTapMembers;
  final String? profileImageUrl;
  final String? description;

  const _Header({
    required this.displayName,
    required this.memberCount,
    required this.likeCount,
    required this.postCount,
    required this.isLoading,
    required this.onTapMembers,
    this.profileImageUrl,
    this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // 班アイコン（画像 or イニシャル）
              ClipRRect(
                borderRadius: BorderRadius.circular(36),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: (profileImageUrl != null && profileImageUrl!.isNotEmpty)
                      ? CachedNetworkImage(
                          imageUrl: profileImageUrl!,
                          width: 72,
                          height: 72,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => _initialAvatar(),
                        )
                      : _initialAvatar(),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _Stat(label: '投稿', value: postCount),
                    _Stat(
                      label: 'メンバー',
                      value: memberCount,
                      onTap: onTapMembers,
                    ),
                    _Stat(label: 'いいね', value: likeCount),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '$displayName 班',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            (description != null && description!.isNotEmpty)
                ? description!
                : 'ADL イベント公式アカウント',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _initialAvatar() {
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
        displayName.isNotEmpty
            ? displayName.substring(0, 1).toUpperCase()
            : '?',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 30,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final int value;
  final VoidCallback? onTap;

  const _Stat({required this.label, required this.value, this.onTap});

  @override
  Widget build(BuildContext context) {
    final column = Column(
      children: [
        Text(
          '$value',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(color: Colors.grey, fontSize: 11),
        ),
      ],
    );
    if (onTap == null) return column;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: column,
    );
  }
}

class _PostThumb extends StatelessWidget {
  final PostModel post;
  final VoidCallback onTap;

  const _PostThumb({required this.post, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        color: AppColors.surfaceLight,
        child: post.photoUrl != null
            ? Image.network(post.photoUrl!, fit: BoxFit.cover)
            : Center(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    post.track.trackName,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 10),
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
      ),
    );
  }
}
