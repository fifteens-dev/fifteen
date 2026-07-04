import 'package:cloud_firestore/cloud_firestore.dart';

class ArtistModel {
  final String artistId;
  final String artistName;
  final String? imageUrl;
  final List<String> followerIds;

  const ArtistModel({
    required this.artistId,
    required this.artistName,
    this.imageUrl,
    this.followerIds = const [],
  });

  int get followerCount => followerIds.length;
  bool isFollowedBy(String userId) => followerIds.contains(userId);

  factory ArtistModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return ArtistModel(
      artistId: doc.id,
      artistName: data['artistName'] as String? ?? '',
      imageUrl: data['imageUrl'] as String?,
      followerIds: List<String>.from(data['followerIds'] as List? ?? []),
    );
  }

  Map<String, dynamic> toMap() => {
        'artistId': artistId,
        'artistName': artistName,
        if (imageUrl != null) 'imageUrl': imageUrl,
        'followerIds': followerIds,
      };
}
