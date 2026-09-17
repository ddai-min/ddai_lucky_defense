import 'dart:math' as math;

import 'package:ddai_lucky_defense/game/data/balance.dart';
import 'package:ddai_lucky_defense/game/data/rarity.dart';
import 'package:ddai_lucky_defense/game/game_state.dart';
import 'package:ddai_lucky_defense/game/lucky_defense_game.dart';
import 'package:ddai_lucky_defense/game/record_store.dart';
import 'package:ddai_lucky_defense/main.dart';
import 'package:ddai_lucky_defense/ui/hud_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 실제 화면 구조 그대로, 시드를 고정한 게임을 띄운다.
Future<LuckyDefenseGame> _boot(
  WidgetTester tester, {
  int seed = 42,
  RecordStore? records,
}) async {
  tester.view
    ..physicalSize =
        const Size(1170, 2532) // iPhone 13 Pro
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  late LuckyDefenseGame game;
  await tester.pumpWidget(
    MaterialApp(
      home: GameScreen(
        gameFactory: () {
          game = LuckyDefenseGame(
            state: GameState(),
            random: math.Random(seed),
            records: records ?? MemoryRecordStore(),
          );
          return game;
        },
      ),
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

  testWidgets('슬롯이 가득 차면 더 소환되지 않는다', (tester) async {
    final game = await _boot(tester);
    game.startGame();
    game.state.gold = 1 << 24;

    for (var i = 0; i < game.layout.slotCount + 5; i++) {
      game.summon();
    }
    await tester.pump();

    expect(game.units.length, game.layout.slotCount);
    expect(game.state.slotsFull, isTrue);
    expect(game.summon(), isFalse);
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

    expect(find.text('운빨 디펜스'), findsOneWidget);
    expect(find.text('소환'), findsOneWidget);
    expect(find.text('시작하기'), findsOneWidget);

    await tester.tap(find.text('시작하기'));
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.text('시작하기'), findsNothing);
    expect(tester.takeException(), isNull);
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
    expect(tester.takeException(), isNull);
  });
}
