/// 플레이 방식. 인트로에서 고른다.
///
/// 쉬움·보통·무한은 몬스터 체력 곡선 하나로만 갈린다([Balance.enemyHp]).
/// 어려움·지옥은 규칙이 하나 더 다르다 — 초월 합성이 도박이다([hasGamble]).
enum GameMode {
  easy('쉬움', '🌱', '무난하게'),
  normal('보통', '🔥', '팽팽하게'),
  hard('어려움', '🎲', '운이 좋아야'),
  hell('지옥', '😈', '시험해 보십시오'),
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

  /// 초월 합성이 도박인 모드인지([Balance.mergeChance]).
  ///
  /// 어려움·지옥만 그렇다. 이 규칙이 붙으면 초월이 받는 피해 보정도 같이
  /// 따라온다([Balance.rarityDamageBonus]) — 보정이 없으면 «걸지 않는 쪽» 이
  /// 최적이 되어 규칙이 함정이 된다.
  bool get hasGamble => this == GameMode.hard || this == GameMode.hell;

  /// 다이아로 라이프를 살 수 있는 모드인지.
  ///
  /// 지옥만 못 산다. 라이프가 하나뿐인 모드에서 살 수 있게 두면 «한 번도 못
  /// 흘린다» 는 규칙이 다이아로 지워진다.
  bool get canBuyLife => this != GameMode.hell;

  bool get hasFinale => this == GameMode.hell;

  /// 마지막 보스를 «잡아야» 클리어인지.
  ///
  /// 어려움·지옥만 그렇다. 이 규칙이 없으면 마지막 보스를 성까지 흘려보내도
  /// 라이프만 남아 있으면 클리어가 된다 — 보스를 못 잡고 이기는 셈이다.
  bool get mustKillFinalBoss => this == GameMode.hard || this == GameMode.hell;

  /// 랭킹을 매기는 모드인지.
  ///
  /// 쉬움·보통은 빠져 있다 — 쉬움은 거의 모두가 100웨이브를 채워 줄이 서지
  /// 않고, 보통은 «깼나 못 깼나» 라 순위가 의미가 없다. 어려움·지옥·무한만
  /// 사람마다 결과가 벌어진다.
  ///
  /// 여기에 모드를 더할 때는 `firebase/firestore.rules` 에 컬렉션 규칙을 같이
  /// 올려야 한다. 규칙 없이 화면만 켜면 등록이 조용히 거절돼 더 나쁘다.
  bool get hasRanking =>
      this == GameMode.hard ||
      this == GameMode.hell ||
      this == GameMode.endless;
}
