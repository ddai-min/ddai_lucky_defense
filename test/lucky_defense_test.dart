import 'dart:math' as math;

import 'package:ddai_lucky_defense/game/data/balance.dart';
import 'package:ddai_lucky_defense/game/data/rarity.dart';
import 'package:ddai_lucky_defense/game/data/unit_catalog.dart';
import 'package:ddai_lucky_defense/game/field_layout.dart';
import 'package:ddai_lucky_defense/game/game_state.dart';
import 'package:ddai_lucky_defense/game/lucky_defense_game.dart';
import 'package:ddai_lucky_defense/game/record_store.dart';
import 'package:ddai_lucky_defense/main.dart';
import 'package:ddai_lucky_defense/ui/hud_bar.dart';
import 'package:flame/components.dart';
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
    LuckyDefenseApp(
      gameFactory: () {
        game = LuckyDefenseGame(
          state: GameState(),
          random: math.Random(seed),
          records: records ?? MemoryRecordStore(),
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
      [4, 4, 4, 4, 4, 3, 1], // kTypesPerRarity
    );
    expect(FieldLayout.maxSlots, 18); // kSlots
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

  test('슬롯 격자는 화면 크기와 무관하게 한 줄 6개로 고정된다', () {
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
      expect(layout.slotCount, 18, reason: reason);

      // 같은 y 를 공유하는 슬롯이 정확히 6개씩, 3줄이다.
      final rows = <double, int>{};
      for (final c in layout.slotCenters) {
        rows.update(c.y, (v) => v + 1, ifAbsent: () => 1);
      }
      expect(rows.length, 3, reason: reason);
      expect(rows.values.every((v) => v == 6), isTrue, reason: reason);

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
    expect(tester.takeException(), isNull);
  });
}
