import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String phoneNumber;
  final String? name;
  final String? username;
  final String? profileImageUrl;
  final String? bio;
  final List<String> followers; // フォロワーのuidリスト
  final List<String> following; // フォロー中のuidリスト
  final List<String> savedPosts; // 保存した投稿のIDリスト
  final int postsCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool isAdmin; // 管理者フラグ

  UserModel({
    required this.uid,
    required this.phoneNumber,
    this.name,
    this.username,
    this.profileImageUrl,
    this.bio,
    this.followers = const [],
    this.following = const [],
    this.savedPosts = const [],
    this.postsCount = 0,
    this.createdAt,
    this.updatedAt,
    this.isAdmin = false,
  });

  // Firestoreドキュメントから作成
  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return UserModel(
      uid: data['uid'] ?? '',
      phoneNumber: data['phoneNumber'] ?? '',
      name: data['name'],
      username: data['username'],
      profileImageUrl: data['profileImageUrl'],
      bio: data['bio'],
      followers: List<String>.from(data['followers'] ?? []),
      following: List<String>.from(data['following'] ?? []),
      savedPosts: List<String>.from(data['savedPosts'] ?? []),
      postsCount: data['postsCount'] ?? 0,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      isAdmin: data['isAdmin'] ?? false,
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
      'followers': followers,
      'following': following,
      'savedPosts': savedPosts,
      'postsCount': postsCount,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : null,
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
      'isAdmin': isAdmin,
    };
  }

  // コピーを作成（一部のフィールドを更新）
  UserModel copyWith({
    String? name,
    String? username,
    String? profileImageUrl,
    String? bio,
    List<String>? followers,
    List<String>? following,
    List<String>? savedPosts,
    int? postsCount,
  }) {
    return UserModel(
      uid: uid,
      phoneNumber: phoneNumber,
      name: name ?? this.name,
      username: username ?? this.username,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      bio: bio ?? this.bio,
      followers: followers ?? this.followers,
      following: following ?? this.following,
      savedPosts: savedPosts ?? this.savedPosts,
      postsCount: postsCount ?? this.postsCount,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
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
}
