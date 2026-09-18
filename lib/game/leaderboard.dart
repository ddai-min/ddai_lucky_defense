import 'dart:convert';

import 'package:characters/characters.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'data/game_mode.dart';

/// 랭킹 한 줄.
@immutable
class RankEntry {
  const RankEntry({required this.name, required this.wave, this.achievedAt});

  final String name;
  final int wave;
  final DateTime? achievedAt;

  @override
  String toString() => 'RankEntry($name, $wave)';
}

/// 이름에 허용하는 최대 글자 수. 규칙(firestore.rules)도 같은 값을 본다.
const int kMaxRankNameLength = 12;

/// 입력한 이름을 저장 가능한 모양으로 다듬는다. 빈 문자열이면 null.
///
/// 앞뒤 공백을 떼고, 줄바꿈·연속 공백을 한 칸으로 줄이고, 길이를 자른다.
/// 서버 규칙도 같은 조건을 검사하므로 여기를 통과 못 하면 올릴 수 없다.
String? normalizeRankName(String raw) {
  final cleaned = raw
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (cleaned.isEmpty) {
    return null;
  }
  return cleaned.characters.length > kMaxRankNameLength
      ? cleaned.characters.take(kMaxRankNameLength).toString()
      : cleaned;
}

/// 마지막으로 쓴 이름. 판마다 다시 치지 않게 기기에 남긴다.
///
/// 저장소를 못 쓰는 환경에서도 게임이 멈추지 않도록 실패는 삼킨다
/// (`PrefsRecordStore` 와 같은 방침).
Future<String?> loadRankName() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_rankNameKey);
  } catch (error) {
    debugPrint('이름을 불러오지 못했습니다: $error');
    return null;
  }
}

Future<void> saveRankName(String name) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_rankNameKey, name);
  } catch (error) {
    debugPrint('이름을 저장하지 못했습니다: $error');
  }
}

const String _rankNameKey = 'rank.name';

/// 모드별 랭킹 저장소.
///
/// 실제 구현은 [FirestoreLeaderboard], 테스트는 [MemoryLeaderboard] 가 맡는다.
abstract class Leaderboard {
  /// 랭킹을 쓸 수 있는 빌드인지. 거짓이면 UI 가 랭킹을 아예 감춘다.
  bool get isAvailable;

  /// [mode] 상위 기록. 실패하면 빈 목록.
  Future<List<RankEntry>> top(GameMode mode, {int limit = 20});

  /// 기록을 올린다. 성공 여부를 돌려준다.
  Future<bool> submit(GameMode mode, RankEntry entry);
}

/// Firestore REST API 를 그대로 쓰는 구현.
///
/// `cloud_firestore` 패키지를 쓰지 않는 이유는 **번들 크기** 다. 이 게임은
/// 콜드 로딩이 4.7MB 인데 Firebase 웹 SDK 를 통째로 넣으면 여기에 수백 KB 가
/// 더 붙는다. 랭킹이 하는 일은 «상위 20개 읽기» 와 «한 줄 쓰기» 뿐이라
/// REST 두 번이면 끝난다.
///
/// 프로젝트 ID 와 웹 API 키는 비밀이 아니다(모든 Firebase 웹 앱이 브라우저에
/// 그대로 내려보낸다). 그래도 저장소에 박아 두지 않고 `--dart-define` 으로
/// 받는다 — 값이 없으면 [isAvailable] 이 거짓이 되어 기능이 조용히 빠진다.
///
/// ```sh
/// flutter build web --release \
///   --dart-define=FIREBASE_PROJECT_ID=your-project \
///   --dart-define=FIREBASE_API_KEY=AIza...
/// ```
///
/// **막는 건 서버 규칙이 한다.** 정적 웹 클라이언트가 직접 쓰는 구조라
/// 브라우저에서 아무 값이나 POST 할 수 있다. 값의 범위·이름 길이·필드 구성은
/// `firebase/firestore.rules` 가 검사한다([docs/leaderboard.md] 참고).
class FirestoreLeaderboard implements Leaderboard {
  FirestoreLeaderboard({http.Client? client, String? projectId, String? apiKey})
    : _client = client ?? http.Client(),
      _projectId = projectId ?? _envProjectId,
      _apiKey = apiKey ?? _envApiKey;

  static const String _envProjectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
  );
  static const String _envApiKey = String.fromEnvironment('FIREBASE_API_KEY');

  final http.Client _client;
  final String _projectId;
  final String _apiKey;

  @override
  bool get isAvailable => _projectId.isNotEmpty && _apiKey.isNotEmpty;

  String get _base =>
      'https://firestore.googleapis.com/v1/projects/$_projectId'
      '/databases/(default)/documents';

  /// 모드마다 컬렉션을 따로 쓴다. 한 컬렉션에 모드를 필드로 섞으면
  /// «모드로 거르고 웨이브로 정렬» 에 복합 색인을 따로 만들어야 한다.
  static String collectionOf(GameMode mode) => 'ranking_${mode.name}';

  @override
  Future<List<RankEntry>> top(GameMode mode, {int limit = 20}) async {
    if (!isAvailable) {
      return const [];
    }
    try {
      final response = await _client.post(
        Uri.parse('$_base:runQuery?key=$_apiKey'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'structuredQuery': {
            'from': [
              {'collectionId': collectionOf(mode)},
            ],
            'orderBy': [
              {
                'field': {'fieldPath': 'wave'},
                'direction': 'DESCENDING',
              },
            ],
            'limit': limit,
          },
        }),
      );
      if (response.statusCode != 200) {
        debugPrint('랭킹을 불러오지 못했습니다: ${response.statusCode}');
        return const [];
      }
      final rows = jsonDecode(response.body);
      if (rows is! List) {
        return const [];
      }
      final entries = <RankEntry>[];
      for (final row in rows) {
        final document = row is Map ? row['document'] : null;
        final fields = document is Map ? document['fields'] : null;
        if (fields is! Map) {
          continue;
        }
        final name = fields['name']?['stringValue'];
        final wave = int.tryParse('${fields['wave']?['integerValue']}');
        if (name is! String || wave == null) {
          continue;
        }
        entries.add(
          RankEntry(
            name: name,
            wave: wave,
            achievedAt: DateTime.tryParse(
              '${fields['createdAt']?['timestampValue']}',
            ),
          ),
        );
      }
      return entries;
    } catch (error) {
      debugPrint('랭킹을 불러오지 못했습니다: $error');
      return const [];
    }
  }

  @override
  Future<bool> submit(GameMode mode, RankEntry entry) async {
    if (!isAvailable) {
      return false;
    }
    try {
      final response = await _client.post(
        Uri.parse('$_base/${collectionOf(mode)}?key=$_apiKey'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'fields': {
            'name': {'stringValue': entry.name},
            'wave': {'integerValue': '${entry.wave}'},
            'createdAt': {
              'timestampValue': (entry.achievedAt ?? DateTime.now())
                  .toUtc()
                  .toIso8601String(),
            },
          },
        }),
      );
      if (response.statusCode == 200) {
        return true;
      }
      debugPrint('랭킹 등록에 실패했습니다: ${response.statusCode} ${response.body}');
      return false;
    } catch (error) {
      debugPrint('랭킹 등록에 실패했습니다: $error');
      return false;
    }
  }
}

/// 테스트용 인메모리 랭킹.
class MemoryLeaderboard implements Leaderboard {
  MemoryLeaderboard({this.isAvailable = true});

  @override
  final bool isAvailable;

  final Map<GameMode, List<RankEntry>> entries = {};
  int submitCount = 0;

  /// 참이면 [submit] 이 실패한다. 실패 경로를 검증할 때 쓴다.
  bool failSubmit = false;

  @override
  Future<List<RankEntry>> top(GameMode mode, {int limit = 20}) async {
    final list = [...?entries[mode]]
      ..sort((a, b) => b.wave.compareTo(a.wave));
    return list.take(limit).toList();
  }

  @override
  Future<bool> submit(GameMode mode, RankEntry entry) async {
    submitCount++;
    if (failSubmit) {
      return false;
    }
    entries.putIfAbsent(mode, () => []).add(entry);
    return true;
  }
}
