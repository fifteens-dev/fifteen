import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String phoneNumber;
  final String? name;
  final String? username;
  final String? profileImageUrl;
  final String? bio;
  final String? university;
  final List<String> followers; // フォロワーのuidリスト
  final List<String> following; // フォロー中のuidリスト
  final List<String> savedPosts; // 保存した投稿のIDリスト
  final Map<String, dynamic> savedPostsAt; // 投稿保存時刻 {postId: Timestamp}
  final Map<String, dynamic> savedTracksData; // 保存した楽曲 {trackId: {trackName, artistName, albumImageUrl, previewUrl}}
  final int postsCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool isAdmin; // 管理者フラグ
  final String? inviteCode; // 招待コード（7文字英数字）
  final String? adlTeamId; // ADL班ID
  final String? adlTeamName; // ADL班名
  final String? adlEventId; // ADLイベントID

  UserModel({
    required this.uid,
    required this.phoneNumber,
    this.name,
    this.username,
    this.profileImageUrl,
    this.bio,
    this.university,
    this.followers = const [],
    this.following = const [],
    this.savedPosts = const [],
    this.savedPostsAt = const {},
    this.savedTracksData = const {},
    this.postsCount = 0,
    this.createdAt,
    this.updatedAt,
    this.isAdmin = false,
    this.inviteCode,
    this.adlTeamId,
    this.adlTeamName,
    this.adlEventId,
  });

  // Firestoreドキュメントから作成
  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    // doc.data() が null の場合（極めてまれ）も空Mapとして安全に扱う
    final data = (doc.data() as Map<String, dynamic>?) ?? {};

    // 非String要素が混入していても TypeError を出さずにスキップする
    List<String> safeStringList(String key) =>
        (data[key] as List<dynamic>? ?? []).whereType<String>().toList();

    // Timestamp 以外の型で保存されていた場合も null を返し CastError を防ぐ
    DateTime? safeTimestamp(String key) {
      final val = data[key];
      return val is Timestamp ? val.toDate() : null;
    }

    // uid はドキュメントID が正（users/{uid} で作られる）。
    // 旧データで uid フィールドが欠けていても doc.id で必ず埋める。
    final rawUid = data['uid']?.toString();

    return UserModel(
      uid: (rawUid == null || rawUid.isEmpty) ? doc.id : rawUid,
      phoneNumber: data['phoneNumber']?.toString() ?? '',
      name: data['name']?.toString(),
      username: data['username']?.toString(),
      profileImageUrl: data['profileImageUrl']?.toString(),
      bio: data['bio']?.toString(),
      university: data['university']?.toString(),
      followers: safeStringList('followers'),
      following: safeStringList('following'),
      savedPosts: safeStringList('savedPosts'),
      savedPostsAt: (data['savedPostsAt'] as Map<String, dynamic>?) ?? {},
      savedTracksData: (data['savedTracksData'] as Map<String, dynamic>?) ?? {},
      // Firestore が int/double どちらで返しても int に統一
      postsCount: (data['postsCount'] as num?)?.toInt() ?? 0,
      createdAt: safeTimestamp('createdAt'),
      updatedAt: safeTimestamp('updatedAt'),
      // 非bool型が保存されていた場合 == true で安全にfalseとして扱う
      isAdmin: data['isAdmin'] == true,
      inviteCode: data['inviteCode']?.toString(),
      adlTeamId: data['adlTeamId']?.toString(),
      adlTeamName: data['adlTeamName']?.toString(),
      adlEventId: data['adlEventId']?.toString(),
    );
  }

  // Firestoreに保存する形式に変換
  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'phoneNumber': phoneNumber,
      'name': name,
      'username': username,
      'profileImageUrl': profileImageUrl,
      'bio': bio,
      'university': university,
      'followers': followers,
      'following': following,
      'savedPosts': savedPosts,
      'savedPostsAt': savedPostsAt,
      'savedTracksData': savedTracksData,
      'postsCount': postsCount,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : null,
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
      'isAdmin': isAdmin,
      'inviteCode': inviteCode,
      'adlTeamId': adlTeamId,
      'adlTeamName': adlTeamName,
      'adlEventId': adlEventId,
    };
  }

  // コピーを作成（一部のフィールドを更新）
  UserModel copyWith({
    String? name,
    String? username,
    String? profileImageUrl,
    String? bio,
    String? university,
    List<String>? followers,
    List<String>? following,
    List<String>? savedPosts,
    Map<String, dynamic>? savedTracksData,
    int? postsCount,
    bool? isAdmin,
  }) {
    return UserModel(
      uid: uid,
      phoneNumber: phoneNumber,
      name: name ?? this.name,
      username: username ?? this.username,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      bio: bio ?? this.bio,
      university: university ?? this.university,
      followers: followers ?? this.followers,
      following: following ?? this.following,
      savedPosts: savedPosts ?? this.savedPosts,
      savedTracksData: savedTracksData ?? this.savedTracksData,
      postsCount: postsCount ?? this.postsCount,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      isAdmin: isAdmin ?? this.isAdmin,
    );
  }

  // フォロワー数を取得
  int get followersCount => followers.length;

  // フォロー中の数を取得
  int get followingCount => following.length;

  // 保存した投稿の数を取得
  int get savedPostsCount => savedPosts.length;

  // 指定されたユーザーをフォローしているかチェック
  bool isFollowing(String userId) {
    return following.contains(userId);
  }

  // 指定された投稿を保存しているかチェック
  bool hasSavedPost(String postId) {
    return savedPosts.contains(postId);
  }

  // 指定された楽曲を保存しているかチェック
  bool hasSavedTrack(String trackId) {
    return savedTracksData.containsKey(trackId);
  }

  // 保存済みトラックIDセット
  Set<String> get savedTrackIds => savedTracksData.keys.toSet();


}
