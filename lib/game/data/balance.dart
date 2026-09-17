import 'dart:math' as math;

/// 게임 밸런스 상수 모음. 수치 조정은 전부 이 파일에서 한다.
class Balance {
  Balance._();

  // ───────────────────────── 등급별 기본 스탯 ─────────────────────────
  /// 등급별 1회 공격 기본 데미지.
  static const List<double> damage = [10, 34, 116, 400, 1400, 5200, 21000];

  /// 등급별 초당 공격 횟수.
  static const List<double> attackSpeed = [
    0.90,
    0.98,
    1.06,
    1.14,
    1.24,
    1.38,
    1.55,
  ];

  /// 사거리는 화면 해상도에 비례해야 하므로 필드 밴드 높이의 배수로 정의한다.
  /// 1.0 = 바로 옆 레인, 3.0 = 두 칸 건너 레인.
  static const List<double> rangeFactor = [
    1.80,
    1.92,
    2.08,
    2.30,
    2.65,
    3.25,
    3.95,
  ];

  /// 등급별 판매 금액.
  static const List<int> sellPrice = [12, 38, 120, 380, 1200, 4000, 14000];

  // ───────────────────────── 시작 자원 ─────────────────────────
  static const int startGold = 160;
  static const int startGems = 0;
  static const int startLives = 20;

  /// 합성에 필요한 동일 유닛 개수.
  static const int mergeCount = 3;

  /// 보유 유닛이 많을수록 소환 비용이 오른다. 합성이 이득인 이유.
  static int summonCost(int unitCount) => 20 + 6 * unitCount;

  // ───────────────────────── 웨이브 ─────────────────────────
  static const double firstWaveDelay = 10;
  static const double waveInterval = 22;
  static const int bossEvery = 10;
  static const int rushEvery = 5;

  /// 클리어 모드가 끝나는 웨이브.
  static const int clearWave = 100;

  /// 몬스터 체력.
  ///
  /// 증가율이 플레이어 전투력 증가율(실측 웨이브당 약 +13.5%)보다 훨씬 가파르면
  /// 중반부터 격차가 복리로 벌어져 아무것도 손쓸 수 없게 된다. 대신 첫 웨이브
  /// 체력을 올려, 초반이 손 놓고 있어도 되는 구간이 되지 않도록 한다.
  ///
  /// 모드마다 곡선이 다르다. 클리어 모드는 [clearWave] 에서 끝을 보라고 만든
  /// 모드이므로 거기까지 갈 수 있게 완만하고, 무한 모드는 «얼마나 멀리 가나» 가
  /// 전부라 더 가파르다. 같은 곡선을 쓰면 둘 중 하나가 망가진다 — 무한 모드에
  /// 맞추면 100웨이브를 아무도 못 깨고, 클리어 모드에 맞추면 무한 모드가
  /// 100웨이브까지 밋밋해진다.
  static double enemyHp(int wave, {required bool endless}) =>
      90 * math.pow(endless ? 1.17 : 1.10, wave - 1).toDouble();

  static int enemyCount(int wave) => math.min(32, 8 + (wave * 0.55).floor());

  /// 한 바퀴를 도는 데 걸리는 시간(초). 해상도와 무관하게 체감이 같아진다.
  static double lapSeconds(int wave) => math.max(19.0, 33.0 - wave * 0.32);

  static int killGold(int wave) => 4 + (wave * 1.19).floor();
  static int clearGold(int wave) => 42 + 13 * wave;

  // 보스
  static const double bossHpMultiplier = 32;
  static const double bossLapMultiplier = 1.65; // 더 느리게 이동
  static int bossGold(int wave) => 280 + 56 * wave;
  static int bossGems(int wave) => 4 + wave ~/ 10;
  static const int bossLifeCost = 5;

  // 러시 웨이브(5, 15, 25...): 수가 많고 빠르지만 약하다.
  static const double rushHpMultiplier = 0.62;
  static const double rushLapMultiplier = 0.6;
  static const double rushCountMultiplier = 1.5;

  // ───────────────────────── 골드 강화 ─────────────────────────
  static int atkUpgradeCost(int lv) => (140 * math.pow(1.155, lv)).round();
  static double atkBonus(int lv) => 1 + 0.06 * lv;

  static int spdUpgradeCost(int lv) => (170 * math.pow(1.175, lv)).round();
  static double spdBonus(int lv) => 1 + 0.04 * lv;

  static int goldUpgradeCost(int lv) => (220 * math.pow(1.21, lv)).round();
  static double goldBonus(int lv) => 1 + 0.10 * lv;

  // ───────────────────────── 다이아 강화 ─────────────────────────
  static const int luckMaxLevel = 30;
  static int luckCost(int lv) => 3 + lv ~/ 3;

  /// 유니크 이상 확정 소환 비용(다이아).
  static const int highSummonGems = 12;

  /// 라이프 1 회복 비용(다이아).
  static const int reviveGems = 8;

  /// 노말~레전더리 소환 가중치. 행운 레벨이 오르면 상위 등급 비중이 커진다.
  static List<double> summonWeights(int luck) {
    final l = luck.toDouble();
    return <double>[
      math.max(1200.0, 6200 - 155 * l),
      2500 + 30 * l,
      950 + 62 * l,
      300 + 38 * l,
      50 + 15 * l,
    ];
  }

  /// 표시용 확률(%) 리스트.
  static List<double> summonRates(int luck) {
    final w = summonWeights(luck);
    final total = w.fold<double>(0, (a, b) => a + b);
    return w.map((e) => e / total * 100).toList();
  }
}
