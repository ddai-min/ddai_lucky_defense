import 'dart:math' as math;

import 'package:ddai_lucky_defense/game/data/balance.dart';
import 'package:ddai_lucky_defense/game/data/rarity.dart';
import 'package:ddai_lucky_defense/game/data/unit_catalog.dart';
import 'package:ddai_lucky_defense/game/field_layout.dart';
import 'package:ddai_lucky_defense/game/components/enemy_component.dart';
import 'package:ddai_lucky_defense/game/components/projectile_component.dart';
import 'package:ddai_lucky_defense/game/game_state.dart';
import 'package:ddai_lucky_defense/game/leaderboard.dart';
import 'package:ddai_lucky_defense/game/lucky_defense_game.dart';
import 'package:ddai_lucky_defense/game/record_store.dart';
import 'package:ddai_lucky_defense/main.dart';
import 'package:ddai_lucky_defense/ui/hud_bar.dart';
import 'package:ddai_lucky_defense/ui/control_panel.dart';
import 'package:ddai_lucky_defense/ui/kill_board.dart';
import 'package:ddai_lucky_defense/ui/shortcuts.dart';
import 'package:flame/components.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 화살표 아이콘을 감싼 가장 가까운 AnimatedOpacity 의 불투명도.
///
/// 조작 패널 전체를 흐리는 AnimatedOpacity 도 조상에 있으므로 첫 번째만 본다.
double _arrowOpacity(WidgetTester tester, IconData icon) {
  return tester
      .widget<AnimatedOpacity>(
        find
            .ancestor(
              of: find.byIcon(icon),
              matching: find.byType(AnimatedOpacity),
            )
            .first,
      )
      .opacity;
}

/// 합성 도박의 결과를 고정한다. [roll] 이 성공 확률보다 작으면 성공이다.
class _FixedRandom implements math.Random {
  _FixedRandom(this.roll);

  final double roll;

  @override
  double nextDouble() => roll;

  @override
  int nextInt(int max) => 0;

  @override
  bool nextBool() => false;
}

/// 실제 화면 구조 그대로, 시드를 고정한 게임을 띄운다.
Future<LuckyDefenseGame> _boot(
  WidgetTester tester, {
  int seed = 42,
  math.Random? random,
  RecordStore? records,
  Leaderboard? leaderboard,
}) async {
  tester.view
    ..physicalSize =
        const Size(1170, 2532) // iPhone 13 Pro
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  late LuckyDefenseGame game;
  await tester.pumpWidget(
    LuckyDefenseApp(
      gameFactory: () {
        game = LuckyDefenseGame(
          state: GameState(),
          random: random ?? math.Random(seed),
          records: records ?? MemoryRecordStore(),
          leaderboard: leaderboard ?? MemoryLeaderboard(isAvailable: false),
        );
        return game;
      },
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return game;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('필드 레이아웃이 만들어지고 인트로가 뜬다', (tester) async {
    final game = await _boot(tester);

    expect(game.layout.slotCount, greaterThan(8));
    expect(game.layout.path.length, greaterThan(100));
    expect(game.state.slotCount, game.layout.slotCount);
    expect(game.state.started, isFalse);
    expect(find.text('시작하기'), findsOneWidget);
    // 인트로가 조작 패널을 덮으므로 소환 버튼은 눌리지 않는다.
    expect(game.units, isEmpty);

    // 인트로 동안에는 웨이브가 진행되지 않는다.
    final before = game.state.waveCountdown;
    for (var i = 0; i < 120; i++) {
      game.update(1 / 60);
    }
    expect(game.state.waveCountdown, before);
    expect(game.state.wave, 0);
  });

  testWidgets('소환하면 유닛이 슬롯에 배치되고 골드가 줄어든다', (tester) async {
    final game = await _boot(tester);
    game.startGame();
    final state = game.state;

    final costFirst = state.summonCost;
    expect(game.summon(), isTrue);
    await tester.pump();

    expect(game.units.length, 1);
    expect(state.unitCount, 1);
    expect(state.gold, Balance.startGold - costFirst);
    // 유닛이 늘면 소환 비용도 오른다.
    expect(state.summonCost, greaterThan(costFirst));
    expect(game.units.first.slotIndex, 0);

    // 골드가 없으면 소환 실패.
    state.gold = 0;
    expect(game.summon(), isFalse);
    expect(game.units.length, 1);
  });

  testWidgets('슬롯이 가득 차면 가장 낮은 등급을 팔고 그 자리에 소환한다', (tester) async {
    final game = await _boot(tester);
    game.startGame();
    final state = game.state;
    state.gold = 1 << 24;

    for (var i = 0; i < game.layout.slotCount; i++) {
      game.summon();
    }
    await tester.pump();
    expect(game.units.length, game.layout.slotCount);
    expect(state.slotsFull, isTrue);
    expect(state.willAutoSell, isTrue);

    // 팔릴 유닛은 보유 중 가장 낮은 등급이다.
    final lowest = game.units.map((u) => u.spec.rarity.index).reduce(math.min);
    expect(state.autoSellRarity!.index, lowest);
    expect(state.autoSellRefund, greaterThan(0));

    // 한 기를 팔면 보유 수가 줄어 소환 비용도 내려간다.
    expect(state.effectiveSummonCost, lessThan(state.summonCost));

    final refund = state.autoSellRefund;
    final cost = state.effectiveSummonCost;
    final goldBefore = state.gold;
    final soldSlot = game
        .units[pickAutoSellIndex(game.units.map((u) => u.spec).toList())]
        .slotIndex;

    expect(state.canSummon, isTrue);
    expect(game.summon(), isTrue);
    await tester.pump();

    // 칸 수는 그대로, 판 자리에 새 유닛이 들어간다.
    expect(game.units.length, game.layout.slotCount);
    expect(game.units.any((u) => u.slotIndex == soldSlot), isTrue);
    expect(state.gold, goldBefore + refund - cost);
    expect(state.totalSummons, game.layout.slotCount + 1);

    // 계속 눌러도 칸 수는 유지된다.
    for (var i = 0; i < 10; i++) {
      game.summon();
    }
    await tester.pump();
    expect(game.units.length, game.layout.slotCount);
  });

  testWidgets('자동 판매를 끄면 자리가 없을 때 소환이 막힌다', (tester) async {
    final game = await _boot(tester);
    game.startGame();
    final state = game.state;
    state.gold = 1 << 24;

    for (var i = 0; i < game.layout.slotCount; i++) {
      game.summon();
    }
    await tester.pump();
    expect(state.willAutoSell, isTrue);

    // 토글을 끈다.
    state.autoSell = false;
    state.notify();
    await tester.pump();

    expect(state.willAutoSell, isFalse);
    expect(state.canSummon, isFalse);
    // 비용도 다시 «안 팔았을 때» 기준으로 돌아온다.
    expect(state.effectiveSummonCost, state.summonCost);

    final before = game.units.length;
    expect(game.summon(), isFalse);
    expect(game.highSummon(), isFalse);
    await tester.pump();
    expect(game.units.length, before);

    // 다시 켜면 동작한다.
    state.autoSell = true;
    state.notify();
    await tester.pump();
    expect(state.canSummon, isTrue);
    expect(game.summon(), isTrue);
    await tester.pump();
    expect(game.units.length, game.layout.slotCount);
  });

  testWidgets('자동 판매 토글이 조작 패널에 있고 합성 버튼은 없다', (tester) async {
    final game = await _boot(tester);
    game.startGame();
    await tester.pump();

    expect(find.text('자동\n판매'), findsOneWidget);
    expect(find.text('자동\n합성'), findsOneWidget);
    // 아무 때나 눌러도 소용없던 전체 합성 버튼은 사라졌다.
    expect(find.text('합성'), findsNothing);
    expect(find.text('3개↑'), findsNothing);

    expect(game.state.autoSell, isTrue);
    await tester.tap(find.text('자동\n판매'));
    await tester.pump();
    expect(game.state.autoSell, isFalse);
  });

  testWidgets('놀고 있을 때는 렌더 루프를 세운다', (tester) async {
    final game = await _boot(tester);

    // 인트로: 그림이 멈춰 있으니 한 프레임 뒤 루프가 선다.
    game.update(1 / 60);
    expect(game.paused, isTrue, reason: '인트로에서는 다시 그릴 게 없다');

    game.startGame();
    await tester.pump();
    expect(game.paused, isFalse, reason: '시작하면 다시 돈다');

    game.togglePause();
    await tester.pump();
    game.update(1 / 60); // 대기 중인 추가·제거를 처리하는 마지막 한 프레임
    expect(game.paused, isTrue);

    game.togglePause();
    await tester.pump();
    expect(game.paused, isFalse);

    // 판이 끝나도 선다.
    game.state
      ..phase = GamePhase.gameOver
      ..notify();
    await tester.pump();
    game.update(1 / 60);
    expect(game.paused, isTrue, reason: '결과 화면에서도 다시 그릴 게 없다');
  });

  testWidgets('멈추기 직전 프레임에 죽은 몬스터는 화면에 남지 않는다', (tester) async {
    final game = await _boot(tester);
    game.startGame();
    for (var i = 0; i < 60 * 12; i++) {
      game.update(1 / 60);
    }
    await tester.pump();
    expect(game.enemies, isNotEmpty);

    // 마지막 프레임에 죽이고 곧바로 멈춘다.
    final victim = game.enemies.first;
    victim.takeDamage(1e9);
    game.togglePause();
    await tester.pump();
    game.update(1 / 60);

    expect(game.paused, isTrue);
    expect(victim.isMounted, isFalse, reason: '제거가 처리된 뒤에 루프가 선다');
  });

  testWidgets('무한 모드에서 죽은 뒤에는 웨이브가 오르지 않는다', (tester) async {
    final game = await _boot(tester);
    game.state.mode = GameMode.endless;
    game.startGame();
    final state = game.state;

    // 유닛 없이 방치해 죽인다.
    for (var i = 0; i < 60 * 400 && !state.isFinished; i++) {
      game.update(1 / 60);
    }
    await tester.pump();
    expect(state.isGameOver, isTrue, reason: '먼저 죽어야 한다');

    final atDeath = state.wave;
    final countdownAtDeath = state.waveCountdown;
    for (var i = 0; i < 60 * 300; i++) {
      game.update(1 / 60);
    }
    await tester.pump();

    // 무한 모드는 끝나는 웨이브가 없으므로, 판이 끝난 뒤에도 카운트다운이
    // 돌면 웨이브가 영원히 올라간다.
    expect(state.wave, atDeath, reason: '결과 화면 뒤에서 웨이브가 올라가면 안 된다');
    expect(state.waveCountdown, countdownAtDeath, reason: '시계도 멈춰 있어야 한다');
    expect(state.phase, GamePhase.gameOver);
  });

  group('지옥 난이도', () {
    test('앞 50웨이브는 어려움과 한 체력도 다르지 않다', () {
      // 초반을 올리면 초월을 보기도 전에 죽어 «아무도 못 깨는 모드» 가 된다.
      for (var w = 1; w <= 50; w++) {
        expect(
          Balance.enemyHp(w, GameMode.hell),
          Balance.enemyHp(w, GameMode.hard),
          reason: '$w 웨이브',
        );
      }
    });

    test('50웨이브 이후에만 어려움보다 가파르다', () {
      for (var w = 51; w <= 150; w++) {
        expect(
          Balance.enemyHp(w, GameMode.hell),
          greaterThan(Balance.enemyHp(w, GameMode.hard)),
          reason: '$w 웨이브',
        );
      }
      // 결승선에서 어려움의 몇 배인지. 이 배수가 «초월 6기 이상» 을 만든다.
      final ratio =
          Balance.enemyHp(150, GameMode.hell) /
          Balance.enemyHp(150, GameMode.hard);
      expect(ratio, greaterThan(7), reason: '지옥 결승선은 어려움의 7배 이상');
    });

    test('어떤 웨이브에서도 어려움보다 약하지 않다', () {
      // 처음엔 «50까지 어려움, 그 뒤 고정 증가율» 로 짰다가 51웨이브에서
      // 지옥이 더 약해졌다 — 어려움의 꺾인 곡선이 그 지점에서 더 가팔라서다.
      for (var w = 1; w <= 400; w++) {
        expect(
          Balance.enemyHp(w, GameMode.hell),
          greaterThanOrEqualTo(Balance.enemyHp(w, GameMode.hard)),
          reason: '$w 웨이브',
        );
      }
    });

    test('결승선은 어려움과 같은 150웨이브다', () {
      expect(Balance.clearWave(GameMode.hell), 150);
    });

    test('초월 도박과 피해 보정이 그대로 붙는다', () {
      expect(GameMode.hell.hasGamble, isTrue);
      expect(
        Balance.mergeChance(Rarity.mythic.index, GameMode.hell),
        Balance.hardMergeChance,
      );
      expect(
        Balance.rarityDamageBonus(Rarity.transcendent.index, GameMode.hell),
        Balance.hardTopTierDamage,
      );
    });

    testWidgets('인트로에서 고를 수 있고 도박 안내가 함께 뜬다', (tester) async {
      final game = await _boot(tester);
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      await tester.ensureVisible(find.text('지옥'));
      await tester.tap(find.text('지옥'));
      await tester.pump();

      expect(game.state.mode, GameMode.hell);
      // 지옥은 규칙을 적지 않고 분위기만 남긴다.
      expect(find.textContaining('주사위는 던져졌습니다'), findsOneWidget);
      expect(
        find.textContaining('도박입니다'),
        findsNothing,
        reason: '어려움 문구가 지옥에 그대로 새어 나오면 안 된다',
      );
    });

    testWidgets('어려움에는 규칙 설명이 그대로 남는다', (tester) async {
      await _boot(tester);
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      await tester.ensureVisible(find.text('어려움'));
      await tester.tap(find.text('어려움'));
      await tester.pump();

      // 도박을 처음 만나는 모드라, 여기서는 수치를 적어 준다.
      expect(find.textContaining('어려움에서는'), findsOneWidget);
      expect(find.textContaining('도박입니다'), findsOneWidget);
      expect(find.textContaining('주사위는 던져졌습니다'), findsNothing);
    });
  });

  group('지옥: 라이프 1', () {
    test('지옥만 시작 라이프가 1이다', () {
      for (final mode in GameMode.values) {
        expect(
          Balance.startLivesOf(mode),
          mode == GameMode.hell ? 1 : Balance.startLives,
          reason: mode.label,
        );
      }
    });

    test('라이프를 살 수 없는 모드는 지옥뿐이다', () {
      expect(
        GameMode.values.where((m) => !m.canBuyLife),
        [GameMode.hell],
      );
    });

    testWidgets('지옥을 고르면 시작 전부터 라이프가 1로 보인다', (tester) async {
      final game = await _boot(tester);
      expect(game.state.lives, Balance.startLives);

      game.setMode(GameMode.hell);
      await tester.pump();
      expect(game.state.lives, 1, reason: '인트로 HUD 가 바로 알려 줘야 한다');

      // startGame 은 reset 을 거치지 않으므로 여기서도 맞춰져야 한다.
      game.startGame();
      await tester.pump();
      expect(game.state.lives, 1);
    });

    testWidgets('다시 시작해도 1로 돌아온다', (tester) async {
      final game = await _boot(tester);
      game.setMode(GameMode.hell);
      game.startGame();
      game.state.lives = 7;

      game.restart();
      await tester.pump();
      expect(game.state.lives, 1);
    });

    testWidgets('지옥에서는 다이아가 넉넉해도 라이프를 못 산다', (tester) async {
      final game = await _boot(tester);
      game.setMode(GameMode.hell);
      game.startGame();
      game.state.gems = 9999;
      await tester.pump();

      expect(game.buyLife(), isFalse);
      expect(game.state.lives, 1);
      expect(game.state.gems, 9999, reason: '다이아도 줄지 않는다');

      // T 를 눌러도 마찬가지다.
      await tester.sendKeyEvent(GameKey.life.key);
      await tester.pump();
      expect(game.state.lives, 1);
    });

    testWidgets('지옥에는 라이프 버튼이 아예 없다', (tester) async {
      final game = await _boot(tester);
      game.startGame();
      game.state.gems = 9999;
      await tester.pump();

      // 강화 목록은 가로로 스크롤된다. 끝까지 밀지 않으면 «없다» 가 그냥
      // «아직 안 보인다» 라서 아무것도 검증하지 못한다.
      Future<void> scrollToEnd() async {
        for (var i = 0; i < 3; i++) {
          await tester.drag(find.byType(ListView), const Offset(-400, 0));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
        }
      }

      await scrollToEnd();
      expect(find.text('라이프'), findsOneWidget, reason: '쉬움에는 있다');

      game.setMode(GameMode.hell);
      await tester.pump();
      await scrollToEnd();
      expect(find.text('라이프'), findsNothing);
      expect(find.text('행운'), findsOneWidget, reason: '나머지는 그대로다');
    });

    testWidgets('어려움에서는 그대로 살 수 있다', (tester) async {
      final game = await _boot(tester);
      game.setMode(GameMode.hard);
      game.startGame();
      game.state.gems = 9999;
      await tester.pump();

      expect(game.buyLife(), isTrue);
      expect(game.state.lives, Balance.startLives + 1);
    });
  });

  group('마지막 보스 격퇴', () {
    /// 마지막 웨이브에 보스 한 기만 살아 있는 판을 만든다.
    ///
    /// 보스를 세우기 **전에** update 를 돌리면 «마지막 웨이브에 남은 적이
    /// 없다» 로 읽혀 그 자리에서 클리어가 나 버린다. 그래서 상태만 맞춰 두고
    /// 보스를 먼저 세운다.
    Future<(LuckyDefenseGame, EnemyComponent)> atFinalBoss(
      WidgetTester tester,
      GameMode mode,
    ) async {
      final game = await _boot(tester);
      game.state.mode = mode;
      game.startGame();
      game.state
        ..wave = Balance.clearWave(mode)!
        ..waveCountdown = 999
        ..lives = 15;
      // 여기서 pump 하면 안 된다 — 프레임이 한 번 돌면서 «마지막 웨이브에 남은
      // 적이 없다» 로 읽혀 그 자리에서 클리어가 난다. 보스를 먼저 세운다.
      return (game, game.spawnFinalBossForTest());
    }

    testWidgets('어려움: 마지막 보스를 놓치면 라이프가 남아도 실패다', (tester) async {
      final (game, boss) = await atFinalBoss(tester, GameMode.hard);
      expect(boss.isBoss, isTrue);

      game.onEnemyReachedBase(boss);
      game.update(1 / 60);
      await tester.pump();

      expect(game.state.lives, greaterThan(0), reason: '라이프는 남아 있다');
      expect(game.state.isCleared, isFalse);
      expect(game.state.isGameOver, isTrue);
      expect(game.state.failedByBossEscape, isTrue);
    });

    testWidgets('어려움: 보스를 잡으면 클리어다', (tester) async {
      final (game, boss) = await atFinalBoss(tester, GameMode.hard);

      game.onEnemyKilled(boss);
      game.update(1 / 60);
      await tester.pump();

      expect(game.state.isCleared, isTrue);
      expect(game.state.failedByBossEscape, isFalse);
    });

    testWidgets('지옥도 같은 규칙이다', (tester) async {
      final (game, boss) = await atFinalBoss(tester, GameMode.hell);
      game.onEnemyReachedBase(boss);
      game.update(1 / 60);
      await tester.pump();

      expect(game.state.isGameOver, isTrue);
      expect(game.state.failedByBossEscape, isTrue);
    });

    // 판 하나에 _boot 를 두 번 부르면 위젯 트리가 재사용돼 게임이 새로
    // 만들어지지 않는다. 모드마다 따로 돌린다.
    for (final mode in [GameMode.easy, GameMode.normal]) {
      testWidgets('${mode.label}은 놓쳐도 라이프가 남으면 클리어다', (tester) async {
        final (game, boss) = await atFinalBoss(tester, mode);
        game.onEnemyReachedBase(boss);
        game.update(1 / 60);
        await tester.pump();

        expect(game.state.isCleared, isTrue);
        expect(game.state.failedByBossEscape, isFalse);
      });
    }

    testWidgets('결과 화면이 «라이프가 남았는데 왜 졌는지» 를 알려 준다', (tester) async {
      final (game, boss) = await atFinalBoss(tester, GameMode.hard);
      game.onEnemyReachedBase(boss);
      game.update(1 / 60);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(find.text('보스 격퇴 실패'), findsOneWidget);
      // 같은 문장을 토스트도 쓰므로 결과 줄만 콕 집는다.
      expect(
        find.text('마지막 보스를 놓쳤습니다 · 라이프 ${game.state.lives} 남음'),
        findsOneWidget,
      );
      expect(game.state.lives, greaterThan(0), reason: '라이프가 남았는데 졌다');
      expect(find.text('방어 실패'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    test('규칙이 붙는 모드는 어려움·지옥뿐이다', () {
      expect(
        GameMode.values.where((m) => m.mustKillFinalBoss),
        [GameMode.hard, GameMode.hell],
      );
    });

    testWidgets('다시 시작하면 놓친 기록이 지워진다', (tester) async {
      final (game, boss) = await atFinalBoss(tester, GameMode.hard);
      game.onEnemyReachedBase(boss);
      game.update(1 / 60);
      await tester.pump();
      expect(game.state.failedByBossEscape, isTrue);

      game.restart();
      await tester.pump();
      expect(game.state.failedByBossEscape, isFalse);

      // 놓친 기억도 지워져야 한다 — 남아 있으면 다음 판이 시작부터 실패다.
      game.state
        ..wave = Balance.clearWave(GameMode.hard)!
        ..waveCountdown = 999;
      game.update(1 / 60);
      await tester.pump();
      expect(game.state.isGameOver, isFalse);
    });
  });

  group('합성 잠금', () {
    testWidgets('잠근 종류는 자동 합성이 건너뛴다', (tester) async {
      final game = await _boot(tester);
      game.startGame();
      final slime = kUnitById['slime']!;
      game.placeUnits(slime, Balance.mergeCount);
      game.state.autoMerge = true;
      game.toggleMergeLock(slime.id);
      await tester.pump();

      for (var i = 0; i < 60; i++) {
        game.update(1 / 60);
      }
      expect(game.unitCounts[slime.id], Balance.mergeCount, reason: '그대로다');
      expect(game.state.totalMerges, 0);

      // 풀면 곧바로 자동으로 합쳐진다.
      game.toggleMergeLock(slime.id);
      await tester.pump();
      game.update(1 / 60);
      expect(game.unitCounts[slime.id] ?? 0, 0);
      expect(game.state.totalMerges, 1);
    });

    testWidgets('잠가도 직접 누르는 합성은 된다', (tester) async {
      final game = await _boot(tester);
      game.startGame();
      final slime = kUnitById['slime']!;
      game.placeUnits(slime, Balance.mergeCount);
      game.toggleMergeLock(slime.id);
      game.focusUnit(game.units.first);
      await tester.pump();

      await tester.sendKeyEvent(GameKey.merge.key);
      await tester.pump();

      expect(game.state.totalMerges, 1, reason: '잠금은 «자동» 합성만 막는다');
      expect(game.units.first.spec.rarity, slime.rarity.next);
    });

    testWidgets('V 로 고른 유닛을 잠그고 푼다', (tester) async {
      final game = await _boot(tester);
      game.startGame();
      final slime = kUnitById['slime']!;
      game.placeUnits(slime, 1);
      game.focusUnit(game.units.first);
      await tester.pump();

      await tester.sendKeyEvent(GameKey.mergeLock.key);
      await tester.pump();
      expect(game.state.mergeLocked, contains(slime.id));

      await tester.sendKeyEvent(GameKey.mergeLock.key);
      await tester.pump();
      expect(game.state.mergeLocked, isEmpty);
    });

    testWidgets('아무것도 안 골랐으면 V 는 아무 일도 안 한다', (tester) async {
      final game = await _boot(tester);
      game.startGame();
      game.placeUnits(kUnitById['slime']!, 1);
      game.clearSelection();
      await tester.pump();

      await tester.sendKeyEvent(GameKey.mergeLock.key);
      await tester.pump();

      expect(game.state.mergeLocked, isEmpty);
    });

    testWidgets('선택 카드의 자물쇠 버튼으로도 걸고 푼다', (tester) async {
      final game = await _boot(tester);
      game.startGame();
      final slime = kUnitById['slime']!;
      game.placeUnits(slime, 1);
      game.focusUnit(game.units.first);
      await tester.pump();

      expect(find.text('🔓'), findsOneWidget);
      await tester.tap(find.text('🔓'));
      await tester.pump();

      expect(game.state.mergeLocked, contains(slime.id));
      expect(find.text('🔒'), findsOneWidget);
      expect(find.text('🔓'), findsNothing);

      await tester.tap(find.text('🔒'));
      await tester.pump();
      expect(game.state.mergeLocked, isEmpty);
    });

    testWidgets('좁은 화면에서도 고른 유닛 이름이 보인다', (tester) async {
      // 버튼이 셋(잠금·합성·판매)이라 320pt 에서는 자리가 빠듯하다. 태그가
      // 밀려나더라도 «무엇을 골랐나» 는 남아야 한다.
      tester.view
        ..physicalSize = const Size(640, 1136) // 320x568
        ..devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      late LuckyDefenseGame game;
      await tester.pumpWidget(
        LuckyDefenseApp(
          gameFactory: () {
            game = LuckyDefenseGame(
              state: GameState(),
              random: math.Random(3),
              records: MemoryRecordStore(),
              leaderboard: MemoryLeaderboard(isAvailable: false),
            );
            return game;
          },
        ),
      );
      await tester.pump();
      game.startGame();
      final spec = kUnitById['slime']!;
      game.placeUnits(spec, 1);
      game.focusUnit(game.units.first);
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('🔓'), findsOneWidget, reason: '잠금 버튼은 남는다');

      // 트리에 있는 것만으로는 부족하다 — 자리를 못 받으면 폭 0 으로 그려진다.
      final name = find.descendant(
        of: find.byType(ControlPanel),
        matching: find.text(spec.name),
      );
      expect(name, findsOneWidget);
      expect(
        tester.getSize(name).width,
        greaterThan(24),
        reason: '이름이 읽을 수 있을 만큼은 나와야 한다',
      );
    });

    testWidgets('다시 시작하면 잠금이 풀린다', (tester) async {
      final game = await _boot(tester);
      game.startGame();
      game.placeUnits(kUnitById['slime']!, 1);
      game.toggleMergeLock('slime');
      expect(game.state.mergeLocked, isNotEmpty);

      game.restart();
      await tester.pump();
      expect(game.state.mergeLocked, isEmpty);
    });
  });

  group('일시정지 화면', () {
    testWidgets('«계속» 은 판을 그대로 이어 간다', (tester) async {
      final game = await _boot(tester);
      game.startGame();
      final state = game.state;
      for (var i = 0; i < 60 * 12; i++) {
        game.update(1 / 60);
      }
      await tester.pump();
      final wave = state.wave;
      final enemies = game.enemies.length;

      game.togglePause();
      await tester.pump();
      await tester.tap(find.text('계속'));
      await tester.pump();

      expect(state.paused, isFalse);
      expect(state.wave, wave, reason: '진행도가 그대로다');
      expect(game.enemies.length, enemies);
    });

    testWidgets('«다시 도전» 은 두 번 눌러야 처음부터 시작한다', (tester) async {
      final game = await _boot(tester);
      game.startGame();
      final state = game.state;
      for (var i = 0; i < 60 * 12; i++) {
        game.update(1 / 60);
      }
      state.gold = 12345;
      await tester.pump();
      expect(state.wave, greaterThan(0));

      game.togglePause();
      await tester.pump();

      // 한 번 눌렀을 때는 확인만 걸린다 — 판은 그대로다.
      await tester.tap(find.text('다시 도전'));
      await tester.pump();
      expect(find.text('정말 다시?'), findsOneWidget);
      expect(find.text('다시 도전'), findsNothing);
      expect(state.wave, greaterThan(0), reason: '아직 안 지운다');
      expect(state.gold, 12345);

      // 두 번째에 실제로 1웨이브부터 다시 시작한다.
      await tester.tap(find.text('정말 다시?'));
      await tester.pump();
      expect(state.wave, 0);
      expect(state.gold, Balance.startGold);
      expect(game.units, isEmpty);
      expect(game.enemies, isEmpty);
      expect(state.paused, isFalse, reason: '다시 시작하면 멈춤도 풀린다');
      expect(state.started, isTrue, reason: '인트로로 돌아가지 않는다');
    });

    testWidgets('계속을 누르면 걸어 둔 확인이 풀린다', (tester) async {
      final game = await _boot(tester);
      game.startGame();
      await tester.pump();

      game.togglePause();
      await tester.pump();
      await tester.tap(find.text('다시 도전'));
      await tester.pump();
      expect(find.text('정말 다시?'), findsOneWidget);

      await tester.tap(find.text('계속'));
      await tester.pump();
      game.togglePause();
      await tester.pump();

      expect(find.text('다시 도전'), findsOneWidget);
      expect(find.text('정말 다시?'), findsNothing);
    });

    testWidgets('낮은 화면에서도 버튼이 넘치지 않는다', (tester) async {
      tester.view
        ..physicalSize = const Size(1600, 840) // 800x420, 필드가 아주 낮다
        ..devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      late LuckyDefenseGame game;
      await tester.pumpWidget(
        LuckyDefenseApp(
          gameFactory: () {
            game = LuckyDefenseGame(
              state: GameState(),
              random: math.Random(1),
              records: MemoryRecordStore(),
              leaderboard: MemoryLeaderboard(isAvailable: false),
            );
            return game;
          },
        ),
      );
      await tester.pump();
      game.startGame();
      game.togglePause();
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('계속'), findsOneWidget);
      expect(find.text('다시 도전'), findsOneWidget);
    });
  });

  testWidgets('일시정지 버튼을 누르면 게임이 멈추고 다시 누르면 이어진다', (tester) async {
    final game = await _boot(tester);
    game.startGame();
    await tester.pump();
    final state = game.state;

    // 첫 웨이브까지 진행시켜 움직이는 것이 있는 상태로 만든다.
    for (var i = 0; i < 60 * 12; i++) {
      game.update(1 / 60);
    }
    await tester.pump();
    expect(game.enemies, isNotEmpty);

    final waveBefore = state.waveCountdown;
    final progressBefore = game.enemies.first.progress;

    await tester.tap(find.byIcon(Icons.pause_rounded));
    await tester.pump();
    expect(state.paused, isTrue);
    expect(find.text('일시정지'), findsOneWidget);

    // 멈춘 동안에는 시간도 몬스터도 움직이지 않는다.
    for (var i = 0; i < 60 * 5; i++) {
      game.update(1 / 60);
    }
    expect(state.waveCountdown, waveBefore);
    expect(game.enemies.first.progress, progressBefore);

    // 다시 누르면 이어진다.
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    expect(state.paused, isFalse);
    expect(find.text('일시정지'), findsNothing);

    for (var i = 0; i < 60; i++) {
      game.update(1 / 60);
    }
    expect(state.waveCountdown, lessThan(waveBefore));
    expect(tester.takeException(), isNull);
  });

  testWidgets('팔아도 골드가 모자라면 자동 판매하지 않는다', (tester) async {
    final game = await _boot(tester);
    game.startGame();
    final state = game.state;
    state.gold = 1 << 24;

    for (var i = 0; i < game.layout.slotCount; i++) {
      game.summon();
    }
    await tester.pump();

    // 판 값을 더해도 비용에 못 미치게 만든다.
    state.gold = 0;
    expect(state.autoSellRefund, lessThan(state.effectiveSummonCost));
    expect(state.canSummon, isFalse);

    final before = game.units.length;
    expect(game.summon(), isFalse);
    await tester.pump();
    // 손해만 보고 끝나면 안 되므로 아무것도 팔리지 않는다.
    expect(game.units.length, before);
    expect(state.gold, 0);
  });

  testWidgets('고급소환도 자리가 없으면 자동 판매 후 소환한다', (tester) async {
    final game = await _boot(tester);
    game.startGame();
    final state = game.state;
    state.gold = 1 << 24;

    for (var i = 0; i < game.layout.slotCount; i++) {
      game.summon();
    }
    await tester.pump();

    state.gems = Balance.highSummonGems;
    expect(state.canHighSummon, isTrue);
    expect(game.highSummon(), isTrue);
    await tester.pump();

    expect(game.units.length, game.layout.slotCount);
    expect(state.gems, 0);
    // 고급소환은 유니크 이상만 나온다.
    expect(
      game.units.any((u) => u.spec.rarity.index >= Rarity.unique.index),
      isTrue,
    );
  });

  test('시뮬레이터가 복사해 쓰는 상수가 실제 게임과 맞는다', () {
    // tool/balance_sim.dart 는 도감·필드가 Flutter 에 의존해 불러올 수 없어서
    // 아래 두 값을 복사해 쓴다. 여기가 깨지면 시뮬레이터도 같이 고쳐야 한다.
    expect(
      [for (final r in Rarity.values) kUnitsByRarity[r]!.length],
      [4, 4, 4, 4, 4, 3, 3], // kTypesPerRarity
    );
    expect(FieldLayout.maxSlots, 21); // kSlots

    // 시뮬레이터의 _highSummonTarget 은 «유니크 = 2번 칸», «소환 가능한 최고
    // 등급 = 소환 가중치의 마지막 칸» 을 가정한다.
    expect(Rarity.unique.index, 2);
    expect(
      Rarity.values.where((r) => r.summonable).length,
      Balance.summonWeights(0).length,
    );
  });

  test('초월 셋은 DPS 가 같고 공격 방식만 다르다', () {
    final units = kUnitsByRarity[Rarity.transcendent]!;
    expect(units.length, greaterThan(1), reason: '합성했을 때 무엇이 나올지 갈린다');
    expect(
      units.map((u) => u.style).toSet().length,
      units.length,
      reason: '공격 방식이 겹치면 종류를 늘린 보람이 없다',
    );

    // 어느 초월이 나오든 판이 기울지 않아야 한다. 도박의 기댓값이 등급 기본치로
    // 계산돼 있어서(Balance.hardTopTierDamage), 여기가 벌어지면 그 계산도 틀어진다.
    final dps = units.map((u) => u.dps).toList();
    expect(
      dps.reduce(math.max) / dps.reduce(math.min),
      lessThan(1.03),
      reason: 'DPS: $dps',
    );
  });

  group('어려움: 초월 합성 도박', () {
    final myth = kUnitsByRarity[Rarity.mythic]!.first;

    test('도박은 도박 모드의 초월 합성 하나뿐이다', () {
      expect(
        GameMode.values.where((m) => m.hasGamble),
        [GameMode.hard, GameMode.hell],
        reason: '도박이 붙는 모드가 늘면 여기도 같이 고쳐야 한다',
      );
      for (final mode in GameMode.values) {
        for (var r = 0; r < Rarity.values.length - 1; r++) {
          final chance = Balance.mergeChance(r, mode);
          final gamble = mode.hasGamble && r == Rarity.mythic.index;
          expect(
            chance,
            gamble ? Balance.hardMergeChance : 1,
            reason: '${mode.label} · ${Rarity.values[r].label}',
          );
        }
      }
    });

    test('초월 보너스도 도박 모드에서만 붙는다', () {
      for (final mode in GameMode.values) {
        for (final rarity in Rarity.values) {
          final boosted = mode.hasGamble && rarity == Rarity.transcendent;
          expect(
            Balance.rarityDamageBonus(rarity.index, mode),
            boosted ? Balance.hardTopTierDamage : 1,
            reason: '${mode.label} · ${rarity.label}',
          );
        }
      }
    });

    testWidgets('성공하면 재료 3기가 초월 1기가 된다', (tester) async {
      final game = await _boot(tester, random: _FixedRandom(0));
      game.setMode(GameMode.hard);
      game.startGame();
      game.placeUnits(myth, Balance.mergeCount);

      expect(game.mergeOnce(specId: myth.id), isTrue);
      await tester.pump();

      expect(game.units.length, 1);
      expect(game.units.single.spec.rarity, Rarity.transcendent);
      expect(game.state.totalMerges, 1);
      expect(game.state.failedMerges, 0);
    });

    testWidgets('실패하면 ${Balance.mergeFailLoss}기만 사라지고 아무것도 안 나온다', (
      tester,
    ) async {
      final game = await _boot(tester, random: _FixedRandom(0.99));
      game.setMode(GameMode.hard);
      game.startGame();
      game.placeUnits(myth, Balance.mergeCount);

      expect(game.mergeOnce(specId: myth.id), isTrue);
      await tester.pump();

      expect(game.units.length, Balance.mergeCount - Balance.mergeFailLoss);
      expect(game.units.single.spec.id, myth.id, reason: '남은 건 재료 그대로다');
      expect(game.state.totalMerges, 0);
      expect(game.state.failedMerges, 1);
      expect(game.unitCounts[myth.id], game.units.length);
    });

    testWidgets('다른 모드에서는 같은 합성이 확정이다', (tester) async {
      final game = await _boot(tester, random: _FixedRandom(0.99));
      game.setMode(GameMode.normal);
      game.startGame();
      game.placeUnits(myth, Balance.mergeCount);

      expect(game.mergeOnce(specId: myth.id), isTrue);
      await tester.pump();

      expect(game.units.single.spec.rarity, Rarity.transcendent);
      expect(game.state.failedMerges, 0);
    });

    testWidgets('자동 합성은 도박을 걸지 않는다', (tester) async {
      final game = await _boot(tester, random: _FixedRandom(0.99));
      game.setMode(GameMode.hard);
      game.startGame();
      final normal = kUnitsByRarity[Rarity.normal]!.first;
      game
        ..placeUnits(myth, Balance.mergeCount)
        ..placeUnits(normal, Balance.mergeCount);
      game.state.autoMerge = true;

      for (var i = 0; i < 30; i++) {
        game.update(1 / 60);
      }
      await tester.pump();

      expect(
        game.unitCounts[myth.id],
        Balance.mergeCount,
        reason: '거는 판단은 플레이어 몫이라 신화는 그대로 남는다',
      );
      expect(game.unitCounts[normal.id], isNull, reason: '확정 합성은 알아서 한다');
      expect(game.state.failedMerges, 0);
    });
  });

  testWidgets('클리어 모드는 정해진 웨이브를 막아내면 끝난다', (tester) async {
    final game = await _boot(tester);
    game.setMode(GameMode.easy);
    game.startGame();
    final end = Balance.clearWave(GameMode.easy)!;
    final state = game.state;
    state
      ..lives = 9999
      ..wave = end - 1
      ..waveCountdown = 0.05;

    // 마지막 웨이브가 시작된다.
    for (var i = 0; i < 60; i++) {
      game.update(1 / 60);
    }
    expect(state.wave, end);
    expect(state.isFinalWave, isTrue);
    expect(game.boss, isNotNull, reason: '$end웨이브는 보스 웨이브다');
    expect(state.isCleared, isFalse, reason: '아직 보스가 살아 있다');

    // 보스를 처치하면 클리어.
    game.boss!.takeDamage(1e30);
    for (var i = 0; i < 10; i++) {
      game.update(1 / 60);
    }
    await tester.pump();

    expect(state.isCleared, isTrue);
    expect(state.isFinished, isTrue);
    expect(find.text('정복 완료!'), findsOneWidget);

    // 더 이상 웨이브가 시작되지 않는다.
    for (var i = 0; i < 60 * 40; i++) {
      game.update(1 / 60);
    }
    expect(state.wave, end);
    expect(game.enemies, isEmpty);
  });

  testWidgets('무한 모드는 끝나는 웨이브가 없다', (tester) async {
    final game = await _boot(tester);
    game.setMode(GameMode.endless);
    game.startGame();
    final state = game.state;
    state
      ..lives = 9999
      ..wave = 100
      ..waveCountdown = 0.05;

    expect(Balance.clearWave(GameMode.endless), isNull);
    expect(state.isFinalWave, isFalse);
    for (var i = 0; i < 60 * 3; i++) {
      game.update(1 / 60);
    }
    expect(state.wave, greaterThan(100));
    expect(state.isCleared, isFalse);
  });

  test('어려움만 결승선이 멀다', () {
    expect(Balance.clearWave(GameMode.easy), 100);
    expect(Balance.clearWave(GameMode.normal), 100);
    expect(Balance.clearWave(GameMode.hard), 150);
    expect(Balance.clearWave(GameMode.endless), isNull);
  });

  testWidgets('인트로에서 모드를 고르고, 결과 화면에서 다시 고를 수 있다', (tester) async {
    final game = await _boot(tester);
    final state = game.state;

    // 기본은 클리어 모드.
    expect(state.mode, GameMode.easy);
    for (final mode in GameMode.values) {
      expect(find.text(mode.label), findsOneWidget, reason: mode.name);
    }

    await tester.tap(find.text(GameMode.endless.label));
    await tester.pump();
    expect(state.mode, GameMode.endless);

    game.startGame();
    await tester.pump();
    expect(find.text('시작하기'), findsNothing);

    // 모드는 다시 시작해도 유지된다.
    game.restart();
    await tester.pump();
    expect(state.mode, GameMode.endless);
    expect(state.started, isTrue);

    // 인트로로 돌아가면 다시 고를 수 있다.
    game.restart(toIntro: true);
    await tester.pump();
    expect(state.started, isFalse);
    expect(find.text('시작하기'), findsOneWidget);
    expect(state.mode, GameMode.endless, reason: '고른 모드는 남아 있다');
  });

  group('고급소환이 겨냥할 유닛 고르기', () {
    UnitSpec of(String id) => kUnitById[id]!;

    test('합성까지 하나 남은 유닛을 고른다', () {
      final specs = [of('skeleton'), of('skeleton'), of('golem')];
      expect(pickHighSummonTarget(specs)?.id, 'skeleton');
    });

    test('여럿이면 등급이 가장 높은 쪽', () {
      final specs = [
        of('skeleton'),
        of('skeleton'),
        of('paladin'),
        of('paladin'),
      ];
      expect(pickHighSummonTarget(specs)?.id, 'paladin');
    });

    test('유니크 미만은 겨냥하지 않는다', () {
      // 노말·레어까지 콕 집어 주면 비싼 값을 치른 보람이 없다.
      final specs = [of('slime'), of('slime'), of('golem'), of('golem')];
      expect(pickHighSummonTarget(specs), isNull);
    });

    test('합성 전용 등급은 겨냥하지 않는다', () {
      // 신화 이상은 소환으로 나올 수 없다. 돈 주고 사게 하면 규칙이 깨진다.
      final specs = [of('ancientdragon'), of('ancientdragon')];
      expect(pickHighSummonTarget(specs), isNull);
    });

    test('이미 3개면 겨냥하지 않는다', () {
      // 합성만 누르면 되는 상태다.
      final specs = [of('skeleton'), of('skeleton'), of('skeleton')];
      expect(pickHighSummonTarget(specs), isNull);
    });

    test('후보가 없으면 null', () {
      expect(pickHighSummonTarget(const []), isNull);
      expect(pickHighSummonTarget([of('skeleton')]), isNull);
    });
  });

  testWidgets('고급소환은 미리 알린 유닛을 그대로 준다', (tester) async {
    final game = await _boot(tester);
    game.startGame();
    final state = game.state;
    final target = kUnitById['skeleton']!;
    game.placeUnits(target, Balance.mergeCount - 1);
    await tester.pump();

    expect(state.highSummonName, target.name);
    expect(find.textContaining(target.name), findsWidgets, reason: '버튼에 뜬다');

    state.gems = Balance.highSummonGems;
    expect(game.highSummon(), isTrue);
    await tester.pump();

    expect(game.unitCounts[target.id], Balance.mergeCount);
    expect(state.gems, 0);
    // 하나 남은 자리를 채웠으니 이제 겨냥할 대상이 없다.
    expect(state.highSummonName, isNull);
  });

  group('유닛별 처치 수', () {
    testWidgets('마지막 일격을 넣은 유닛에게 킬이 붙는다', (tester) async {
      final game = await _boot(tester);
      game.startGame();
      final state = game.state;
      // 한 종류만 세워 두면 누가 잡았는지가 분명하다.
      final paladin = kUnitById['paladin']!;
      game.placeUnits(paladin, 3);
      state.waveCountdown = 0.05;
      await tester.pump();

      for (var i = 0; i < 60 * 25 && state.totalKills == 0; i++) {
        game.update(1 / 60);
      }
      await tester.pump();

      expect(state.totalKills, greaterThan(0), reason: '뭔가는 잡았어야 한다');
      expect(state.killsByUnit[paladin.id], state.totalKills);
    });

    testWidgets('중독으로 죽으면 중독을 건 유닛이 가져간다', (tester) async {
      final game = await _boot(tester);
      game.startGame();
      final state = game.state;
      // 독거미는 중독만 건다. 도트가 터지는 시점에는 이미 다른 일이 일어난 뒤라,
      // 출처를 기억해 두지 않으면 킬이 아무에게도 안 붙는다.
      final spider = kUnitById['spider']!;
      game.placeUnits(spider, 3);
      state.waveCountdown = 0.05;
      await tester.pump();

      for (var i = 0; i < 60 * 25 && state.totalKills == 0; i++) {
        game.update(1 / 60);
      }
      await tester.pump();

      expect(state.totalKills, greaterThan(0));
      expect(state.killsByUnit[spider.id], state.totalKills);
    });

    testWidgets('드롭다운이 우측 상단에서 열리고 유닛별로 보여 준다', (tester) async {
      final game = await _boot(tester);
      // 이모지 하나로 찾으면 다른 화면(모드 카드 등)과 부딪치므로 킬보드
      // 안쪽만 본다.
      final toggle = find.descendant(
        of: find.byType(KillBoard),
        matching: find.text('💀'),
      );
      expect(toggle, findsNothing, reason: '시작 전에는 보여 줄 게 없다');

      game.startGame();
      final state = game.state;
      state
        ..totalKills = 9
        ..killsByUnit['slime'] = 6
        ..killsByUnit['golem'] = 3;
      await tester.pump();

      // 접힌 상태에서는 합계만 보인다.
      expect(toggle, findsOneWidget);
      expect(find.text('9'), findsOneWidget);
      expect(find.text('슬라임'), findsNothing);

      await tester.tap(find.text('9'));
      await tester.pump();

      expect(find.text('유닛별 처치'), findsOneWidget);
      expect(find.text('슬라임'), findsOneWidget);
      expect(find.text('6'), findsOneWidget);
      expect(find.text('돌골렘'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);

      // 다시 누르면 접힌다.
      await tester.tap(find.text('9'));
      await tester.pump();
      expect(find.text('유닛별 처치'), findsNothing);
    });

    testWidgets('낮은 화면에서 목록을 다 펼쳐도 넘치지 않는다', (tester) async {
      tester.view
        ..physicalSize = const Size(720, 1120) // 360x560, 필드가 아주 낮다
        ..devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      late LuckyDefenseGame game;
      await tester.pumpWidget(
        LuckyDefenseApp(
          gameFactory: () {
            game = LuckyDefenseGame(
              state: GameState(),
              random: math.Random(1),
              records: MemoryRecordStore(),
              leaderboard: MemoryLeaderboard(isAvailable: false),
            );
            return game;
          },
        ),
      );
      await tester.pump();
      game.startGame();

      // 도감에 있는 유닛이 전부 한 번씩은 잡은, 가장 긴 목록.
      var total = 0;
      for (final spec in kUnitCatalog) {
        game.state.killsByUnit[spec.id] = 1234;
        total += 1234;
      }
      game.state.totalKills = total;
      await tester.pump();

      // 칼럼은 필드 높이만큼 늘어나 있으므로 토글을 콕 집어 누른다.
      // (빈 칸은 포인터를 먹지 않고 게임으로 넘어간다.)
      await tester.tap(find.text('💀'));
      await tester.pump();

      expect(tester.takeException(), isNull);
      // 1234 는 «1,234» 로 줄여 쓴다 — 세 자리가 넘어가면 칸을 밀어낸다.
      expect(find.text('1,234'), findsWidgets);
    });

    testWidgets('다시 시작하면 집계가 비워진다', (tester) async {
      final game = await _boot(tester);
      game.startGame();
      game.state
        ..totalKills = 5
        ..killsByUnit['slime'] = 5;

      game.restart();
      await tester.pump();

      expect(game.state.killsByUnit, isEmpty);
      expect(game.state.totalKills, 0);
    });
  });

  group('랭킹', () {
    testWidgets('좁은 화면에서도 모드 칩 셋이 넘치지 않는다', (tester) async {
      // 지옥이 붙어 칩이 셋(어려움·지옥·무한)이 됐다. 320pt 에서 확인한다.
      tester.view
        ..physicalSize = const Size(640, 1600)
        ..devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      late LuckyDefenseGame game;
      await tester.pumpWidget(
        LuckyDefenseApp(
          gameFactory: () {
            game = LuckyDefenseGame(
              state: GameState(),
              random: math.Random(1),
              records: MemoryRecordStore(),
              leaderboard: MemoryLeaderboard(),
            );
            return game;
          },
        ),
      );
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      await tester.ensureVisible(find.text('랭킹'));
      await tester.tap(find.text('랭킹'));
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(tester.takeException(), isNull);
      for (final mode in GameMode.values.where((m) => m.hasRanking)) {
        expect(find.text(mode.label), findsWidgets, reason: mode.label);
      }
    });

    test('이름을 다듬는다', () {
      expect(normalizeRankName('  택민  '), '택민');
      expect(normalizeRankName('택\n민   입니다'), '택 민 입니다');
      expect(normalizeRankName('   '), isNull);
      expect(normalizeRankName(''), isNull);
      expect(
        normalizeRankName('가나다라마바사아자차카타파하'),
        '가나다라마바사아자차카타',
        reason: '$kMaxRankNameLength 자에서 자른다',
      );
    });

    test('랭킹은 어려움과 무한에만 있다', () {
      expect(GameMode.easy.hasRanking, isFalse);
      expect(GameMode.normal.hasRanking, isFalse);
      expect(GameMode.hard.hasRanking, isTrue);
      expect(GameMode.hell.hasRanking, isTrue);
      expect(GameMode.endless.hasRanking, isTrue);
    });

    test('모드마다 컬렉션이 다르다', () {
      expect(FirestoreLeaderboard.collectionOf(GameMode.hard), 'ranking_hard');
      expect(
        FirestoreLeaderboard.collectionOf(GameMode.endless),
        'ranking_endless',
      );
    });

    test('설정이 없으면 랭킹을 쓸 수 없다', () {
      // --dart-define 없이 빌드하면 UI 가 랭킹을 아예 감춘다.
      expect(FirestoreLeaderboard().isAvailable, isFalse);
      expect(
        FirestoreLeaderboard(projectId: 'p', apiKey: 'k').isAvailable,
        isTrue,
      );
    });

    testWidgets('게임이 끝나면 이름을 받아 랭킹에 올린다', (tester) async {
      final board = MemoryLeaderboard();
      final game = await _boot(tester, leaderboard: board);
      game.setMode(GameMode.hard);
      game.startGame();
      final state = game.state;
      state
        ..wave = 77
        ..phase = GamePhase.gameOver;
      await tester.pump();

      expect(find.text('등록'), findsOneWidget, reason: '어려움은 랭킹이 있다');

      await tester.enterText(find.byType(TextField), '택민');
      await tester.tap(find.text('등록'));
      await tester.pump();
      await tester.pump();

      expect(board.submitCount, 1);
      final entries = board.entries[GameMode.hard]!;
      expect(entries.single.name, '택민');
      expect(entries.single.wave, 77);
      expect(state.rankSubmitted, isTrue);

      // 한 판에 한 번만 받는다 — 다시 눌러도 줄이 늘지 않는다.
      expect(await game.submitRank('택민'), isFalse);
      expect(board.submitCount, 1);
    });

    testWidgets('쉬움·보통에서는 이름 입력이 나오지 않는다', (tester) async {
      final game = await _boot(tester, leaderboard: MemoryLeaderboard());
      game.setMode(GameMode.normal);
      game.startGame();
      game.state
        ..wave = 50
        ..phase = GamePhase.gameOver;
      await tester.pump();

      expect(find.text('등록'), findsNothing);
    });

    testWidgets('설정이 없는 빌드에서는 랭킹 UI 가 없다', (tester) async {
      final game = await _boot(
        tester,
        leaderboard: MemoryLeaderboard(isAvailable: false),
      );
      game.setMode(GameMode.hard);
      expect(find.text('랭킹'), findsNothing, reason: '인트로 버튼');

      game.startGame();
      game.state
        ..wave = 30
        ..phase = GamePhase.gameOver;
      await tester.pump();
      expect(find.text('등록'), findsNothing);
    });

    testWidgets('빈 이름은 올리지 않는다', (tester) async {
      final board = MemoryLeaderboard();
      final game = await _boot(tester, leaderboard: board);
      game.setMode(GameMode.endless);
      game.startGame();
      game.state
        ..wave = 42
        ..phase = GamePhase.gameOver;
      await tester.pump();

      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.text('등록'));
      await tester.pump();
      await tester.pump();

      expect(board.submitCount, 0);
      expect(game.state.rankSubmitted, isFalse);
      expect(find.textContaining('등록하지 못했습니다'), findsOneWidget);
    });
  });

  group('키보드 단축키', () {
    testWidgets('소환·고급소환·강화를 키로 누른다', (tester) async {
      final game = await _boot(tester);
      game.startGame();
      final state = game.state;
      state
        ..gold = 1 << 20
        ..gems = 1 << 10;
      await tester.pump();

      await tester.sendKeyEvent(GameKey.summon.key);
      await tester.pump();
      expect(game.units.length, 1, reason: 'D');

      await tester.sendKeyEvent(GameKey.highSummon.key);
      await tester.pump();
      expect(game.units.length, 2, reason: 'F');
      expect(
        game.units.last.spec.rarity.index,
        greaterThanOrEqualTo(Rarity.unique.index),
        reason: '고급소환은 유니크 이상',
      );

      await tester.sendKeyEvent(GameKey.attack.key);
      await tester.sendKeyEvent(GameKey.attackSpeed.key);
      await tester.sendKeyEvent(GameKey.goldGain.key);
      await tester.sendKeyEvent(GameKey.luck.key);
      await tester.pump();
      expect(state.atkLevel, 1, reason: 'Q');
      expect(state.spdLevel, 1, reason: 'W');
      expect(state.goldLevel, 1, reason: 'E');
      expect(state.luckLevel, greaterThan(0), reason: 'R');

      final lives = state.lives;
      await tester.sendKeyEvent(GameKey.life.key);
      await tester.pump();
      expect(state.lives, lives + 1, reason: 'T');
    });

    testWidgets('C 는 고른 유닛을 합성한다', (tester) async {
      final game = await _boot(tester);
      game.startGame();
      final slime = kUnitById['slime']!;
      game.placeUnits(slime, Balance.mergeCount);
      game.focusUnit(game.units.first);
      await tester.pump();

      await tester.sendKeyEvent(GameKey.merge.key);
      await tester.pump();

      expect(game.unitCounts[slime.id] ?? 0, 0, reason: '재료 3기가 사라진다');
      expect(game.units.length, 1);
      expect(game.units.first.spec.rarity, slime.rarity.next);
    });

    testWidgets('아무것도 안 골랐으면 C 는 아무 일도 안 한다', (tester) async {
      final game = await _boot(tester);
      game.startGame();
      // 합성할 수 있는 유닛이 판에 있어도, 고르지 않았으면 손대지 않는다.
      // 어려움에서 «아무거나» 로 흘러가면 누른 적 없는 도박이 터진다.
      final slime = kUnitById['slime']!;
      game.placeUnits(slime, Balance.mergeCount);
      game.clearSelection();
      await tester.pump();

      await tester.sendKeyEvent(GameKey.merge.key);
      await tester.pump();

      expect(game.unitCounts[slime.id], Balance.mergeCount);
      expect(game.state.totalMerges, 0);
    });

    testWidgets('재료가 모자라면 C 를 눌러도 그대로다', (tester) async {
      final game = await _boot(tester);
      game.startGame();
      final slime = kUnitById['slime']!;
      game.placeUnits(slime, Balance.mergeCount - 1);
      game.focusUnit(game.units.first);
      await tester.pump();

      await tester.sendKeyEvent(GameKey.merge.key);
      await tester.pump();

      expect(game.unitCounts[slime.id], Balance.mergeCount - 1);
      expect(game.state.totalMerges, 0);
    });

    testWidgets('인트로·일시정지 중에는 듣지 않는다', (tester) async {
      final game = await _boot(tester);
      final state = game.state;
      state.gold = 1 << 20;

      // 아직 시작 전(인트로).
      await tester.sendKeyEvent(GameKey.summon.key);
      await tester.pump();
      expect(game.units, isEmpty, reason: '인트로가 덮고 있다');

      game.startGame();
      state.paused = true;
      await tester.pump();
      await tester.sendKeyEvent(GameKey.summon.key);
      await tester.pump();
      expect(game.units, isEmpty, reason: '멈춘 동안에는 조작 패널도 잠긴다');

      state.paused = false;
      await tester.pump();
      await tester.sendKeyEvent(GameKey.summon.key);
      await tester.pump();
      expect(game.units.length, 1);
    });

    // 오버라이드는 테스트 본문이 끝나기 전에 되돌려야 한다 — 프레임워크가
    // 본문 종료 시점에 «전역 디버그 변수가 남아 있지 않은지» 를 검사한다.
    testWidgets('키캡은 키보드가 있는 환경에서만 뜬다', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final game = await _boot(tester);
        game.startGame();
        // 합성 키캡은 선택 카드 위에만 있으니 유닛을 하나 골라 둔다.
        game.placeUnits(kUnitById['slime']!, 1);
        game.focusUnit(game.units.first);
        await tester.pump();

        // 강화 목록은 가로로 스크롤되므로 한 화면에 다 뜨지 않는다.
        // 끝까지 밀어 가며 모은다.
        final seen = <String>{};
        void collect() {
          for (final shortcut in GameKey.values) {
            if (find.text(shortcut.hint).evaluate().isNotEmpty) {
              seen.add(shortcut.hint);
            }
          }
        }

        collect();
        await tester.drag(find.byType(ListView), const Offset(-400, 0));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        collect();

        expect(seen, {for (final s in GameKey.values) s.hint});
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('폰에서는 키캡을 띄우지 않는다', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final game = await _boot(tester);
        game.startGame();
        await tester.pump();

        expect(find.text(GameKey.summon.hint), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('자동 판매 대상 고르기', () {
    UnitSpec of(String id) => kUnitById[id]!;

    test('등급이 가장 낮은 유닛을 고른다', () {
      final specs = [of('skeleton'), of('golem'), of('slime'), of('treant')];
      expect(pickAutoSellIndex(specs), 2);
    });

    test('3개 맞춰 둔 합성 세트는 건드리지 않는다', () {
      final specs = [of('slime'), of('slime'), of('slime'), of('snail')];
      expect(pickAutoSellIndex(specs), 3);
    });

    test('세트를 깨지 않는 쪽이면 보유 수가 많아도 그쪽을 판다', () {
      final specs = [
        of('slime'),
        of('slime'),
        of('slime'),
        of('mushroom'),
        of('mushroom'),
        of('mushroom'),
        of('mushroom'),
      ];
      expect(pickAutoSellIndex(specs), 3);
    });

    test('모두 세트뿐이면 보유 수가 적은 쪽을 판다', () {
      final specs = [
        of('slime'),
        of('slime'),
        of('slime'),
        of('mushroom'),
        of('mushroom'),
        of('mushroom'),
        of('mushroom'),
        of('mushroom'),
        of('mushroom'),
      ];
      expect(pickAutoSellIndex(specs), 0);
    });

    test('유닛이 없으면 -1', () {
      expect(pickAutoSellIndex(const []), -1);
    });
  });

  testWidgets('같은 유닛 3개를 모으면 상위 등급으로 합성된다', (tester) async {
    final game = await _boot(tester);
    game.startGame();
    final state = game.state;
    state.gold = 1 << 24;

    for (var i = 0; i < game.layout.slotCount; i++) {
      game.summon();
    }
    await tester.pump();

    expect(state.mergeableGroups, greaterThan(0));
    final beforeUnits = game.units.length;
    final targetId = game.unitCounts.entries
        .firstWhere((e) => e.value >= Balance.mergeCount)
        .key;
    final targetTier = game.units
        .firstWhere((u) => u.spec.id == targetId)
        .spec
        .rarity
        .index;

    expect(game.mergeOnce(specId: targetId), isTrue);
    await tester.pump();

    // 3개가 사라지고 1개가 생기므로 순증감은 -2.
    expect(game.units.length, beforeUnits - 2);
    expect(state.totalMerges, 1);
    expect(
      game.units.any((u) => u.spec.rarity.index == targetTier + 1),
      isTrue,
    );
  });

  testWidgets('웨이브가 시작되고 몬스터가 스폰된다', (tester) async {
    final game = await _boot(tester);
    game.startGame();

    // 첫 웨이브 시작까지 진행.
    for (var i = 0; i < 60 * 12; i++) {
      game.update(1 / 60);
    }
    expect(game.state.wave, greaterThanOrEqualTo(1));
    expect(game.enemies, isNotEmpty);
    expect(game.enemies.first.progress, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('유닛이 몬스터를 공격해 처치하고 골드를 준다', (tester) async {
    final game = await _boot(tester);
    game.startGame();
    final state = game.state;
    state.gold = 1 << 24;
    // 모든 슬롯을 채워 경로 전체를 커버한다.
    for (var i = 0; i < game.layout.slotCount; i++) {
      game.summon();
    }
    state.gold = 0;

    for (var i = 0; i < 60 * 20; i++) {
      game.update(1 / 60);
    }

    expect(state.wave, greaterThanOrEqualTo(1));
    expect(state.totalKills, greaterThan(0));
    expect(state.gold, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('막지 못하면 라이프가 깎이고 게임오버가 뜬다', (tester) async {
    final game = await _boot(tester);
    game.startGame();
    final state = game.state;

    // 유닛 없이 방치 → 몬스터가 성까지 도달.
    for (var i = 0; i < 60 * 60; i++) {
      game.update(1 / 60);
      if (state.isGameOver) {
        break;
      }
    }
    expect(state.lives, lessThan(Balance.startLives));

    // 강제로 게임오버까지.
    state.lives = 1;
    for (var i = 0; i < 60 * 120 && !state.isGameOver; i++) {
      game.update(1 / 60);
    }
    await tester.pump();

    expect(state.isGameOver, isTrue);
    expect(find.text('방어 실패'), findsOneWidget);

    game.restart();
    await tester.pump();
    expect(state.lives, Balance.startLives);
    expect(state.wave, 0);
    expect(game.units, isEmpty);
    expect(game.enemies, isEmpty);
    expect(find.text('방어 실패'), findsNothing);
  });

  testWidgets('보스 웨이브에서 보스가 등장한다', (tester) async {
    final game = await _boot(tester);
    game.startGame();
    final state = game.state;

    // 보스 웨이브 직전까지 웨이브만 빠르게 넘긴다.
    state.wave = Balance.bossEvery - 1;
    state.waveCountdown = 0.1;
    state.lives = 9999;
    for (var i = 0; i < 60 * 3; i++) {
      game.update(1 / 60);
    }

    expect(state.wave, Balance.bossEvery);
    expect(game.boss, isNotNull);
    expect(game.boss!.isBoss, isTrue);
    expect(state.bossName, isNotNull);

    // 보스를 처치하면 다이아를 준다.
    final gemsBefore = state.gems;
    game.boss!.takeDamage(1e30);
    expect(state.gems, greaterThan(gemsBefore));
    expect(game.boss, isNull);
  });

  testWidgets('강화와 행운 업그레이드가 스탯에 반영된다', (tester) async {
    final game = await _boot(tester);
    game.startGame();
    final state = game.state;
    state.gold = 1 << 24;
    state.gems = 999;

    expect(game.upgradeAttack(), isTrue);
    expect(game.upgradeSpeed(), isTrue);
    expect(game.upgradeGold(), isTrue);
    expect(state.damageMultiplier, greaterThan(1));
    expect(state.attackSpeedMultiplier, greaterThan(1));
    expect(state.goldMultiplier, greaterThan(1));

    final ratesBefore = Balance.summonRates(state.luckLevel);
    expect(game.upgradeLuck(), isTrue);
    final ratesAfter = Balance.summonRates(state.luckLevel);
    expect(
      ratesAfter[Rarity.legendary.index],
      greaterThan(ratesBefore[Rarity.legendary.index]),
    );
    expect(
      ratesAfter[Rarity.normal.index],
      lessThan(ratesBefore[Rarity.normal.index]),
    );
  });

  group('드래그 중 사격 위치', () {
    testWidgets('놓기 전까지는 출발한 자리에서 쏜다', (tester) async {
      final game = await _boot(tester);
      game.startGame();
      game.placeUnits(kUnitById['slime']!, 1);
      final unit = game.units.first;
      final home = unit.position.clone();
      await tester.pump();

      // 몸을 멀찍이 끌어다 놓는다(드래그 중인 상태).
      unit.beginDragForTest();
      unit.position.add(Vector2(200, 120));

      expect(unit.position, isNot(home), reason: '몸은 따라왔다');
      expect(unit.firePosition, home, reason: '사격은 원래 자리에서');

      // 놓으면 그때부터 새 자리다.
      unit.endDragForTest();
      expect(unit.firePosition, unit.position);
    });

    testWidgets('드래그 중 날아가는 총알도 원래 자리에서 나간다', (tester) async {
      final game = await _boot(tester);
      game.startGame();
      game.placeUnits(kUnitById['slime']!, 1);
      final unit = game.units.first;
      final home = unit.position.clone();
      game.state.waveCountdown = 0.05;
      for (var i = 0; i < 60 * 15 && game.enemies.isEmpty; i++) {
        game.update(1 / 60);
      }
      expect(game.enemies, isNotEmpty, reason: '쏠 대상이 있어야 한다');

      unit.beginDragForTest();
      unit.position.add(Vector2(150, 90));
      // 총알은 빠르게 날아가 사라지므로 매 프레임 훑어 «갓 생긴» 것을 잡는다.
      final seen = <Vector2>[];
      final known = <ProjectileComponent>{};
      for (var i = 0; i < 60 * 5; i++) {
        game.update(1 / 60);
        for (final p in game.fieldRoot.children
            .whereType<ProjectileComponent>()) {
          if (known.add(p)) {
            seen.add(p.position.clone());
          }
        }
      }

      expect(seen, isNotEmpty, reason: '드래그 중에도 쏜다');
      // 끌고 간 자리가 아니라 원래 자리 근처에서 나와야 한다.
      final dragged = unit.position.distanceTo(home);
      for (final origin in seen) {
        expect(origin.distanceTo(home), lessThan(dragged / 2));
      }
    });
  });

  testWidgets('드래그로 유닛 자리를 서로 바꾼다', (tester) async {
    final game = await _boot(tester);
    game.startGame();
    game.state.gold = 1 << 24;
    game.summon();
    game.summon();
    await tester.pump();

    final a = game.units[0];
    final b = game.units[1];
    final slotA = a.slotIndex;
    final slotB = b.slotIndex;

    game.moveUnitToSlot(a, slotB);
    expect(a.slotIndex, slotB);
    expect(b.slotIndex, slotA);
    expect(a.position, game.layout.slotCenters[slotB]);
  });

  testWidgets('저장된 최고 기록을 불러와 HUD와 인트로에 보여준다', (tester) async {
    final store = MemoryRecordStore(const BestRecord(wave: 17, kills: 428));
    final game = await _boot(tester, records: store);
    await tester.pump();
    await tester.pump();

    expect(game.state.best.wave, 17);
    expect(find.text('🏆 최고 기록 17 웨이브'), findsOneWidget);

    game.startGame();
    await tester.pump();
    // 웨이브 배지 옆에 최고 기록이 병기된다.
    expect(find.text('17'), findsWidgets);
  });

  testWidgets('기록을 넘기면 저장되고, 못 넘기면 저장하지 않는다', (tester) async {
    final store = MemoryRecordStore(const BestRecord(wave: 17, kills: 428));
    final game = await _boot(tester, records: store);
    await tester.pump();
    final state = game.state;
    game.startGame();

    // 기존 기록보다 낮은 성적 → 갱신 없음.
    state
      ..wave = 12
      ..totalKills = 300;
    game.submitRecord();
    expect(state.isNewRecord, isFalse);
    expect(store.saveCount, 0);
    expect(state.best.wave, 17);

    // 같은 웨이브에 처치 수만 많으면 갱신된다.
    state
      ..wave = 17
      ..totalKills = 500;
    game.submitRecord();
    expect(state.isNewRecord, isTrue);
    expect(state.best.kills, 500);

    // 더 높은 웨이브 → 갱신.
    state
      ..wave = 23
      ..totalKills = 900
      ..bestRarityTier = 4;
    game.submitRecord();
    await tester.pump();

    expect(state.best.wave, 23);
    expect(store.record.wave, 23);
    expect(store.record.rarityTier, 4);
    expect(store.saveCount, 2);
  });

  testWidgets('게임오버 화면에 최고 기록과 신기록 표시가 나온다', (tester) async {
    final store = MemoryRecordStore();
    final game = await _boot(tester, records: store);
    await tester.pump();
    final state = game.state;
    game.startGame();

    // 유닛 없이 방치해 게임오버까지.
    state.lives = 1;
    for (var i = 0; i < 60 * 120 && !state.isGameOver; i++) {
      game.update(1 / 60);
    }
    await tester.pump();

    expect(state.isGameOver, isTrue);
    expect(state.isNewRecord, isTrue);
    expect(store.record.wave, state.wave);
    expect(find.text('신기록 달성!'), findsOneWidget);
    expect(find.text('${state.wave} 웨이브'), findsOneWidget);

    // 다시 시작해도 최고 기록은 남는다.
    final achieved = state.best.wave;
    game.restart();
    await tester.pump();
    expect(state.wave, 0);
    expect(state.best.wave, achieved);
    expect(state.isNewRecord, isFalse);
  });

  testWidgets('휴대폰 화면에서 앱 전체가 예외 없이 렌더링된다', (tester) async {
    tester.view
      ..physicalSize =
          const Size(1170, 2532) // iPhone 13 Pro
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const LuckyDefenseApp());
    // 라우트 전환이 끝나야 오버레이가 포인터를 받는다.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(find.text('따이 운빨 디펜스'), findsOneWidget);
    expect(find.text('소환'), findsOneWidget);
    expect(find.text('시작하기'), findsOneWidget);

    await tester.tap(find.text('시작하기'));
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.text('시작하기'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('슬롯 격자는 화면 크기와 무관하게 한 줄 7개로 고정된다', () {
    const sizes = [
      [320.0, 480.0], // 작은 폰
      [390.0, 520.0], // 일반 폰
      [430.0, 700.0], // 큰 폰
      [480.0, 900.0], // 웹 세로로 긴 창
      [480.0, 360.0], // 웹 가로로 납작한 창(확대했을 때)
      [1200.0, 800.0], // 제한 전 원본 크기
    ];

    for (final wh in sizes) {
      final layout = FieldLayout(Vector2(wh[0], wh[1]));
      final reason = '${wh[0]}x${wh[1]}';

      expect(layout.slotCount, FieldLayout.maxSlots, reason: reason);
      expect(layout.slotCount, 21, reason: reason);

      // 같은 y 를 공유하는 슬롯이 정확히 6개씩, 3줄이다.
      final rows = <double, int>{};
      for (final c in layout.slotCenters) {
        rows.update(c.y, (v) => v + 1, ifAbsent: () => 1);
      }
      expect(rows.length, 3, reason: reason);
      expect(rows.values.every((v) => v == 7), isTrue, reason: reason);

      // 칸끼리 겹치지 않고 화면 안에 들어간다.
      final step = layout.slotCenters[1].x - layout.slotCenters[0].x;
      expect(step, greaterThan(layout.slotSize), reason: reason);
      expect(
        layout.slotCenters.first.x - layout.slotSize / 2,
        greaterThan(0),
        reason: reason,
      );
      expect(
        layout.slotCenters.last.x + layout.slotSize / 2,
        lessThan(wh[0]),
        reason: reason,
      );
    }
  });

  testWidgets('강화 메뉴 끝에 넘김 화살표가 나타나고 눌러서 넘긴다', (tester) async {
    final game = await _boot(tester);
    game.startGame();
    await tester.pump();

    // 처음에는 오른쪽으로만 넘길 수 있다.
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    expect(_arrowOpacity(tester, Icons.chevron_right), 1);
    expect(_arrowOpacity(tester, Icons.chevron_left), 0);

    final position = tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          ),
        )
        .position;

    // 오른쪽 화살표를 누르면 넘어간다.
    await tester.tap(find.byIcon(Icons.chevron_right));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(position.pixels, greaterThan(0));

    // 넘어간 뒤에는 왼쪽 화살표도 보인다.
    expect(_arrowOpacity(tester, Icons.chevron_left), 1);

    // 끝까지 가면 오른쪽 화살표가 사라진다.
    for (var n = 0; n < 6; n++) {
      await tester.tap(find.byIcon(Icons.chevron_right), warnIfMissed: false);
      for (var i = 0; i < 25; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }
    expect(position.pixels, position.maxScrollExtent);
    expect(_arrowOpacity(tester, Icons.chevron_right), 0);
  });

  testWidgets('하단 강화 메뉴를 마우스로 끌어 좌우로 넘길 수 있다', (tester) async {
    final game = await _boot(tester);
    game.startGame();
    await tester.pump();

    // 하단 강화 메뉴는 화면 폭보다 넓은 가로 목록이다.
    final row = find.byType(ListView);
    expect(row, findsOneWidget);
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: row, matching: find.byType(Scrollable)),
        )
        .position;
    expect(position.pixels, 0);
    expect(position.maxScrollExtent, greaterThan(0));

    // 마우스로 왼쪽으로 끌면 뒤쪽 항목이 보인다.
    await tester.drag(
      row,
      const Offset(-120, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    final afterLeft = position.pixels;
    expect(afterLeft, greaterThan(0));

    // 다시 오른쪽으로 끌면 되돌아온다.
    // (탄성 물리라 시작점을 넘어 음수까지 갈 수 있으므로 값만 줄면 된다.)
    await tester.drag(row, const Offset(200, 0), kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(position.pixels, lessThan(afterLeft));

    // Flame 티커가 매 프레임을 요청하므로 pumpAndSettle 은 끝나지 않는다.
    // 탄성 애니메이션이 가라앉을 만큼만 프레임을 돌린다.
    for (var i = 0; i < 90; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(position.pixels, 0);
  });

  testWidgets('넓은 화면에서는 폰 너비로 가운데 세운다', (tester) async {
    tester.view
      ..physicalSize =
          const Size(1600, 1000) // 데스크톱 브라우저
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const LuckyDefenseApp());
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    // HUD 가 화면 전체로 늘어나지 않고 480 폭 안에 들어간다.
    final hud = tester.getSize(find.byType(HudBar));
    expect(hud.width, lessThanOrEqualTo(480));
    expect(tester.takeException(), isNull);
  });

  testWidgets('작은 화면에서도 패널이 넘치지 않는다', (tester) async {
    tester.view
      ..physicalSize =
          const Size(640, 1136) // iPhone SE 1세대
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const LuckyDefenseApp());
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    // 모드 카드 넷이 2×2로 서도 넘치지 않는다.
    for (final mode in GameMode.values) {
      expect(find.text(mode.label), findsOneWidget, reason: mode.name);
    }
    expect(tester.takeException(), isNull);

    // 어려움을 고르면 규칙 안내가 한 줄 더 붙는다.
    // (인트로는 이 화면 높이보다 길어서 원래 스크롤해야 한다.)
    await tester.ensureVisible(find.text(GameMode.hard.label));
    await tester.pump();
    await tester.tap(find.text(GameMode.hard.label));
    await tester.pump();
    expect(find.textContaining('도박'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
