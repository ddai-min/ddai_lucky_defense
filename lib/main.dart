import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game/game_state.dart';
import 'game/lucky_defense_game.dart';
import 'ui/control_panel.dart';
import 'ui/result_overlay.dart';
import 'ui/hud_bar.dart';
import 'ui/intro_overlay.dart';
import 'ui/shortcuts.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const LuckyDefenseApp());
}

class LuckyDefenseApp extends StatelessWidget {
  const LuckyDefenseApp({super.key, this.gameFactory});

  /// 테스트에서 시드 고정된 게임을 주입하기 위한 훅.
  final LuckyDefenseGame Function()? gameFactory;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '운빨 디펜스',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const AppScrollBehavior(),
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: GameColors.bg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: GameColors.accent,
          brightness: Brightness.dark,
        ),
      ),
      home: GameScreen(gameFactory: gameFactory),
    );
  }
}

/// 세로 화면 게임이므로 넓은 화면에서는 이 너비로 가운데 세운다.
const double _maxAppWidth = 480;

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, this.gameFactory});

  /// 테스트에서 시드 고정된 게임을 주입하기 위한 훅.
  final LuckyDefenseGame Function()? gameFactory;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late final LuckyDefenseGame game =
      widget.gameFactory?.call() ?? LuckyDefenseGame(state: GameState());

  /// 죽지 않고 앱을 닫아도 진행도가 기록으로 남도록 한다.
  AppLifecycleListener? _lifecycle;

  GameState get state => game.state;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onPause: game.submitRecord,
      onDetach: game.submitRecord,
    );
    // 포커스 트리를 타지 않고 직접 받는다. 게임 화면에는 글자를 넣는 칸이
    // 없으므로 키를 가로챌 다른 위젯이 없고, Flame 의 GameWidget 이 포커스를
    // 가져가도 단축키가 죽지 않는다.
    HardwareKeyboard.instance.addHandler(_handleKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKey);
    _lifecycle?.dispose();
    state.dispose();
    super.dispose();
  }

  /// 조작 패널 버튼과 같은 동작을 키보드로 부른다([GameKey]).
  ///
  /// 누를 때 한 번만 반응한다 — 꾹 누르고 있으면 골드가 순식간에 빠져나가므로
  /// 자동 반복([KeyRepeatEvent])은 받지 않는다.
  bool _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) {
      return false;
    }
    // 인트로·결과 화면과 일시정지 중에는 조작 패널이 잠기므로 키도 같이 잠근다.
    if (!state.started || state.isFinished || state.paused) {
      return false;
    }
    final shortcut = GameKey.of(event.logicalKey);
    if (shortcut == null) {
      return false;
    }
    switch (shortcut) {
      case GameKey.summon:
        game.summon();
      case GameKey.highSummon:
        game.highSummon();
      case GameKey.attack:
        game.upgradeAttack();
      case GameKey.attackSpeed:
        game.upgradeSpeed();
      case GameKey.goldGain:
        game.upgradeGold();
      case GameKey.luck:
        game.upgradeLuck();
      case GameKey.life:
        game.buyLife();
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GameColors.bg,
      body: SafeArea(
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.1,
          // 세로 화면 기준으로 만든 게임이라, 넓은 화면(웹·태블릿)에서는
          // 폰 너비로 가운데 세워 둔다. 그대로 늘리면 필드가 납작해지고
          // 버튼만 길어진다.
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _maxAppWidth),
              child: SizedBox.expand(
                child: LayoutBuilder(
                  builder: (context, constraints) => DecoratedBox(
                    decoration: BoxDecoration(
                      border: constraints.maxWidth >= _maxAppWidth
                          ? const Border.symmetric(
                              vertical: BorderSide(color: GameColors.border),
                            )
                          : null,
                    ),
                    child: Stack(
                      children: [
                        Column(
                          children: [
                            HudBar(state: state),
                            Expanded(
                              child: Stack(
                                children: [
                                  GameWidget<LuckyDefenseGame>(game: game),
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    bottom: 10,
                                    child: _Toast(state: state),
                                  ),
                                  Positioned.fill(
                                    child: AnimatedBuilder(
                                      animation: state,
                                      builder: (context, _) => state.paused
                                          ? _PauseOverlay(game: game)
                                          : const SizedBox.shrink(),
                                    ),
                                  ),
                                  Positioned(
                                    right: 12,
                                    bottom: 12,
                                    child: _PauseButton(game: game),
                                  ),
                                ],
                              ),
                            ),
                            // 멈춰 있는 동안에는 조작 패널도 잠근다.
                            AnimatedBuilder(
                              animation: state,
                              builder: (context, child) => IgnorePointer(
                                ignoring: state.paused,
                                child: AnimatedOpacity(
                                  opacity: state.paused ? 0.45 : 1,
                                  duration: const Duration(milliseconds: 160),
                                  child: child,
                                ),
                              ),
                              child: ControlPanel(game: game),
                            ),
                          ],
                        ),
                        // 인트로/결과 화면은 HUD와 조작 패널까지 덮는다.
                        Positioned.fill(
                          child: AnimatedBuilder(
                            animation: state,
                            builder: (context, _) {
                              if (!state.started) {
                                return IntroOverlay(game: game);
                              }
                              if (state.isFinished) {
                                return ResultOverlay(game: game);
                              }
                              return const SizedBox.shrink();
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 게임 화면 우측 하단의 일시정지 버튼.
class _PauseButton extends StatelessWidget {
  const _PauseButton({required this.game});

  final LuckyDefenseGame game;

  @override
  Widget build(BuildContext context) {
    final state = game.state;
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        final paused = state.paused;
        return Semantics(
          button: true,
          label: paused ? '계속하기' : '일시정지',
          child: GestureDetector(
            onTap: game.togglePause,
            child: Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: GameColors.panel.withValues(alpha: 0.92),
                shape: BoxShape.circle,
                border: Border.all(
                  color: paused ? GameColors.green : GameColors.border,
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Icon(
                paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                size: 23,
                color: paused ? GameColors.green : GameColors.text,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 멈춘 동안 게임 화면을 덮는 안내. 아무 데나 누르면 계속된다.
class _PauseOverlay extends StatelessWidget {
  const _PauseOverlay({required this.game});

  final LuckyDefenseGame game;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: game.togglePause,
      behavior: HitTestBehavior.opaque,
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.62),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.pause_circle_filled_rounded,
                size: 52,
                color: GameColors.text,
              ),
              SizedBox(height: 10),
              Text(
                '일시정지',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
              SizedBox(height: 4),
              Text(
                '화면을 누르면 계속합니다',
                style: TextStyle(
                  color: GameColors.sub,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Toast extends StatelessWidget {
  const _Toast({required this.state});

  final GameState state;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        final message = state.toastMessage;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: message == null
              ? const SizedBox.shrink()
              : Center(
                  key: ValueKey(message),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.82),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Color(state.toastColor).withValues(alpha: 0.7),
                      ),
                    ),
                    child: Text(
                      message,
                      style: TextStyle(
                        color: Color(state.toastColor),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }
}
