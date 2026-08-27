import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../constants/app_colors.dart';
import '../constants/milfolha_teams.dart';
import '../models/milfolha_team_model.dart';
import '../models/post_model.dart';
import '../services/milfolha_service.dart';
import 'milfolha_team_members_screen.dart';
import 'post_detail_screen.dart';

/// Milfolha 班アカウントのプロフィール画面（班員投稿のグリッド表示）。
///
/// 班アカウント（users/{teamId}）のプロフィール代替。ADL の AdlTeamPlaylistScreen に準拠。
/// 投稿は「班メンバー（milfolha_memberships）の uid」で posts を集約して表示する。
class MilfolhaTeamProfileScreen extends StatefulWidget {
  final String teamId;

  const MilfolhaTeamProfileScreen({super.key, required this.teamId});

  @override
  State<MilfolhaTeamProfileScreen> createState() =>
      _MilfolhaTeamProfileScreenState();
}

class _MilfolhaTeamProfileScreenState extends State<MilfolhaTeamProfileScreen> {
  final _db = FirebaseFirestore.instance;
  final _service = MilfolhaService();
  MilfolhaTeamModel? _team;
  List<PostModel>? _posts;
  int _memberCount = 0;
  bool _isLoadingTeam = true;
  bool _isLoadingPosts = true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadTeam(), _loadPosts()]);
  }

  Future<void> _loadTeam() async {
    try {
      final team = await _service.getTeam(widget.teamId);
      if (!mounted) return;
      setState(() {
        _team = team;
        _isLoadingTeam = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingTeam = false);
    }
  }

  Future<void> _loadPosts() async {
    try {
      // メンバー uid を集め、その投稿を集約（班アカウント自身は除外）。
      final memberUids = (await _service.getTeamMemberUids(widget.teamId))
          .where((uid) => uid != widget.teamId)
          .toList();
      _memberCount = memberUids.length;
      if (memberUids.isEmpty) {
        if (mounted) {
          setState(() {
            _posts = const [];
            _isLoadingPosts = false;
          });
        }
        return;
      }
      // whereIn は最大30件。メンバーを30件ずつに分割してクエリ。
      final all = <PostModel>[];
      for (var i = 0; i < memberUids.length; i += 30) {
        final chunk = memberUids.sublist(
            i, (i + 30 > memberUids.length) ? memberUids.length : i + 30);
        final snap = await _db
            .collection('posts')
            .where('userId', whereIn: chunk)
            .get();
        all.addAll(snap.docs.map(PostModel.fromFirestore));
      }
      all.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (!mounted) return;
      setState(() {
        _posts = all;
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

  Future<void> _refresh() => _loadAll();

  @override
  Widget build(BuildContext context) {
    final displayName =
        _team?.name ?? MilfolhaTeamDefinitions.displayNameOf(widget.teamId);

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
              memberCount: _memberCount,
              postCount: _posts?.length ?? 0,
              isLoading: _isLoadingTeam,
              profileImageUrl: _team?.profileImageUrl,
              description: _team?.description,
              onTapMembers: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MilfolhaTeamMembersScreen(
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
        child: Center(child: CupertinoActivityIndicator(color: Colors.white)),
      );
    }
    final posts = _posts ?? const [];
    if (posts.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Text('まだ投稿がありません',
              style: TextStyle(color: Colors.grey, fontSize: 13)),
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
                    builder: (_) =>
                        PostDetailScreen(post: post, currentUserId: uid),
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
  final int postCount;
  final bool isLoading;
  final VoidCallback onTapMembers;
  final String? profileImageUrl;
  final String? description;

  const _Header({
    required this.displayName,
    required this.memberCount,
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
                        onTap: onTapMembers),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '$displayName チーム',
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
                : 'Milfolha イベント公式アカウント',
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
          colors: [Color(0xFF7B6FE6), Color(0xFF4B3FB0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        displayName.isNotEmpty ? displayName.substring(0, 1).toUpperCase() : '?',
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
        Text('$value',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
      ],
    );
    if (onTap == null) return column;
    return GestureDetector(
        behavior: HitTestBehavior.opaque, onTap: onTap, child: column);
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
                    style: const TextStyle(color: Colors.white, fontSize: 10),
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
