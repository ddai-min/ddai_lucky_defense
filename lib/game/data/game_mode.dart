/// 플레이 방식. 인트로에서 고른다.
///
/// 난이도 차이는 몬스터 체력 곡선 하나로만 낸다([Balance.enemyHp]).
enum GameMode {
  easy('쉬움', '🌱', '100 웨이브 · 무난하게'),
  normal('보통', '🔥', '100 웨이브 · 팽팽하게'),
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
