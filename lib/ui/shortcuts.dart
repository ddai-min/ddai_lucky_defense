import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 웹·데스크톱에서 쓰는 조작 단축키.
///
/// 화면에 띄우는 힌트와 실제로 도는 동작이 **모두 이 목록에서 나온다.** 키를
/// 하나 더 만들면 처리하는 쪽(`_GameScreenState._handleKey`)의 switch 가
/// 컴파일 에러로 막히므로, 힌트만 있고 동작이 없는 키는 생길 수 없다.
enum GameKey {
  summon('D', LogicalKeyboardKey.keyD),
  highSummon('F', LogicalKeyboardKey.keyF),
  attack('Q', LogicalKeyboardKey.keyQ),
  attackSpeed('W', LogicalKeyboardKey.keyW),
  goldGain('E', LogicalKeyboardKey.keyE),
  luck('R', LogicalKeyboardKey.keyR),
  life('T', LogicalKeyboardKey.keyT);

  const GameKey(this.hint, this.key);

  /// 버튼에 띄우는 글자.
  final String hint;

  final LogicalKeyboardKey key;

  /// 눌린 키에 묶인 조작. 없으면 null.
  static GameKey? of(LogicalKeyboardKey pressed) {
    for (final shortcut in values) {
      if (shortcut.key == pressed) {
        return shortcut;
      }
    }
    return null;
  }
}

/// 물리 키보드가 있다고 볼 수 있는 환경인지. 힌트를 띄울지 가른다.
///
/// 웹에서도 [defaultTargetPlatform] 은 브라우저가 도는 OS 를 알려주므로,
/// 데스크톱 브라우저에서는 참이고 폰 브라우저에서는 거짓이 된다. 키보드가 없는
/// 기기에 «[D]» 를 띄워 봐야 자리만 차지한다.
///
/// 힌트만 가릴 뿐 단축키 자체는 어디서나 동작한다 — 폰에 블루투스 키보드를
/// 붙여 쓰는 경우까지 막을 이유는 없다.
bool get hasPhysicalKeyboard =>
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.windows ||
    defaultTargetPlatform == TargetPlatform.linux;
