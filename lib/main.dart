import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game/game_state.dart';
import 'game/lucky_defense_game.dart';
import 'ui/control_panel.dart';
import 'ui/game_over_overlay.dart';
import 'ui/hud_bar.dart';
import 'ui/intro_overlay.dart';
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
  const LuckyDefenseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '운빨 디펜스',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: GameColors.bg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: GameColors.accent,
          brightness: Brightness.dark,
        ),
      ),
      home: const GameScreen(),
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
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    state.dispose();
    super.dispose();
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
                                ],
                              ),
                            ),
                            ControlPanel(game: game),
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
                              if (state.isGameOver) {
                                return GameOverOverlay(game: game);
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
