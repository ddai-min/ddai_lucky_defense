import 'package:flutter/material.dart';

@immutable
class EnemyKind {
  const EnemyKind(this.name, this.emoji, this.color);
  final String name;
  final String emoji;
  final Color color;
}

/// 일반 몬스터. 2웨이브마다 종류가 바뀐다.
const List<EnemyKind> kMobs = <EnemyKind>[
  EnemyKind('고블린', '👺', Color(0xFF5FAE55)),
  EnemyKind('박쥐', '🦇', Color(0xFF6E5AA8)),
  EnemyKind('좀비', '🧟', Color(0xFF7E9B4C)),
  EnemyKind('해골병', '☠️', Color(0xFFB9C2D0)),
  EnemyKind('유령', '👻', Color(0xFF79C7D8)),
  EnemyKind('임프', '😈', Color(0xFFC1568F)),
  EnemyKind('늑대', '🐗', Color(0xFFA9773F)),
  EnemyKind('거미떼', '🕸️', Color(0xFF9AA4B2)),
  EnemyKind('화염정령', '🔥', Color(0xFFE07A3A)),
  EnemyKind('빙결정령', '🧊', Color(0xFF5FB8E8)),
];

/// 10웨이브마다 등장하는 보스.
const List<EnemyKind> kBosses = <EnemyKind>[
  EnemyKind('탐욕의 거석', '🗿', Color(0xFFB08B5A)),
  EnemyKind('심해의 군주', '🐙', Color(0xFF6F5BD8)),
  EnemyKind('폭군 드레이크', '🦖', Color(0xFF4FB06A)),
  EnemyKind('망각의 마왕', '👿', Color(0xFFD9484F)),
  EnemyKind('종말의 화신', '☄️', Color(0xFFFF9838)),
  EnemyKind('공허의 지배자', '🌑', Color(0xFF8C7BE8)),
];

EnemyKind mobForWave(int wave) => kMobs[((wave - 1) ~/ 2) % kMobs.length];

EnemyKind bossForWave(int wave) =>
    kBosses[((wave ~/ 10) - 1).clamp(0, 1 << 30) % kBosses.length];
