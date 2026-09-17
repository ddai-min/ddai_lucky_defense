import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'balance.dart';
import 'rarity.dart';

/// 유닛 공격 방식.
enum AttackStyle {
  single('단일', Color(0xFFE8ECF4)),
  splash('광역', Color(0xFFFF9A4D)),
  slow('둔화', Color(0xFF7FD8FF)),
  poison('중독', Color(0xFF8BE36B)),
  chain('연쇄', Color(0xFFFFE066)),
  execute('처형', Color(0xFFFF6B8A)),
  greed('약탈', Color(0xFFFFD34E));

  const AttackStyle(this.label, this.color);
  final String label;
  final Color color;
}

/// 둔화/중독 지속 시간(초).
const double kSlowDuration = 1.8;
const double kPoisonDuration = 3.0;

@immutable
class UnitSpec {
  const UnitSpec(
    this.id,
    this.name,
    this.emoji,
    this.rarity,
    this.style, {
    this.dmg = 1.0,
    this.spd = 1.0,
    this.rng = 1.0,
    this.param = 0,
  });

  final String id;
  final String name;
  final String emoji;
  final Rarity rarity;
  final AttackStyle style;

  /// 등급 기본치 대비 배율.
  final double dmg;
  final double spd;
  final double rng;

  /// 공격 방식별 부가 수치.
  /// splash=폭발 반경(밴드 배수), slow=감속률, poison=초당 추가 피해율,
  /// chain=추가 대상 수, execute=즉사 확률, greed=추가 골드 확률.
  final double param;

  double get damage => Balance.damage[rarity.index] * dmg;
  double get attacksPerSecond => Balance.attackSpeed[rarity.index] * spd;
  double get rangeFactor => Balance.rangeFactor[rarity.index] * rng;
  int get sellPrice => Balance.sellPrice[rarity.index];
  double get dps => damage * attacksPerSecond;

  String get skillText {
    switch (style) {
      case AttackStyle.single:
        return '단일 대상에게 강한 피해';
      case AttackStyle.splash:
        return '착탄 지점 주변에 광역 피해';
      case AttackStyle.slow:
        return '적중 시 ${(param * 100).round()}% 둔화 '
            '(${kSlowDuration.toStringAsFixed(1)}초)';
      case AttackStyle.poison:
        return '초당 ${(param * 100).round()}% 중독 피해 '
            '(${kPoisonDuration.toStringAsFixed(0)}초)';
      case AttackStyle.chain:
        return '최대 ${param.toInt()}명에게 연쇄 전이';
      case AttackStyle.execute:
        return '${(param * 100).toStringAsFixed(0)}% 확률로 즉사 (보스 제외)';
      case AttackStyle.greed:
        return '${(param * 100).round()}% 확률로 골드 추가 획득';
    }
  }
}

/// 전체 유닛 도감.
const List<UnitSpec> kUnitCatalog = <UnitSpec>[
  // ── 노말 ──────────────────────────────────────────────
  UnitSpec(
    'slime',
    '슬라임',
    '🫧',
    Rarity.normal,
    AttackStyle.single,
    dmg: 1.00,
    spd: 1.12,
  ),
  UnitSpec(
    'mushroom',
    '버섯돌이',
    '🍄',
    Rarity.normal,
    AttackStyle.splash,
    dmg: 0.85,
    spd: 0.90,
    param: 0.50,
  ),
  UnitSpec(
    'snail',
    '달팽이',
    '🐌',
    Rarity.normal,
    AttackStyle.slow,
    dmg: 0.70,
    spd: 0.88,
    rng: 1.05,
    param: 0.18,
  ),
  UnitSpec(
    'piglet',
    '아기돼지',
    '🐷',
    Rarity.normal,
    AttackStyle.greed,
    dmg: 0.80,
    param: 0.14,
  ),

  // ── 레어 ──────────────────────────────────────────────
  UnitSpec(
    'golem',
    '돌골렘',
    '🪨',
    Rarity.rare,
    AttackStyle.splash,
    dmg: 1.05,
    spd: 0.85,
    param: 0.62,
  ),
  UnitSpec(
    'foxfire',
    '불여우',
    '🦊',
    Rarity.rare,
    AttackStyle.poison,
    dmg: 0.90,
    spd: 1.05,
    param: 0.50,
  ),
  UnitSpec(
    'icerabbit',
    '얼음토끼',
    '🐰',
    Rarity.rare,
    AttackStyle.slow,
    dmg: 0.80,
    rng: 1.06,
    param: 0.26,
  ),
  UnitSpec(
    'treant',
    '나무정령',
    '🌳',
    Rarity.rare,
    AttackStyle.single,
    dmg: 1.38,
    spd: 0.80,
  ),

  // ── 유니크 ────────────────────────────────────────────
  UnitSpec(
    'skeleton',
    '해골검사',
    '💀',
    Rarity.unique,
    AttackStyle.single,
    dmg: 1.28,
    spd: 1.10,
    rng: 0.95,
  ),
  UnitSpec(
    'werewolf',
    '늑대인간',
    '🐺',
    Rarity.unique,
    AttackStyle.chain,
    dmg: 0.95,
    param: 3,
  ),
  UnitSpec(
    'darkmage',
    '암흑마법사',
    '🔮',
    Rarity.unique,
    AttackStyle.splash,
    dmg: 1.10,
    spd: 0.85,
    rng: 1.14,
    param: 0.72,
  ),
  UnitSpec(
    'spider',
    '독거미',
    '🕷️',
    Rarity.unique,
    AttackStyle.poison,
    dmg: 0.95,
    spd: 1.15,
    param: 0.70,
  ),

  // ── 에픽 ──────────────────────────────────────────────
  UnitSpec(
    'firegiant',
    '화염거인',
    '🔥',
    Rarity.epic,
    AttackStyle.splash,
    dmg: 1.20,
    spd: 0.90,
    param: 0.85,
  ),
  UnitSpec(
    'frostwitch',
    '서리마녀',
    '❄️',
    Rarity.epic,
    AttackStyle.slow,
    dmg: 1.05,
    rng: 1.16,
    param: 0.38,
  ),
  UnitSpec(
    'thunderbird',
    '천둥독수리',
    '🦅',
    Rarity.epic,
    AttackStyle.chain,
    dmg: 1.05,
    spd: 1.10,
    rng: 1.08,
    param: 5,
  ),
  UnitSpec(
    'assassin',
    '그림자암살자',
    '🥷',
    Rarity.epic,
    AttackStyle.execute,
    dmg: 1.15,
    spd: 1.25,
    rng: 0.95,
    param: 0.06,
  ),

  // ── 레전더리 ──────────────────────────────────────────
  UnitSpec(
    'dragonknight',
    '용기사',
    '🐉',
    Rarity.legendary,
    AttackStyle.splash,
    dmg: 1.25,
    param: 0.95,
  ),
  UnitSpec(
    'archmage',
    '대마법사',
    '🧙',
    Rarity.legendary,
    AttackStyle.chain,
    dmg: 1.15,
    spd: 1.05,
    rng: 1.18,
    param: 7,
  ),
  UnitSpec(
    'paladin',
    '성기사',
    '🛡️',
    Rarity.legendary,
    AttackStyle.single,
    dmg: 1.95,
    spd: 0.95,
  ),
  UnitSpec(
    'stormlord',
    '폭풍군주',
    '🌪️',
    Rarity.legendary,
    AttackStyle.splash,
    dmg: 1.05,
    spd: 1.30,
    rng: 1.08,
    param: 1.05,
  ),

  // ── 신화 ──────────────────────────────────────────────
  UnitSpec(
    'ancientdragon',
    '고대용',
    '🐲',
    Rarity.mythic,
    AttackStyle.splash,
    dmg: 1.30,
    rng: 1.08,
    param: 1.25,
  ),
  UnitSpec(
    'abysslord',
    '심연의군주',
    '👹',
    Rarity.mythic,
    AttackStyle.execute,
    dmg: 1.45,
    param: 0.12,
  ),
  UnitSpec(
    'lightguardian',
    '빛의수호자',
    '✨',
    Rarity.mythic,
    AttackStyle.chain,
    dmg: 1.20,
    spd: 1.10,
    rng: 1.22,
    param: 10,
  ),

  // ── 초월 ──────────────────────────────────────────────
  UnitSpec(
    'creator',
    '창세의신',
    '🌟',
    Rarity.transcendent,
    AttackStyle.splash,
    dmg: 1.60,
    spd: 1.20,
    rng: 1.25,
    param: 1.70,
  ),
];

/// 등급별로 미리 묶어둔 도감.
final Map<Rarity, List<UnitSpec>> kUnitsByRarity = {
  for (final r in Rarity.values)
    r: kUnitCatalog.where((u) => u.rarity == r).toList(growable: false),
};

final Map<String, UnitSpec> kUnitById = {for (final u in kUnitCatalog) u.id: u};

/// 가중치 기반 등급 추첨 후 해당 등급에서 무작위 유닛을 뽑는다.
UnitSpec rollSummon(math.Random rng, int luckLevel) {
  final weights = Balance.summonWeights(luckLevel);
  final total = weights.fold<double>(0, (a, b) => a + b);
  var pick = rng.nextDouble() * total;
  var index = 0;
  for (var i = 0; i < weights.length; i++) {
    if (pick < weights[i]) {
      index = i;
      break;
    }
    pick -= weights[i];
  }
  return randomOfRarity(rng, Rarity.values[index]);
}

/// 유니크 이상 확정 소환(다이아 소환).
UnitSpec rollHighSummon(math.Random rng, int luckLevel) {
  final weights = Balance.summonWeights(luckLevel).sublist(2);
  final total = weights.fold<double>(0, (a, b) => a + b);
  var pick = rng.nextDouble() * total;
  var index = 0;
  for (var i = 0; i < weights.length; i++) {
    if (pick < weights[i]) {
      index = i;
      break;
    }
    pick -= weights[i];
  }
  return randomOfRarity(rng, Rarity.values[index + 2]);
}

UnitSpec randomOfRarity(math.Random rng, Rarity rarity) {
  final pool = kUnitsByRarity[rarity]!;
  return pool[rng.nextInt(pool.length)];
}

/// 자리가 없을 때 자동으로 팔아 치울 유닛의 인덱스. 후보가 없으면 -1.
///
/// 고르는 순서는 이렇다.
/// 1. 등급이 가장 낮은 것.
/// 2. 그중 **팔아도 합성 횟수가 줄지 않는 것**. 3개 맞춰 둔 세트에서 하나를
///    빼면 합성 한 번이 통째로 사라지므로, 어중간하게 남은 쪽을 먼저 판다.
/// 3. 그래도 여럿이면 보유 수가 적은 것.
///
/// 순수 함수라 게임 상태 없이 그대로 검증할 수 있다.
int pickAutoSellIndex(List<UnitSpec> specs) {
  if (specs.isEmpty) {
    return -1;
  }

  final counts = <String, int>{};
  var lowest = Rarity.values.length;
  for (final spec in specs) {
    counts.update(spec.id, (v) => v + 1, ifAbsent: () => 1);
    if (spec.rarity.index < lowest) {
      lowest = spec.rarity.index;
    }
  }

  var best = -1;
  var bestBreaksMerge = true;
  var bestCount = 1 << 30;

  for (var i = 0; i < specs.length; i++) {
    final spec = specs[i];
    if (spec.rarity.index != lowest) {
      continue;
    }
    final count = counts[spec.id]!;
    // 보유 수가 3의 배수인 무리에서 하나를 빼면 합성 한 번을 잃는다.
    final breaksMerge =
        spec.rarity.next != null && count % Balance.mergeCount == 0;

    final better =
        best == -1 ||
        (bestBreaksMerge && !breaksMerge) ||
        (bestBreaksMerge == breaksMerge && count < bestCount);
    if (better) {
      best = i;
      bestBreaksMerge = breaksMerge;
      bestCount = count;
    }
  }
  return best;
}
