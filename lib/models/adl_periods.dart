import 'package:cloud_firestore/cloud_firestore.dart';

/// ADL実証実験の期間設定
///
/// 計画書（ADL.pdf）に基づく4つのマイルストーン：
/// - チーム賞期間: 6/10〜6/20（班員投稿のいいね総数で評価）
/// - 個人賞期間: 6/10〜6/24（新規ユーザー招待人数で評価）
/// - 結果連絡日: 6/27
/// - 最終発表日: 6/28
///
/// `adl_config/current` ドキュメントに保存される。
class AdlPeriods {
  final DateTime? teamRankingStart;
  final DateTime? teamRankingEnd;
  final DateTime? inviteRankingStart;
  final DateTime? inviteRankingEnd;
  final DateTime? resultAnnouncementDate;
  final DateTime? finalAnnouncementDate;

  const AdlPeriods({
    this.teamRankingStart,
    this.teamRankingEnd,
    this.inviteRankingStart,
    this.inviteRankingEnd,
    this.resultAnnouncementDate,
    this.finalAnnouncementDate,
  });

  static AdlPeriods fromMap(Map<String, dynamic>? data) {
    if (data == null) return const AdlPeriods();
    DateTime? read(String key) =>
        (data[key] as Timestamp?)?.toDate();
    return AdlPeriods(
      teamRankingStart: read('teamRankingStart'),
      teamRankingEnd: read('teamRankingEnd'),
      inviteRankingStart: read('inviteRankingStart'),
      inviteRankingEnd: read('inviteRankingEnd'),
      resultAnnouncementDate: read('resultAnnouncementDate'),
      finalAnnouncementDate: read('finalAnnouncementDate'),
    );
  }

  /// Firestore に保存するための部分マップを返す。
  /// null フィールドは含めない（部分更新時に他のフィールドを消さないため）。
  Map<String, dynamic> toPartialMap() {
    final m = <String, dynamic>{};
    void put(String key, DateTime? value) {
      if (value != null) m[key] = Timestamp.fromDate(value);
    }
    put('teamRankingStart', teamRankingStart);
    put('teamRankingEnd', teamRankingEnd);
    put('inviteRankingStart', inviteRankingStart);
    put('inviteRankingEnd', inviteRankingEnd);
    put('resultAnnouncementDate', resultAnnouncementDate);
    put('finalAnnouncementDate', finalAnnouncementDate);
    return m;
  }

  AdlPeriods copyWith({
    DateTime? teamRankingStart,
    DateTime? teamRankingEnd,
    DateTime? inviteRankingStart,
    DateTime? inviteRankingEnd,
    DateTime? resultAnnouncementDate,
    DateTime? finalAnnouncementDate,
  }) {
    return AdlPeriods(
      teamRankingStart: teamRankingStart ?? this.teamRankingStart,
      teamRankingEnd: teamRankingEnd ?? this.teamRankingEnd,
      inviteRankingStart: inviteRankingStart ?? this.inviteRankingStart,
      inviteRankingEnd: inviteRankingEnd ?? this.inviteRankingEnd,
      resultAnnouncementDate:
          resultAnnouncementDate ?? this.resultAnnouncementDate,
      finalAnnouncementDate:
          finalAnnouncementDate ?? this.finalAnnouncementDate,
    );
  }

  /// チーム賞期間が両端ともに設定されているか
  bool get hasTeamRankingPeriod =>
      teamRankingStart != null && teamRankingEnd != null;

  /// 個人賞期間が両端ともに設定されているか
  bool get hasInviteRankingPeriod =>
      inviteRankingStart != null && inviteRankingEnd != null;
}
