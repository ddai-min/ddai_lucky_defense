// 난이도 시뮬레이터.
//
//   dart run tool/balance_sim.dart           현재 밸런스 리포트
//   dart run tool/balance_sim.dart --curve   웨이브별 여유(보유 DPS ÷ 필요 DPS)
//   dart run tool/balance_sim.dart --levers  조정 레버별 효과 비교
//
// 공식은 `lib/game/data/balance.dart` 를 그대로 가져다 쓴다. 수치를 고치면
// 여기도 따라가므로 «게임과 시뮬레이터가 어긋나는» 일이 없다.
//
// 다만 세 가지는 이 파일이 복사해서 쓴다. 도감(`unit_catalog.dart`)과
// 필드(`field_layout.dart`)가 Flutter 에 의존해 순수 Dart 스크립트에서
// 불러올 수 없기 때문이다.
//   1. 등급별 유닛 종류 수 [kTypesPerRarity]
//   2. 슬롯 수 [kSlots]
//   3. 자동 판매 대상 고르는 규칙 [_autoSellIndex] — pickAutoSellIndex 의 사본
// 1·2 는 테스트(«시뮬레이터가 복사해 쓰는 상수가 실제 게임과 맞는다»)가
// 어긋나지 않도록 지켜 준다.

import 'dart:io';
import 'dart:math' as math;

import 'package:ddai_lucky_defense/game/data/balance.dart';

/// 등급별 유닛 종류 수(노말 ~ 초월).
const List<int> kTypesPerRarity = [4, 4, 4, 4, 4, 3, 1];

/// 배치 가능한 슬롯 수.
const int kSlots = 21;

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
    this.endless = true,
    this.enemyHp,
    this.summonCost,
    this.damage,
    this.goldScale = 1.0,
    this.slots = kSlots,
    this.lives = Balance.startLives,
    this.waveInterval = Balance.waveInterval,
    this.bossHpMultiplier = Balance.bossHpMultiplier,
    this.startLuck = 0,
    this.mergeAnyOfRarity = false,
  });

  final String label;
  final double coverage;

  /// 무한 모드인지. 체력 곡선이 모드마다 다르다.
  final bool endless;

  /// 웨이브마다 들어온 골드 중 강화에 쓰는 비율.
  final double upgradeShare;

  final double Function(int wave)? enemyHp;
  final int Function(int unitCount)? summonCost;
  final List<double>? damage;
  final double goldScale;
  final int slots;
  final int lives;
  final double waveInterval;
  final double bossHpMultiplier;
  final int startLuck;

  /// 참이면 «같은 등급 아무 3개» 로 합성한다(현재 규칙은 같은 유닛 3개).
  final bool mergeAnyOfRarity;

  double hpAt(int wave) =>
      enemyHp?.call(wave) ?? Balance.enemyHp(wave, endless: endless);
  int costAt(int units) => summonCost?.call(units) ?? Balance.summonCost(units);
  List<double> get damageTable => damage ?? Balance.damage;

  SimConfig copyWith({String? label, double? coverage, bool? endless}) =>
      SimConfig(
        label: label ?? this.label,
        coverage: coverage ?? this.coverage,
        upgradeShare: upgradeShare,
        endless: endless ?? this.endless,
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
  RunResult(this.endedAt, this.waves);
  final int endedAt;
  final List<WaveSnapshot> waves;
}

/// 한 판을 끝까지 돌린다. 라이프가 0이 된 웨이브를 돌려준다.
RunResult runOnce(int seed, SimConfig c, {int maxWave = 80}) {
  final rng = math.Random(seed);
  final units = <Unit>[];
  final waves = <WaveSnapshot>[];
  var gold = Balance.startGold;
  var gems = Balance.startGems;
  var lives = c.lives;
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
      _autoMerge(units, rng, anyOfRarity: c.mergeAnyOfRarity);
      summons++;
    }

    while (luck < Balance.luckMaxLevel && gems >= Balance.luckCost(luck)) {
      gems -= Balance.luckCost(luck);
      luck++;
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
        return RunResult(w, waves);
      }
    }
  }
  return RunResult(maxWave, waves);
}

double _dps(List<Unit> units, SimConfig c, int atk, int spd) {
  final table = c.damageTable;
  var base = 0.0;
  for (final u in units) {
    base += table[u.$1] * Balance.attackSpeed[u.$1];
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

void _autoMerge(
  List<Unit> units,
  math.Random rng, {
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
    var removed = 0;
    units.removeWhere((u) {
      if (removed >= Balance.mergeCount) {
        return false;
      }
      final match = anyOfRarity ? u.$1 == rarity : u == hit;
      if (match) {
        removed++;
      }
      return match;
    });
    units.add((rarity + 1, rng.nextInt(kTypesPerRarity[rarity + 1])));
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

double _medianEnd(SimConfig c) {
  final ends = [for (var s = 0; s < _seeds; s++) runOnce(s, c).endedAt]..sort();
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
  const skilled = SimConfig();
  final casual = skilled.copyWith(coverage: kCasualCoverage);
  final clearSkilled = skilled.copyWith(endless: false);
  final clearCasual = casual.copyWith(endless: false);

  stdout.writeln('운빨 디펜스 밸런스 리포트');
  stdout.writeln('─' * 58);
  for (final endless in [true, false]) {
    double hp(int w) => Balance.enemyHp(w, endless: endless);
    stdout.writeln(
      '${endless ? '무한  ' : '클리어'} 체력  '
      '1웨 ${_num(hp(1))} · 30웨 ${_num(hp(30))} · '
      '60웨 ${_num(hp(60))} · 100웨 ${_num(hp(100))}  '
      '(×${(hp(11) / hp(10)).toStringAsFixed(3)}/웨이브)',
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
  stdout.writeln(
    '무한 모드 생존 웨이브 ($_seeds판 중앙값)   '
    '숙련자 ${_medianEnd(skilled).toStringAsFixed(0)} · '
    '라이트 ${_medianEnd(casual).toStringAsFixed(0)}',
  );
  stdout.writeln('');
  stdout.writeln(
    '클리어 모드 ${Balance.clearWave}웨이브 도달률   '
    '숙련자 ${_clearRate(clearSkilled).toStringAsFixed(0)}% · '
    '라이트 ${_clearRate(clearCasual).toStringAsFixed(0)}%',
  );
}

/// 클리어 모드에서 마지막 웨이브까지 간 판의 비율.
double _clearRate(SimConfig c) {
  var cleared = 0;
  for (var s = 0; s < _seeds; s++) {
    if (runOnce(s, c, maxWave: Balance.clearWave).endedAt >=
        Balance.clearWave) {
      cleared++;
    }
  }
  return cleared / _seeds * 100;
}

void _curve() {
  const skilled = SimConfig();
  final byWave = <int, List<double>>{};
  for (var s = 0; s < _seeds; s++) {
    for (final snap in runOnce(s, skilled).waves) {
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
          Balance.enemyHp(1, endless: true) *
          math
              .pow(
                (Balance.enemyHp(11, endless: true) /
                        Balance.enemyHp(10, endless: true)) -
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
    SimConfig(label: '소환 비용 계수 4', summonCost: (n) => 20 + 4 * n),
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
  if (args.contains('--levers')) {
    _levers();
  } else if (args.contains('--curve')) {
    _curve();
  } else {
    _report();
  }
}
