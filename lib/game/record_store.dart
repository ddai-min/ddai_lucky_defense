import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 기기에 남는 최고 기록 한 건.
@immutable
class BestRecord {
  const BestRecord({
    this.wave = 0,
    this.kills = 0,
    this.rarityTier = 0,
    this.summons = 0,
    this.merges = 0,
    this.achievedAt,
  });

  final int wave;
  final int kills;
  final int rarityTier;
  final int summons;
  final int merges;
  final DateTime? achievedAt;

  bool get isEmpty => wave <= 0;

  /// 도달 웨이브가 우선, 같은 웨이브면 처치 수로 가린다.
  bool isBetterThan(BestRecord other) =>
      wave != other.wave ? wave > other.wave : kills > other.kills;

  @override
  String toString() => 'BestRecord(wave: $wave, kills: $kills)';
}

/// 최고 기록 저장소. 테스트에서는 [MemoryRecordStore]를 주입한다.
abstract class RecordStore {
  Future<BestRecord> load();
  Future<void> save(BestRecord record);
}

/// SharedPreferences 기반 기본 구현.
///
/// 저장소를 쓸 수 없는 환경(플러그인 미등록 등)에서도 게임이 멈추지 않도록
/// 모든 입출력 실패를 삼키고 기본값으로 동작한다.
class PrefsRecordStore implements RecordStore {
  static const String _wave = 'record.wave';
  static const String _kills = 'record.kills';
  static const String _rarity = 'record.rarity';
  static const String _summons = 'record.summons';
  static const String _merges = 'record.merges';
  static const String _achievedAt = 'record.achievedAt';

  @override
  Future<BestRecord> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final wave = prefs.getInt(_wave) ?? 0;
      if (wave <= 0) {
        return const BestRecord();
      }
      final millis = prefs.getInt(_achievedAt);
      return BestRecord(
        wave: wave,
        kills: prefs.getInt(_kills) ?? 0,
        rarityTier: prefs.getInt(_rarity) ?? 0,
        summons: prefs.getInt(_summons) ?? 0,
        merges: prefs.getInt(_merges) ?? 0,
        achievedAt: millis == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(millis),
      );
    } catch (error) {
      debugPrint('최고 기록을 불러오지 못했습니다: $error');
      return const BestRecord();
    }
  }

  @override
  Future<void> save(BestRecord record) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_wave, record.wave);
      await prefs.setInt(_kills, record.kills);
      await prefs.setInt(_rarity, record.rarityTier);
      await prefs.setInt(_summons, record.summons);
      await prefs.setInt(_merges, record.merges);
      await prefs.setInt(
        _achievedAt,
        (record.achievedAt ?? DateTime.now()).millisecondsSinceEpoch,
      );
    } catch (error) {
      debugPrint('최고 기록을 저장하지 못했습니다: $error');
    }
  }
}

/// 테스트용 인메모리 저장소.
class MemoryRecordStore implements RecordStore {
  MemoryRecordStore([this.record = const BestRecord()]);

  BestRecord record;
  int saveCount = 0;

  @override
  Future<BestRecord> load() async => record;

  @override
  Future<void> save(BestRecord next) async {
    record = next;
    saveCount++;
  }
}
