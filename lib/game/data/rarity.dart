import 'package:flutter/material.dart';

/// 유닛 등급. 낮은 인덱스일수록 흔하고, 합성으로 다음 등급이 된다.
enum Rarity {
  normal('노말', Color(0xFF9BA6B8), Color(0xFF2B3040)),
  rare('레어', Color(0xFF52A8FF), Color(0xFF13293F)),
  unique('유니크', Color(0xFFB57BFF), Color(0xFF2B1A47)),
  epic('에픽', Color(0xFFFF8A3D), Color(0xFF412012)),
  legendary('레전더리', Color(0xFFFFD34E), Color(0xFF423110)),
  mythic('신화', Color(0xFFFF4F79), Color(0xFF45101F)),
  transcendent('초월', Color(0xFF5BF5D6), Color(0xFF0B3B35));

  const Rarity(this.label, this.color, this.deep);

  /// 한글 표기명.
  final String label;

  /// 테두리/강조에 쓰는 대표색.
  final Color color;

  /// 배경 채움에 쓰는 어두운 색.
  final Color deep;

  int get tier => index;

  /// 합성으로 승급했을 때의 등급. 최고 등급이면 null.
  Rarity? get next =>
      index + 1 < Rarity.values.length ? Rarity.values[index + 1] : null;

  /// 소환으로 직접 뽑을 수 있는 등급인지 여부(신화 이상은 합성 전용).
  bool get summonable => index <= Rarity.legendary.index;

  Color get glow => color.withValues(alpha: 0.55);
}
