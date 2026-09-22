// 난이도 시뮬레이터.
//
//   dart run tool/balance_sim.dart           현재 밸런스 리포트
//   dart run tool/balance_sim.dart --curve   웨이브별 여유(보유 DPS ÷ 필요 DPS)
//   dart run tool/balance_sim.dart --levers  조정 레버별 효과 비교
//   dart run tool/balance_sim.dart --luck    운이 당락을 가르는지 측정
//   dart run tool/balance_sim.dart --gems    다이아를 어디에 쓰는 게 이득인지
//
// 공식은 `lib/game/data/balance.dart` 를 그대로 가져다 쓴다. 수치를 고치면
// 여기도 따라가므로 «게임과 시뮬레이터가 어긋나는» 일이 없다.
//
// 다만 세 가지는 이 파일이 복사해서 쓴다. 도감(`unit_catalog.dart`)과
// 필드(`field_layout.dart`)가 Flutter 에 의존해 순수 Dart 스크립트에서
// 불러올 수 없기 때문이다.
//   1. 등급별 유닛 종류 수 [kTypesPerRarity]
//   2. 슬롯 수 [kSlots]
//   3. 유닛별 피해·공속 배율 [kUnitMultipliers]
//   4. 자동 판매 대상 고르는 규칙 [_autoSellIndex] — pickAutoSellIndex 의 사본
//      고급소환이 겨냥할 유닛 [_highSummonTarget] — pickHighSummonTarget 의 사본
// 1~3 은 테스트(«시뮬레이터가 복사해 쓰는 상수가 실제 게임과 맞는다»)가
// 어긋나지 않도록 지켜 준다.

import 'dart:io';
import 'dart:math' as math;

import 'package:ddai_lucky_defense/game/data/balance.dart';
import 'package:ddai_lucky_defense/game/data/game_mode.dart';

/// 등급별 유닛 종류 수(노말 ~ 초월).
const List<int> kTypesPerRarity = [4, 4, 4, 4, 4, 3, 3];

/// 배치 가능한 슬롯 수.
const int kSlots = 21;

/// 유닛마다 붙은 (피해, 공속) 배율. 등급별로 종류 순서대로다.
///
/// 이걸 빼고 등급 기본치만 쓰면 **초월을 크게 과소평가한다.** 초월 셋의 배율
/// 곱이 평균 1.92 라, 등급 기본치로만 재면 초월 한 기가 신화의 18.1배로
/// 나오지만 실제로는 25.8배다. 그만큼 필요한 초월 기수가 부풀려져, 조정할
/// 때마다 같은 방향으로 틀린다.
const List<List<(double dmg, double spd)>> kUnitMultipliers = [
  [(1.0, 1.12), (0.85, 0.9), (0.7, 0.88), (0.8, 1.0)], // 노말
  [(1.05, 0.85), (0.9, 1.05), (0.8, 1.0), (1.38, 0.8)], // 레어
  [(1.28, 1.1), (0.95, 1.0), (1.1, 0.85), (0.95, 1.15)], // 유니크
  [(1.2, 0.9), (1.05, 1.0), (1.05, 1.1), (1.15, 1.25)], // 에픽
  [(1.25, 1.0), (1.15, 1.05), (1.95, 0.95), (1.05, 1.3)], // 레전더리
  [(1.3, 1.0), (1.45, 1.0), (1.2, 1.1)], // 신화
  [(1.6, 1.2), (1.75, 1.1), (2.1, 0.92)], // 초월
];

/// 사거리 밖이거나 재장전 중이라 명목 DPS 가 전부 몬스터에게 닿지는 않는다.
/// 광역 유닛이 여럿을 동시에 때리는 몫은 일부 되돌아온다.
/// 모델에서 가장 불확실한 값이라, 두 가지로 나눠 본다.
const double kSkilledCoverage = 0.80;
const double kCasualCoverage = 0.55;

/// 한 판을 돌릴 때 바꿔 볼 수 있는 값들. 넘기지 않으면 실제 게임 수치를 쓴다.
class SimConfig {
  const SimConfig({
    this.label = '현재',
    this.coverage = kSkilledCoverage,
    this.upgradeShare = 0.45,
    this.mode = GameMode.endless,
    this.enemyHp,
    this.summonCost,
    this.damage,
    this.goldScale = 1.0,
    this.slots = kSlots,
    this.lives,
    this.waveInterval = Balance.waveInterval,
    this.bossHpMultiplier = Balance.bossHpMultiplier,
    this.startLuck = 0,
    this.mergeAnyOfRarity = false,
    this.luckCap = Balance.luckMaxLevel,
    this.highSummons = false,
  });

  final String label;
  final double coverage;

  /// 플레이 방식. 체력 곡선이 모드마다 다르다.
  final GameMode mode;

  /// 웨이브마다 들어온 골드 중 강화에 쓰는 비율.
  final double upgradeShare;

  final double Function(int wave)? enemyHp;
  final int Function(int unitCount)? summonCost;
  final List<double>? damage;
  final double goldScale;
  final int slots;
  /// 시작 라이프. 안 넘기면 모드 기본값을 쓴다(지옥은 1).
  final int? lives;

  int get livesAt => lives ?? Balance.startLivesOf(mode);
  final double waveInterval;
  final double bossHpMultiplier;
  final int startLuck;

  /// 참이면 «같은 등급 아무 3개» 로 합성한다(현재 규칙은 같은 유닛 3개).
  final bool mergeAnyOfRarity;

  /// 행운을 여기까지만 올린다. 남는 다이아는 [highSummons] 에 쓰인다.
  final int luckCap;

  /// 참이면 남는 다이아로 고급소환을 한다.
  final bool highSummons;

  double hpAt(int wave) => enemyHp?.call(wave) ?? Balance.enemyHp(wave, mode);
  int costAt(int units) => summonCost?.call(units) ?? Balance.summonCost(units);

  /// 모드 보정까지 반영한 등급별 피해(어려움의 초월 보너스).
  List<double> get damageTable => [
    for (var r = 0; r < (damage ?? Balance.damage).length; r++)
      (damage ?? Balance.damage)[r] * Balance.rarityDamageBonus(r, mode),
  ];

  /// 이 모드가 끝나는 웨이브. 무한이면 null.
  int? get clearWave => Balance.clearWave(mode);

  /// [fromRarity] 3개를 합성할 성공 확률. 어려움의 초월 합성만 1 보다 작다.
  double mergeChanceAt(int fromRarity) =>
      Balance.mergeChance(fromRarity, mode);

  SimConfig copyWith({
    String? label,
    double? coverage,
    GameMode? mode,
    int? luckCap,
    bool? highSummons,
  }) => SimConfig(
        label: label ?? this.label,
        coverage: coverage ?? this.coverage,
        upgradeShare: upgradeShare,
        mode: mode ?? this.mode,
        enemyHp: enemyHp,
        summonCost: summonCost,
        damage: damage,
        goldScale: goldScale,
        slots: slots,
        lives: lives,
        waveInterval: waveInterval,
        bossHpMultiplier: bossHpMultiplier,
        startLuck: startLuck,
        mergeAnyOfRarity: mergeAnyOfRarity,
        luckCap: luckCap ?? this.luckCap,
        highSummons: highSummons ?? this.highSummons,
      );
}

/// (등급, 유닛 종류) 한 기.
typedef Unit = (int rarity, int type);

class WaveSnapshot {
  WaveSnapshot(this.wave, this.need, this.have, this.summons, this.topRarity);
  final int wave;
  final double need;
  final double have;
  final int summons;
  final int topRarity;

  double get headroom => have / need;
}

class RunResult {
  RunResult(this.endedAt, this.waves, this.topCount);
  final int endedAt;
  final List<WaveSnapshot> waves;

  /// 판이 끝난 시점에 보드에 있던 최고 등급(초월) 기수.
  ///
  /// «초월 몇 기면 깨지는가» 를 재려고 둔다. 도달률만 보면 모드가 어려운
  /// 것은 알아도 «무엇이 모자라서» 못 깨는지는 알 수 없다.
  final int topCount;
}

int _topCount(List<Unit> units) =>
    units.where((u) => u.$1 == Balance.topTier).length;

/// 한 판을 끝까지 돌린다. 라이프가 0이 된 웨이브를 돌려준다.
RunResult runOnce(int seed, SimConfig c, {int maxWave = 80}) {
  final rng = math.Random(seed);
  final units = <Unit>[];
  final waves = <WaveSnapshot>[];
  var gold = Balance.startGold;
  var gems = Balance.startGems;
  var lives = c.livesAt;
  var atk = 0;
  var spd = 0;
  var gld = 0;
  var luck = c.startLuck;

  for (var w = 1; w <= maxWave; w++) {
    gold += (Balance.clearGold(w) * c.goldScale * Balance.goldBonus(gld))
        .round();

    // 강화: 배정한 예산 안에서 가장 싼 것부터 계속 산다.
    var budget = gold * c.upgradeShare;
    while (true) {
      final options = <(int, int)>[
        (Balance.atkUpgradeCost(atk), 0),
        (Balance.spdUpgradeCost(spd), 1),
        (Balance.goldUpgradeCost(gld), 2),
      ]..sort((a, b) => a.$1.compareTo(b.$1));
      final (cost, kind) = options.first;
      if (cost > budget || cost > gold) {
        break;
      }
      gold -= cost;
      budget -= cost;
      if (kind == 0) {
        atk++;
      } else if (kind == 1) {
        spd++;
      } else {
        gld++;
      }
    }

    // 소환: 남는 골드로 최대한. 자리가 없으면 자동 판매가 끼어든다.
    var summons = 0;
    while (true) {
      final full = units.length >= c.slots;
      final cost = c.costAt(full ? units.length - 1 : units.length);
      final sellAt = full ? _autoSellIndex(units) : -1;
      final refund = sellAt < 0 ? 0 : Balance.sellPrice[units[sellAt].$1];
      if (gold + refund < cost) {
        break;
      }
      if (full) {
        gold += refund;
        units.removeAt(sellAt);
      }
      gold -= cost;
      units.add(_roll(rng, luck));
      _autoMerge(units, rng, c, anyOfRarity: c.mergeAnyOfRarity);
      summons++;
    }

    while (luck < c.luckCap && gems >= Balance.luckCost(luck)) {
      gems -= Balance.luckCost(luck);
      luck++;
    }

    // 고급소환: 남는 다이아로. 합성까지 하나 남은 유닛이 있으면 그걸 준다.
    while (c.highSummons && gems >= Balance.highSummonGems) {
      final full = units.length >= c.slots;
      final sellAt = full ? _autoSellIndex(units) : -1;
      if (full && sellAt < 0) {
        break;
      }
      if (full) {
        gold += Balance.sellPrice[units[sellAt].$1];
        units.removeAt(sellAt);
      }
      gems -= Balance.highSummonGems;
      units.add(_highSummonTarget(units) ?? _rollHigh(rng, luck));
      _autoMerge(units, rng, c, anyOfRarity: c.mergeAnyOfRarity);
    }

    final isBoss = w % Balance.bossEvery == 0;
    final isRush = !isBoss && w % Balance.rushEvery == 0;
    final hp =
        c.hpAt(w) *
        (isBoss
            ? c.bossHpMultiplier
            : (isRush ? Balance.rushHpMultiplier : 1.0));
    final count = isBoss
        ? 1
        : (Balance.enemyCount(w) * (isRush ? Balance.rushCountMultiplier : 1.0))
              .round();
    // 보스는 느리게 걸어 한 바퀴 도는 데 오래 걸리므로 때릴 시간이 더 길다.
    final window = isBoss
        ? Balance.lapSeconds(w) * Balance.bossLapMultiplier
        : c.waveInterval;

    final need = hp * count / window;
    final have = _dps(units, c, atk, spd);
    final top = units.fold(0, (m, u) => math.max(m, u.$1));
    waves.add(WaveSnapshot(w, need, have, summons, top));

    if (have >= need) {
      gold +=
          (Balance.killGold(w) * count * c.goldScale * Balance.goldBonus(gld))
              .round();
      if (isBoss) {
        gold += (Balance.bossGold(w) * c.goldScale * Balance.goldBonus(gld))
            .round();
        gems += Balance.bossGems(w);
      }
    } else {
      // 막지 못한 비율만큼 몬스터가 성까지 간다.
      final leaked = have / need;
      lives -= isBoss
          ? Balance.bossLifeCost
          : math.max(1, (count * (1 - leaked)).toInt());
      gold +=
          (Balance.killGold(w) *
                  count *
                  leaked *
                  c.goldScale *
                  Balance.goldBonus(gld))
              .round();
      if (lives <= 0) {
        return RunResult(w, waves, _topCount(units));
      }
    }
  }
  return RunResult(maxWave, waves, _topCount(units));
}

double _dps(List<Unit> units, SimConfig c, int atk, int spd) {
  final table = c.damageTable;
  var base = 0.0;
  for (final u in units) {
    final (dmg, spdMul) = kUnitMultipliers[u.$1][u.$2];
    base += table[u.$1] * dmg * Balance.attackSpeed[u.$1] * spdMul;
  }
  return base * Balance.atkBonus(atk) * Balance.spdBonus(spd) * c.coverage;
}

Unit _roll(math.Random rng, int luck) {
  final weights = Balance.summonWeights(luck);
  final total = weights.fold<double>(0, (a, b) => a + b);
  var pick = rng.nextDouble() * total;
  for (var i = 0; i < weights.length; i++) {
    if (pick < weights[i]) {
      return (i, rng.nextInt(kTypesPerRarity[i]));
    }
    pick -= weights[i];
  }
  return (0, rng.nextInt(kTypesPerRarity[0]));
}

/// 자동 합성. 도박(어려움의 초월 합성)이면 실패할 수 있고, 실패하면
/// 재료가 [Balance.mergeFailLoss] 개 사라진다.
///
/// 게임에서는 도박을 자동으로 걸지 않지만(플레이어가 고른다) 시뮬레이터는
/// «늘 건다» 로 본다 — 기댓값이 1.19배라 거는 쪽이 이득이기 때문이다.
/// 유니크 이상 확정 소환.
Unit _rollHigh(math.Random rng, int luck) {
  final weights = Balance.summonWeights(luck).sublist(2);
  final total = weights.fold<double>(0, (a, b) => a + b);
  var pick = rng.nextDouble() * total;
  for (var i = 0; i < weights.length; i++) {
    if (pick < weights[i]) {
      return (i + 2, rng.nextInt(kTypesPerRarity[i + 2]));
    }
    pick -= weights[i];
  }
  return (2, rng.nextInt(kTypesPerRarity[2]));
}

/// `pickHighSummonTarget` 의 사본. 규칙이 바뀌면 여기도 같이 고친다.
///
/// 합성까지 하나 남은 유닛 중 가장 높은 등급. 소환으로 나올 수 있는 등급
/// (유니크 ~ 레전더리)만 겨냥한다.
Unit? _highSummonTarget(List<Unit> units) {
  const lowest = 2;
  final highest = Balance.summonWeights(0).length - 1;
  final counts = <Unit, int>{};
  for (final u in units) {
    counts.update(u, (v) => v + 1, ifAbsent: () => 1);
  }
  Unit? best;
  for (final e in counts.entries) {
    if (e.key.$1 < lowest || e.key.$1 > highest) {
      continue;
    }
    if (e.value != Balance.mergeCount - 1) {
      continue;
    }
    if (best == null || e.key.$1 > best.$1) {
      best = e.key;
    }
  }
  return best;
}

void _autoMerge(
  List<Unit> units,
  math.Random rng,
  SimConfig config, {
  required bool anyOfRarity,
}) {
  while (true) {
    final counts = <Object, int>{};
    for (final u in units) {
      final key = anyOfRarity ? u.$1 : u;
      counts.update(key, (v) => v + 1, ifAbsent: () => 1);
    }
    Object? hit;
    for (final e in counts.entries) {
      final rarity = anyOfRarity ? e.key as int : (e.key as Unit).$1;
      if (e.value >= Balance.mergeCount &&
          rarity + 1 < kTypesPerRarity.length) {
        hit = e.key;
        break;
      }
    }
    if (hit == null) {
      return;
    }
    final rarity = anyOfRarity ? hit as int : (hit as Unit).$1;
    final chance = config.mergeChanceAt(rarity);
    final failed = chance < 1 && rng.nextDouble() >= chance;
    final burn = failed ? Balance.mergeFailLoss : Balance.mergeCount;
    var removed = 0;
    units.removeWhere((u) {
      if (removed >= burn) {
        return false;
      }
      final match = anyOfRarity ? u.$1 == rarity : u == hit;
      if (match) {
        removed++;
      }
      return match;
    });
    if (!failed) {
      units.add((rarity + 1, rng.nextInt(kTypesPerRarity[rarity + 1])));
    }
  }
}

/// `pickAutoSellIndex` 의 사본. 규칙이 바뀌면 여기도 같이 고친다.
int _autoSellIndex(List<Unit> units) {
  if (units.isEmpty) {
    return -1;
  }
  final counts = <Unit, int>{};
  var lowest = kTypesPerRarity.length;
  for (final u in units) {
    counts.update(u, (v) => v + 1, ifAbsent: () => 1);
    lowest = math.min(lowest, u.$1);
  }
  var best = -1;
  var bestBreaks = true;
  var bestCount = 1 << 30;
  for (var i = 0; i < units.length; i++) {
    final u = units[i];
    if (u.$1 != lowest) {
      continue;
    }
    final count = counts[u]!;
    final breaks =
        u.$1 + 1 < kTypesPerRarity.length && count % Balance.mergeCount == 0;
    if (best == -1 ||
        (bestBreaks && !breaks) ||
        (bestBreaks == breaks && count < bestCount)) {
      best = i;
      bestBreaks = breaks;
      bestCount = count;
    }
  }
  return best;
}

const int _seeds = 80;

double _medianEnd(SimConfig c, {int maxWave = 80}) {
  final ends = [
    for (var s = 0; s < _seeds; s++) runOnce(s, c, maxWave: maxWave).endedAt,
  ]..sort();
  return (ends[(_seeds - 1) ~/ 2] + ends[_seeds ~/ 2]) / 2;
}

String _num(num v) {
  final s = v.round().toString();
  return s.replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
}

String _pad(String s, int width) {
  // 한글은 두 칸으로 세어야 표가 맞는다.
  var w = 0;
  for (final r in s.runes) {
    w += r > 0x1100 ? 2 : 1;
  }
  return s + ' ' * math.max(0, width - w);
}

void _report() {
  stdout.writeln('따이 운빨 디펜스 밸런스 리포트');
  stdout.writeln('─' * 62);
  for (final mode in GameMode.values) {
    double hp(int w) => Balance.enemyHp(w, mode);
    // 끝나는 웨이브가 모드마다 다르므로 그 지점 체력도 같이 보여 준다.
    final end = Balance.clearWave(mode);
    stdout.writeln(
      '${_pad(mode.label, 7)}체력  '
      '1웨 ${_num(hp(1))} · 30웨 ${_num(hp(30))} · '
      '60웨 ${_num(hp(60))} · 100웨 ${_num(hp(100))}'
      '${end == null || end == 100 ? '' : ' · $end웨 ${_num(hp(end))}'}',
    );
  }
  stdout.writeln(
    '웨이브 수입   '
    '10웨 ${_num(Balance.clearGold(10) + Balance.killGold(10) * Balance.enemyCount(10))} G · '
    '30웨 ${_num(Balance.clearGold(30) + Balance.killGold(30) * Balance.enemyCount(30))} G',
  );
  stdout.writeln(
    '소환 비용     빈 슬롯 ${_num(Balance.summonCost(0))} G · '
    '가득 ${_num(Balance.summonCost(kSlots - 1))} G',
  );
  stdout.writeln('슬롯          $kSlots칸');
  stdout.writeln('');
  stdout.writeln('$_seeds판 중앙값');
  for (final mode in GameMode.values) {
    final skilled = const SimConfig().copyWith(mode: mode);
    final casual = skilled.copyWith(coverage: kCasualCoverage);
    if (mode.isEndless) {
      stdout.writeln(
        '  ${_pad(mode.label, 7)}생존 웨이브   '
        '숙련자 ${_medianEnd(skilled).toStringAsFixed(0)} · '
        '라이트 ${_medianEnd(casual).toStringAsFixed(0)}',
      );
    } else {
      stdout.writeln(
        '  ${_pad(mode.label, 7)}${Balance.clearWave(mode)}웨이브 도달률  '
        '전체 ${_clearRateAcrossSkill(mode).toStringAsFixed(0)}% '
        '(숙련자 ${_clearRate(skilled).toStringAsFixed(0)}% · '
        '라이트 ${_clearRate(casual).toStringAsFixed(0)}%)'
        '   중반 최저 여유 ${_minHeadroom(casual).toStringAsFixed(2)}'
        ' · 라이트가 멈추는 웨이브 '
        '${_medianEnd(casual, maxWave: Balance.clearWave(mode)!).toStringAsFixed(0)}',
      );
    }
  }
}

/// 10~90웨이브 구간에서 여유가 가장 빠듯했던 지점. 1.0 에 가까울수록 팽팽하다.
double _minHeadroom(SimConfig c) {
  final byWave = <int, List<double>>{};
  for (var s = 0; s < _seeds; s++) {
    for (final snap in runOnce(s, c, maxWave: c.clearWave!).waves) {
      byWave.putIfAbsent(snap.wave, () => []).add(snap.headroom);
    }
  }
  var worst = double.infinity;
  for (var w = 10; w <= 90; w++) {
    final list = byWave[w];
    if (list == null || list.length < _seeds / 2) {
      continue;
    }
    list.sort();
    worst = math.min(worst, list[list.length ~/ 2]);
  }
  return worst;
}

/// 실력 분포 전체에 걸친 도달률.
///
/// 커버리지를 한 값으로 고정해 재면 도달률이 100% 아니면 0% 로 튄다. 후반에는
/// 누구나 «초월» 에서 멈춰 전투력이 같아지기 때문에, 그 한 사람이 깨느냐 마느냐로
/// 결과가 갈리는 탓이다. 실력을 [kCasualCoverage] ~ [kSkilledCoverage] 사이에서
/// 고르게 훑어야 «몇 %가 깨는가» 가 제대로 나온다.
double _clearRateAcrossSkill(GameMode mode) {
  const steps = 8;
  final runs = _seeds ~/ 2;
  var cleared = 0;
  for (var i = 0; i < steps; i++) {
    final coverage =
        kCasualCoverage +
        (kSkilledCoverage - kCasualCoverage) * i / (steps - 1);
    final config = SimConfig(mode: mode, coverage: coverage);
    for (var s = 0; s < runs; s++) {
      if (runOnce(s, config, maxWave: config.clearWave!).endedAt >=
          config.clearWave!) {
        cleared++;
      }
    }
  }
  return cleared / (steps * runs) * 100;
}

/// «초월 몇 기면 깨지는가» 를 실력 전 구간에서 재서 표로 찍는다.
///
///   dart run tool/balance_sim.dart --top
///
/// 도달률 하나로는 모드가 왜 어려운지 알 수 없다. 깬 판과 못 깬 판의 초월
/// 기수를 나란히 보면 «체력이 높아서» 인지 «초월이 안 나와서» 인지 갈린다.
void _topReport() {
  const steps = 8;
  final runs = _seeds ~/ 2;
  stdout.writeln('초월 기수와 결과 — 실력 전 구간, 모드별');
  stdout.writeln('─' * 62);
  stdout.writeln('표본은 모드마다 ${steps * runs}판이다 — 도달률이 이보다 낮은');
  stdout.writeln('모드는 0% 로 찍힌다. «불가능» 이 아니라 «여기서는 안 잡힌다» 다.');
  stdout.writeln('');
  stdout.writeln('모드    결승선  도달률   깬 판 초월(중앙)  못 깬 판 초월(중앙)  깬 판 수');
  for (final mode in GameMode.values) {
    final end = Balance.clearWave(mode);
    if (end == null) {
      continue;
    }
    final won = <int>[];
    final lost = <int>[];
    for (var i = 0; i < steps; i++) {
      final coverage =
          kCasualCoverage +
          (kSkilledCoverage - kCasualCoverage) * i / (steps - 1);
      final c = SimConfig(mode: mode, coverage: coverage);
      for (var s = 0; s < runs; s++) {
        final r = runOnce(s, c, maxWave: end);
        (r.endedAt >= end ? won : lost).add(r.topCount);
      }
    }
    final rate = won.length / (won.length + lost.length) * 100;
    stdout.writeln(
      '${mode.label.padRight(7)}${end.toString().padLeft(5)}'
      '${rate.toStringAsFixed(2).padLeft(7)}%'
      '${_median(won).padLeft(15)}${_median(lost).padLeft(18)}'
      '${'${won.length}/${won.length + lost.length}'.padLeft(12)}',
    );
  }
}

String _median(List<int> xs) {
  if (xs.isEmpty) {
    return '-';
  }
  final sorted = [...xs]..sort();
  return sorted[sorted.length ~/ 2].toString();
}

/// 클리어 모드에서 마지막 웨이브까지 간 판의 비율.
double _clearRate(SimConfig c) {
  var cleared = 0;
  for (var s = 0; s < _seeds; s++) {
    if (runOnce(s, c, maxWave: c.clearWave!).endedAt >= c.clearWave!) {
      cleared++;
    }
  }
  return cleared / _seeds * 100;
}

/// 이 게임이 정말 «운빨» 인지 재는 자.
///
/// 실력(커버리지)을 고정하면 판마다 다른 건 뽑기 운뿐이다. 그래서 두 가지를 본다.
///  1. **운빨 폭** — 같은 실력으로 여러 판을 돌렸을 때 전투력이 얼마나 갈리는지.
///     1.0 에 가까우면 어떤 판이든 결국 같은 보드가 된다는 뜻이다.
///  2. **실력별 도달률** — 실력을 바꿔 가며 잰 도달률. 0%→100% 로 튀면 당락을
///     가르는 건 실력이고, 실력이 달라도 비슷하면 운이 가른다.
///
/// 폭을 재는 동안에는 죽어서 판이 끊기지 않도록 체력 곡선만 쉬움으로 바꾼다.
/// 합성 규칙과 피해 보정은 원래 모드 그대로다.
void _luck() {
  const waves = [20, 40, 60, 80, 100];
  stdout.writeln('운빨 폭 — 같은 실력, 판마다 벌어지는 전투력 (p90 ÷ p10)');
  stdout.writeln('1.0 에 가까우면 운이 아무것도 바꾸지 못한다는 뜻이다.');
  stdout.writeln('─' * 52);
  stdout.writeln(
    '${_pad("모드", 9)}${waves.map((w) => _pad("$w웨", 8)).join()}',
  );
  for (final mode in GameMode.values) {
    final config = SimConfig(
      mode: mode,
      enemyHp: (w) => Balance.enemyHp(w, GameMode.easy),
    );
    final byWave = <int, List<double>>{};
    for (var s = 0; s < _seeds; s++) {
      for (final snap in runOnce(s, config, maxWave: 100).waves) {
        byWave.putIfAbsent(snap.wave, () => []).add(snap.have);
      }
    }
    final cells = [
      for (final w in waves)
        _pad(_spread(byWave[w], _seeds)?.toStringAsFixed(2) ?? '-', 8),
    ];
    stdout.writeln('${_pad(mode.label, 9)}${cells.join()}');
  }

  stdout.writeln('');
  stdout.writeln('실력별 도달률 — 평평할수록 운이 가른다 (모드마다 끝나는 웨이브가 다르다)');
  stdout.writeln('─' * 52);
  const skills = [0.55, 0.65, 0.70, 0.75, 0.80];
  stdout.writeln(
    '${_pad("모드", 9)}'
    '${skills.map((c) => _pad(c.toStringAsFixed(2), 8)).join()}',
  );
  for (final mode in GameMode.values) {
    if (mode.isEndless) {
      continue;
    }
    final cells = [
      for (final skill in skills)
        _pad(
          '${_clearRate(SimConfig(mode: mode, coverage: skill)).toStringAsFixed(0)}%',
          8,
        ),
    ];
    stdout.writeln('${_pad(mode.label, 9)}${cells.join()}');
  }
}

/// [values] 의 p90 ÷ p10. 표본이 모자라면 null.
double? _spread(List<double>? values, int seeds) {
  if (values == null || values.length < seeds / 2) {
    return null;
  }
  final sorted = [...values]..sort();
  final low = sorted[(sorted.length * 0.1).floor()];
  final high = sorted[math.min(sorted.length - 1, (sorted.length * 0.9).floor())];
  return low == 0 ? null : high / low;
}

/// 다이아를 어디에 쓰는 게 이득인지.
///
/// 다이아 수입은 한 판에 95개(보스 10번)인데 행운을 끝까지 올리는 데만 225개가
/// 든다. 한 판에 다 채울 수 없으니 «언제나 행운» 이 최적이 되기 쉽고, 그러면
/// 고급소환은 눌러 볼 이유가 없는 버튼이 된다. 그 구도를 숫자로 본다.
void _gems() {
  final income = [
    for (var w = Balance.bossEvery;
        w <= Balance.clearWave(GameMode.normal)!;
        w += Balance.bossEvery)
      Balance.bossGems(w),
  ].fold<int>(0, (a, b) => a + b);
  var luckTotal = 0;
  for (var lv = 0; lv < Balance.luckMaxLevel; lv++) {
    luckTotal += Balance.luckCost(lv);
  }
  stdout.writeln(
    '다이아 수입 ${Balance.clearWave(GameMode.normal)}웨이브까지 $income개 · '
    '행운 끝까지 올리는 값 $luckTotal개 · 고급소환 ${Balance.highSummonGems}개',
  );
  stdout.writeln('─' * 62);
  stdout.writeln(
    '${_pad("다이아 쓰는 법", 26)}${_pad("무한", 8)}'
    '${_pad("보통", 8)}어려움',
  );

  final policies = <(String, SimConfig Function(GameMode))>[
    ('전부 행운', (m) => SimConfig(mode: m)),
    (
      '전부 고급소환',
      (m) => SimConfig(mode: m, luckCap: 0, highSummons: true),
    ),
    for (final cap in [6, 10, 14])
      (
        '행운 $cap렙까지 → 고급소환',
        (m) => SimConfig(mode: m, luckCap: cap, highSummons: true),
      ),
  ];

  for (final (label, make) in policies) {
    final ends = [
      for (var s = 0; s < _seeds; s++)
        runOnce(s, make(GameMode.endless), maxWave: 150).endedAt,
    ]..sort();
    final endless = (ends[(_seeds - 1) ~/ 2] + ends[_seeds ~/ 2]) / 2;
    stdout.writeln(
      '${_pad(label, 26)}'
      '${_pad("${endless.toStringAsFixed(0)}웨", 8)}'
      '${_pad("${_clearRate(make(GameMode.normal)).toStringAsFixed(0)}%", 8)}'
      '${_clearRate(make(GameMode.hard)).toStringAsFixed(0)}%',
    );
  }
}

void _curve(GameMode mode) {
  final skilled = const SimConfig().copyWith(mode: mode);
  final byWave = <int, List<double>>{};
  for (var s = 0; s < _seeds; s++) {
    for (final snap in runOnce(s, skilled, maxWave: 110).waves) {
      byWave.putIfAbsent(snap.wave, () => []).add(snap.headroom);
    }
  }
  stdout.writeln('웨이브별 여유 (보유 DPS ÷ 필요 DPS, 중앙값)');
  stdout.writeln('1.0 아래면 그 웨이브에서 몬스터가 새어 나간다.');
  stdout.writeln('─' * 52);
  final waves = byWave.keys.toList()..sort();
  for (final w in waves) {
    final list = byWave[w]!..sort();
    if (list.length < _seeds / 2) {
      break;
    }
    final median = list[list.length ~/ 2];
    final bar = '■' * math.min(24, (median * 4).round());
    stdout.writeln(
      '${w.toString().padLeft(3)}  '
      '${median.toStringAsFixed(2).padLeft(6)}  $bar',
    );
  }
}

void _levers() {
  const base = SimConfig();
  final baseSkilled = _medianEnd(base);
  final baseCasual = _medianEnd(base.copyWith(coverage: kCasualCoverage));

  final levers = <SimConfig>[
    SimConfig(
      label: '체력 증가율 −0.03',
      enemyHp: (w) =>
          Balance.enemyHp(1, GameMode.endless) *
          math
              .pow(
                (Balance.enemyHp(11, GameMode.endless) /
                        Balance.enemyHp(10, GameMode.endless)) -
                    0.03,
                w - 1,
              )
              .toDouble(),
    ),
    const SimConfig(label: '골드 수입 ×1.4', goldScale: 1.4),
    const SimConfig(label: '골드 수입 ×2.0', goldScale: 2.0),
    SimConfig(label: '등급 배율 4.2×', damage: _geometric(4.2)),
    const SimConfig(label: '합성: 같은 등급 아무 3개', mergeAnyOfRarity: true),
    const SimConfig(label: '슬롯 24칸', slots: 24),
    SimConfig(label: '소환 비용 계수 6', summonCost: (n) => 24 + 6 * n),
    const SimConfig(label: '라이프 30', lives: 30),
    const SimConfig(label: '웨이브 간격 26초', waveInterval: 26),
    const SimConfig(label: '보스 체력 ×20', bossHpMultiplier: 20),
    const SimConfig(label: '행운 시작 Lv.10', startLuck: 10),
  ];

  stdout.writeln('조정 레버별 효과 ($_seeds판 중앙값)');
  stdout.writeln('─' * 52);
  stdout.writeln('${_pad("조정", 30)}${_pad("숙련자", 9)}${_pad("라이트", 9)}증감');
  stdout.writeln(
    '${_pad("현재 (기준)", 30)}'
    '${_pad(baseSkilled.toStringAsFixed(0), 9)}'
    '${_pad(baseCasual.toStringAsFixed(0), 9)}-',
  );
  for (final lever in levers) {
    final a = _medianEnd(lever);
    final b = _medianEnd(lever.copyWith(coverage: kCasualCoverage));
    final delta = a - baseSkilled;
    stdout.writeln(
      '${_pad(lever.label, 30)}'
      '${_pad(a.toStringAsFixed(0), 9)}'
      '${_pad(b.toStringAsFixed(0), 9)}'
      '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(0)}',
    );
  }
}

List<double> _geometric(double step) {
  final out = <double>[Balance.damage.first];
  for (var i = 1; i < Balance.damage.length; i++) {
    out.add(out.last * step);
  }
  return out;
}

void main(List<String> args) {
  if (args.contains('--top')) {
    _topReport();
  } else if (args.contains('--levers')) {
    _levers();
  } else if (args.contains('--luck')) {
    _luck();
  } else if (args.contains('--gems')) {
    _gems();
  } else if (args.contains('--curve')) {
    _curve(
      args.contains('--easy')
          ? GameMode.easy
          : args.contains('--normal')
          ? GameMode.normal
          : args.contains('--hard')
          ? GameMode.hard
          : GameMode.endless,
    );
  } else {
    _report();
  }
}
