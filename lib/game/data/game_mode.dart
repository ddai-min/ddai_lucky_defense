/// 플레이 방식. 인트로에서 고른다.
///
/// 쉬움·보통·무한은 몬스터 체력 곡선 하나로만 갈린다([Balance.enemyHp]).
/// 어려움만 규칙이 하나 더 다르다 — 초월 합성이 도박이다([Balance.mergeChance]).
enum GameMode {
  easy('쉬움', '🌱', '100 웨이브 · 무난하게'),
  normal('보통', '🔥', '100 웨이브 · 팽팽하게'),
  hard('어려움', '🎲', '100 웨이브 · 운이 좋아야'),
  endless('무한', '♾️', '끝없이 · 얼마나 멀리');

  const GameMode(this.label, this.icon, this.description);

  /// 버튼에 쓰는 짧은 이름.
  final String label;
  final String icon;

  /// 버튼 아래 한 줄 설명.
  final String description;

  /// 끝이 없는 모드인지. 나머지는 [Balance.clearWave] 에서 끝난다.
  bool get isEndless => this == GameMode.endless;
}
