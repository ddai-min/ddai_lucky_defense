import 'dart:math' as math;

import 'game_mode.dart';

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
  /// 시작 골드. 첫 웨이브 전에 유닛 4~5기를 세울 수 있는 값으로 맞춘다
  /// (소환 비용이 20·59·98·137·176 이라 600이면 5기). 160 이던 시절에는
  /// 비용이 24·32·40·48 이라 같은 4기였다 — 비용을 올린 만큼 같이 올렸다.
  static const int startGold = 600;
  static const int startGems = 0;
  static const int startLives = 20;

  /// 지옥의 시작 라이프. 한 마리도 흘릴 수 없고, 다이아로 살 수도 없다
  /// ([GameMode.canBuyLife]).
  static const int hellLives = 1;

  /// 모드별 시작 라이프.
  static int startLivesOf(GameMode mode) =>
      mode == GameMode.hell ? hellLives : startLives;

  /// 합성에 필요한 동일 유닛 개수.
  static const int mergeCount = 3;

  // ───────────────────────── 어려움: 초월 도박 ─────────────────────────
  //
  // 이 게임에서 «운» 은 사실상 아무것도 결정하지 않는다. 한 판에 유닛을 수백
  // 번 뽑으므로 뽑기 운은 평균으로 수렴하고, 후반에는 누구나 21칸을 초월로
  // 채워 같은 전투력에서 멈춘다. 실력을 고정해 놓고 재면 판마다 벌어지는
  // 전투력 차이가 100웨이브에서 1.10배뿐이다. 그래서 체력만 올리면 «운 좋으면
  // 깬다» 가 아니라 «아무도 못 깬다» 가 된다.
  //
  //   dart run tool/balance_sim.dart --luck
  //
  // 어려움은 최고 등급을 도박으로 만들어 그 편차를 벌린다. 같은 실력에서도
  // 판마다 전투력이 2배 넘게 갈리므로, 당락을 가르는 게 실력이 아니라 뽑기다.

  /// 최고 등급(초월) 자리. [damage] 표의 마지막 칸이다.
  static int get topTier => damage.length - 1;

  /// 어려움에서 신화 3개를 초월로 합성했을 때의 성공 확률.
  static const double hardMergeChance = 0.15;

  /// 지옥의 같은 확률. 어려움보다 낮다.
  static const double hellMergeChance = 0.10;

  /// 합성에 실패했을 때 사라지는 재료 수. 나머지는 자리에 남는다.
  static const int mergeFailLoss = 2;

  /// 어려움에서 초월이 받는 피해 배수.
  ///
  /// 이 보정이 없으면 **도박하지 않는 쪽이 최적** 이 되어 규칙이 통째로 함정이
  /// 된다. 신화 3개는 그대로 두면 21,528 DPS 인데, 15% 에 걸어 실패하면 1개만
  /// 남으므로 기댓값이 10,982 로 반토막이기 때문이다. 초월을 4배로 키우면
  /// 기댓값이 25,630(1.19배)이 되어 거는 쪽이 이득이 된다.
  static const double hardTopTierDamage = 4;

  /// [fromRarity] 유닛 [mergeCount] 개를 합성할 때의 성공 확률. 1 이면 확정이다.
  static double mergeChance(int fromRarity, GameMode mode) {
    if (!mode.hasGamble || fromRarity != topTier - 1) {
      return 1;
    }
    return mode == GameMode.hell ? hellMergeChance : hardMergeChance;
  }

  /// 등급별 피해 보정. 강화([atkBonus])와 곱해져 최종 피해가 된다.
  static double rarityDamageBonus(int rarity, GameMode mode) =>
      mode.hasGamble && rarity == topTier ? hardTopTierDamage : 1;

  /// 보유 유닛이 많을수록 소환 비용이 오른다. 합성이 이득인 이유.
  ///
  /// **체력 곡선과 묶여 있는 값이다.** 소환 횟수가 줄면 합성 사슬이 통째로
  /// 느려져 전투력이 주저앉는다. 24+8n(최대 184G)에서 지금 값으로 올렸을 때,
  /// 체력을 그대로 두었더니 네 모드가 전부 도달률 0% 가 됐다 — 무한도 44웨에서
  /// 16웨로 떨어졌다. 그래서 올린 만큼 모든 모드의 체력 증가율을 함께 내렸다.
  ///
  /// 자리가 찬 뒤의 교체 소환이 [kSlotCount] - 1 기준 800G 다. 184G 였을 때는
  /// 후반 수입(웨이브당 1만 골드 이상)에 견줘 사실상 공짜라, 누를수록 이득인
  /// 버튼이었다.
  static int summonCost(int unitCount) => 20 + 39 * unitCount;

  static const int hellFinaleFrom = 146;
  static const int hellMeteorHeavyFrom = 148;

  static int hellMeteorKillsAt(int wave) =>
      wave >= hellMeteorHeavyFrom ? 2 : 1;
  static const double hellFinaleBossGrowth = 1.0395;

  static double bossHpAt(int wave, GameMode mode) =>
      bossHpMultiplier *
      (mode.hasFinale && wave >= hellFinaleFrom
          ? math.pow(hellFinaleBossGrowth, wave - hellFinaleFrom).toDouble()
          : 1);

  static bool isBossWave(int wave, GameMode mode) =>
      wave % bossEvery == 0 || (mode.hasFinale && wave >= hellFinaleFrom);

  static bool isSummonSealed(int wave, GameMode mode) =>
      mode.hasFinale && wave >= hellFinaleFrom;

  // ───────────────────────── 웨이브 ─────────────────────────
  static const double firstWaveDelay = 10;
  static const double waveInterval = 22;
  static const int bossEvery = 10;
  static const int rushEvery = 5;

  /// 클리어 모드가 끝나는 웨이브. 무한은 끝이 없어 null 이다.
  ///
  /// 어려움만 150 이다. 도박이 붙어 있어 판마다 결과가 크게 갈리는 모드라,
  /// 결승선을 멀리 두고 «운이 어디까지 따라오나» 를 더 오래 확인하게 한다.
  /// 늘린 만큼 체력 증가율은 내렸다 — 곡선을 그대로 두고 50웨이브를 더 붙이면
  /// 마지막 체력이 7배가 되어 아무도 못 깬다.
  static int? clearWave(GameMode mode) => switch (mode) {
    GameMode.easy || GameMode.normal => 100,
    GameMode.hard => 150,
    GameMode.hell => 150,
    GameMode.endless => null,
  };

  /// 1웨이브 몬스터 체력. 모든 모드가 여기서 출발한다.
  ///
  /// 여기를 올리면 곡선 전체가 곱으로 올라간다. 여유가 2~5배인 초·중반은
  /// 체감만 빡빡해지지만, 여유가 1.0 언저리인 후반은 **도달률과 1:1로 맞바꾼다**
  /// — 90이던 시절 104로만 올려 봤을 때(×1.15) 보통 도달률이 26%에서 2%로
  /// 떨어졌다. 그래서 이 값을 올릴 때는 모드별 증가율을 같이 내려 결승선을
  /// 제자리에 둬야 한다. 90 → 110 으로 올리면서 보통은 1.19 → 1.186,
  /// 어려움은 1.20 → 1.197 로 내렸다(100웨이브에서 복리로 1.23배를 상쇄한다).
  static const double baseHp = 110;

  /// 몬스터 체력. 쉬움·보통·무한의 난이도는 이 곡선 하나로만 갈린다
  /// (어려움만 [mergeChance] 라는 규칙이 하나 더 붙는다).
  ///
  /// 증가율이 플레이어 전투력 증가율(실측 웨이브당 약 +13.5%)보다 훨씬 가파르면
  /// 중반부터 격차가 복리로 벌어져 아무것도 손쓸 수 없게 된다. 대신 첫 웨이브
  /// 체력을 올려, 초반이 손 놓고 있어도 되는 구간이 되지 않도록 한다.
  static double enemyHp(int wave, GameMode mode) {
    switch (mode) {
      // 쉬움: 100웨이브까지 갈 수 있게 완만한 지수 곡선.
      case GameMode.easy:
        return baseHp * math.pow(1.053, wave - 1).toDouble();
      // 보통: 같은 웨이브에서 끝나되 중반이 팽팽하도록 꺾인 곡선.
      // 실력 분포 전체 기준 도달률이 13% 다 — 아주 잘 해야 깨진다(숙련자 79%).
      // 못 깨는 판도 88웨이브까지는 가므로 «중반에 무너졌다» 가 아니라
      // «결승선 앞에서 놓쳤다» 로 끝난다.
      // 여기서 증가율을 0.002 만 더 올리면 숙련자 도달률이 5분의 1 이하로
      // 주저앉는다(1.186 → 1.188 에서 85% → 18%). 후반에는 플레이어가
      // «초월» 에서 멈춰 더 셀 수 없기 때문에 이 언저리가 난이도가 급격히
      // 꺾이는 지점이다.
      case GameMode.normal:
        return _taperedHp(wave, growth: 1.154, taper: 0.9875);
      // 어려움: 곡선만 보면 보통과 별로 다르지 않다. 난이도는 여기가 아니라
      // 초월 도박([hardMergeChance])에서 나온다 — 초월을 몇 기 세웠느냐로
      // 전투력이 갈리고, 이 곡선은 그 분포의 꼭대기에 결승선을 놓는다
      // (실력 전 구간에서 3~6%, 즉 실력이 아니라 뽑기가 가른다).
      //
      // 여기서 [taper] 를 1.0 쪽으로 올리면 못 깨는 판이 중반에 죽지 않고
      // 94웨이브까지 간다(보통이 그렇게 맞춰져 있다). 그 대신 30웨이브 여유가
      // 3.1배에서 11.6배로 벌어져, **보통보다 쉬운 «어려움»** 이 된다.
      // 60웨이브 운빨 폭이 8배라 한 곡선으로 «운 나쁜 판» 과 «운 좋은 판» 을
      // 동시에 팽팽하게 만들 수는 없다 — 둘 중 하나를 골라야 한다.
      case GameMode.hard:
        return _hardHp(wave);
      // 지옥: 어려움과 규칙은 같고(초월 도박) 체력만 훨씬 높다. 결승선을
      // 초월 여러 기를 세워야 닿는 자리에 놓는다 — 도달률을 맞추는 대신
      // «초월 없이는 못 넘는다» 를 기준으로 삼은 모드다.
      case GameMode.hell:
        return _hellHp(wave);
      // 무한: «얼마나 멀리 가나» 가 전부라 끝까지 가파르다.
      case GameMode.endless:
        return baseHp * math.pow(1.125, wave - 1).toDouble();
    }
  }

  /// 어려움 체력. 100웨이브까지는 꺾인 곡선, 그 뒤는 거의 눕는다.
  ///
  /// 결승선이 150이라고 곡선을 그냥 늘리면 안 된다. 100 → 150 구간에서
  /// [_taperedHp] 는 아직 7배가 오르는데 플레이어는 «초월» 에서 멈춰 강화분만
  /// 늘기 때문이다 — 실제로 그대로 늘렸더니 도달률이 3%에서 **0%** 가 됐다.
  ///
  /// 그래서 100 이후는 웨이브당 [_hardLateGrowth] 만큼만 올린다. 앞의 100
  /// 웨이브는 한 글자도 달라지지 않으므로, 지금까지의 어려움에 «마지막 50
  /// 웨이브» 가 붙은 모양이 된다.
  static double _hardHp(int wave) {
    final knee = math.min(wave, 100);
    final base = _taperedHp(knee, growth: _hardHpGrowth, taper: 0.9875);
    return base *
        math.pow(_hardLateGrowth, math.max(0, wave - 100)).toDouble();
  }

  /// 100웨이브 이후 웨이브당 체력 증가율.
  static const double _hardLateGrowth = 1.005;

  /// 100웨이브까지의 증가율. 어려움과 지옥이 같이 쓴다 — 지옥은 여기가 아니라
  /// [_hellLateGrowth] 에서만 갈린다.
  static const double _hardHpGrowth = 1.147;

  /// 지옥 체력. **어려움 곡선 그 자체에**, 50웨이브부터 복리를 더 얹는다.
  ///
  /// 꺾이는 자리를 뒤로 둔 이유는 초반을 건드릴 수 없기 때문이다. 어려움에서
  /// 증가율을 0.005 만 올려 봤을 때 도달률이 3.4% → 0% 가 됐다 — 판이
  /// **11웨이브에서 초월 0기로** 죽는다. 초월을 보기도 전에 끝나므로 «초월이
  /// 더 필요한 모드» 가 아니라 «아무도 못 깨는 모드» 가 된다. 같은 이유로
  /// 초월 피해 배수를 4배에서 12배까지 올려 봐도 도달률이 소수점까지 똑같았다.
  ///
  /// 처음에는 «50까지 어려움, 그 뒤는 고정 증가율» 로 짰는데 **51웨이브에서
  /// 지옥이 어려움보다 약했다.** 어려움의 꺾인 곡선은 그 지점에서 웨이브당
  /// 7.6% 씩 오르는데 고정 5.5% 가 그보다 완만했기 때문이다. 그래서 곡선을
  /// 새로 그리는 대신 **어려움에 곱하는** 모양으로 바꿨다 — 이러면 어떤
  /// 웨이브에서도 지옥이 어려움보다 약할 수 없다.
  ///
  /// 3,200판씩 돌려 잰 값이다.
  ///
  ///   곱하는 값  100웨 체력   150웨 체력    도달률   깬 판 초월   깬 판 수
  ///   1.014       545,400    1,402,542     1.83%    5기(3~8)    44/2400
  ///   1.018       664,058    2,079,209     0.47%    6기(4~8)    15/3200
  ///   1.020(지옥)  732,531    2,530,099     0.19%    6기(6~8)     6/3200
  ///   1.022       807,908    3,077,585     0.03%    6기(6~6)     1/3200
  ///   1.025       935,429    4,125,788     0.00%      —          0/3200
  ///
  /// 1.020 을 골랐다 — 500판에 한 번쯤 깨지고, 깨는 판은 초월을 6기 이상
  /// 세운 판뿐이다. 도박이 15% 라 8기는 사실상 뽑기 운의 천장이다.
  /// 1.022 는 3,200판에 한 판이라 «깨진다» 고 말할 표본이 못 된다.
  ///
  /// **0.005 만 더 올리면 0% 다.** 이 근처에서는 체력을 올리는 것이 도달률과
  /// 1:1 이 아니라 절벽으로 맞바꿔진다 — 플레이어 전투력이 초월에서 멈추기
  /// 때문이다. 다른 수치(소환 비용·피해표·슬롯 수)를 건드리면 이 값도 같이
  /// 다시 재야 한다.
  ///
  /// 위 표는 라이프 20 시절에 잰 것이다. 지금 지옥은 라이프가 1이므로
  /// ([hellLives]) 실제 도달률은 이보다 낮다.
  ///
  ///   dart run tool/balance_sim.dart --top
  static double _hellHp(int wave) =>
      _hardHp(wave) *
      math.pow(_hellExtra, math.max(0, wave - _hellKnee)).toDouble();

  /// 지옥에서 어려움 위에 복리가 붙기 시작하는 웨이브.
  static const int _hellKnee = 50;

  /// [_hellKnee] 이후 웨이브마다 어려움 체력에 추가로 곱하는 값.
  static const double _hellExtra = 1.030;

  /// 증가율이 웨이브마다 [taper] 배씩 꺾이는 체력 곡선.
  ///
  /// 플레이어 전투력은 «초월» 에서 멈추므로 후반에는 더 늘지 않는다. 체력만
  /// 끝까지 같은 비율로 올리면 중반 50웨이브가 손 놓아도 되는 구간이 되고
  /// 마지막 몇 웨이브만 난이도가 된다(쉬움 곡선이 딱 그렇다 — 중반 여유가
  /// 10배 안팎까지 벌어진다). 증가율을 조금씩 꺾으면 여유가 처음부터 끝까지
  /// 비슷하게 유지된다.
  static double _taperedHp(
    int wave, {
    required double growth,
    required double taper,
  }) {
    final steps = (1 - math.pow(taper, wave - 1)) / (1 - taper);
    return baseHp * math.pow(growth, steps).toDouble();
  }

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

  /// 고급소환 비용(다이아).
  ///
  /// 보스 하나가 고급소환 한 번이 되도록 맞췄다([bossGems] 는 40웨이브에서 8).
  /// 12 였을 때는 행운 3~4레벨을 포기하는 값이라 누를 이유가 없었다 — 다이아
  /// 수입이 한 판에 95 인데 행운을 끝까지 올리는 데만 225 가 들기 때문이다.
  static const int highSummonGems = 8;

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
