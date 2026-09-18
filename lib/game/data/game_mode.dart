/// 플레이 방식. 인트로에서 고른다.
///
/// 쉬움·보통·무한은 몬스터 체력 곡선 하나로만 갈린다([Balance.enemyHp]).
/// 어려움만 규칙이 하나 더 다르다 — 초월 합성이 도박이다([Balance.mergeChance]).
enum GameMode {
  easy('쉬움', '🌱', '무난하게'),
  normal('보통', '🔥', '팽팽하게'),
  hard('어려움', '🎲', '운이 좋아야'),
  endless('무한', '♾️', '얼마나 멀리');

  const GameMode(this.label, this.icon, this.tagline);

  /// 버튼에 쓰는 짧은 이름.
  final String label;
  final String icon;

  /// 버튼 아래 한 줄 설명의 뒷부분.
  ///
  /// 앞부분(«150 웨이브 ·»)은 [Balance.clearWave] 로 만든다 — 모드마다 끝나는
  /// 웨이브가 다르고, 여기에 숫자를 적어 두면 밸런스를 고칠 때 따로 놀게 된다.
  final String tagline;

  /// 끝이 없는 모드인지. 나머지는 [Balance.clearWave] 에서 끝난다.
  bool get isEndless => this == GameMode.endless;

  /// 랭킹을 매기는 모드인지.
  ///
  /// 쉬움·보통은 빠져 있다 — 쉬움은 거의 모두가 100웨이브를 채워 줄이 서지
  /// 않고, 보통은 «깼나 못 깼나» 라 순위가 의미가 없다. 어려움과 무한만
  /// 사람마다 결과가 벌어진다.
  bool get hasRanking => this == GameMode.hard || this == GameMode.endless;
}
