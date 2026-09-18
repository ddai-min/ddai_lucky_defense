import 'dart:async';
import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'components/effects.dart';
import 'components/enemy_component.dart';
import 'components/field_decor.dart';
import 'components/projectile_component.dart';
import 'components/render_utils.dart';
import 'components/unit_component.dart';
import 'data/balance.dart';
import 'data/enemy_catalog.dart';
import 'data/rarity.dart';
import 'data/unit_catalog.dart';
import 'field_layout.dart';
import 'game_state.dart';
import 'leaderboard.dart';
import 'record_store.dart';

/// 운빨 디펜스 본체.
///
/// 컴포넌트는 모두 [fieldRoot] 아래에 스크린 좌표 그대로 배치한다.
/// (카메라 변환을 쓰지 않으므로 좌표 계산이 단순하다.)
class LuckyDefenseGame extends FlameGame {
  LuckyDefenseGame({
    required this.state,
    math.Random? random,
    RecordStore? records,
    Leaderboard? leaderboard,
  }) : rng = random ?? math.Random(),
       _records = records ?? PrefsRecordStore(),
       leaderboard = leaderboard ?? FirestoreLeaderboard();

  final GameState state;
  final math.Random rng;
  final RecordStore _records;

  /// 모드별 랭킹. 설정이 없는 빌드에서는 [Leaderboard.isAvailable] 이 거짓이라
  /// UI 가 랭킹을 아예 감춘다.
  final Leaderboard leaderboard;

  final List<UnitComponent> units = [];
  final List<EnemyComponent> enemies = [];
  final Map<String, int> unitCounts = {};

  UnitComponent? selected;
  EnemyComponent? boss;
  int? dropTargetSlot;

  late final PositionComponent fieldRoot;
  late final BackgroundComponent _background;
  late final PathComponent _pathComponent;
  late final SlotLayerComponent _slotLayer;
  late final _FieldTapCatcher _tapCatcher;
  late final _BossBanner _bossBanner;

  FieldLayout? _layout;
  bool _ready = false;

  bool _hudDirty = false;
  double _hudTimer = 0;
  double _damageTextBudget = 20;

  double _shakeTime = 0;
  double _shakeMagnitude = 0;

  int _pendingSpawns = 0;
  double _spawnTimer = 0;
  double _spawnInterval = 0.5;
  EnemyKind? _spawnKind;
  double _spawnHp = 0;
  double _spawnLap = 20;
  bool _spawnIsBoss = false;

  FieldLayout get layout => _layout ??= FieldLayout(
    Vector2(size.x > 10 ? size.x : 400, size.y > 10 ? size.y : 640),
  );

  @override
  Color backgroundColor() => const Color(0xFF070A14);

  @override
  Future<void> onLoad() async {
    fieldRoot = PositionComponent();
    await add(fieldRoot);

    _background = BackgroundComponent(this);
    _pathComponent = PathComponent(this);
    _slotLayer = SlotLayerComponent(this);
    _tapCatcher = _FieldTapCatcher(this);
    _bossBanner = _BossBanner(this);

    await fieldRoot.addAll([
      _background,
      _tapCatcher,
      _pathComponent,
      _slotLayer,
      _bossBanner,
    ]);

    _ready = true;
    _relayout();
    state.slotCount = layout.slotCount;
    _recount();

    // 저장소 I/O가 게임 로딩을 막지 않도록 백그라운드로 돌린다.
    unawaited(_loadBestRecord());
  }

  @override
  void onGameResize(Vector2 size) {
    // Flame은 GameWidget이 다시 빌드될 때마다 이 메서드를 부른다.
    // 레이아웃 재계산은 비싸므로 크기가 실제로 달라졌을 때만 한다.
    final changed = size.x > 10 && size.y > 10 && _layout?.size != size;
    if (changed) {
      _layout = FieldLayout(size.clone());
    }
    super.onGameResize(size);
    if (_ready && changed) {
      _relayout();
    }
  }

  void _relayout() {
    final s = layout.size;
    _tapCatcher.size = s.clone();
    _background
      ..size = s.clone()
      ..rebuild();
    _slotLayer
      ..size = s.clone()
      ..rebuild();
    _pathComponent.rebuild();
    _bossBanner.position = Vector2(s.x / 2, layout.bandHeight * 0.42);
    _reindexSlots();
    for (final u in units) {
      u.syncToSlot();
    }
    state.slotCount = layout.slotCount;
    _hudDirty = true;
    // 인트로 중에는 _tick이 일찍 반환하므로 여기서 한 번 알려준다.
    state.notify();
  }

  /// 화면 크기가 바뀌어 슬롯 수가 달라졌을 때 유닛을 다시 배치한다.
  void _reindexSlots() {
    final capacity = layout.slotCount;
    final used = <int>{};
    for (final u in units) {
      if (u.slotIndex >= 0 && u.slotIndex < capacity && used.add(u.slotIndex)) {
        continue;
      }
      u.slotIndex = -1;
    }
    for (final u in units) {
      if (u.slotIndex != -1) {
        continue;
      }
      var placed = false;
      for (var i = 0; i < capacity; i++) {
        if (used.add(i)) {
          u.slotIndex = i;
          placed = true;
          break;
        }
      }
      if (!placed) {
        u.slotIndex = capacity - 1;
      }
    }
  }

  // ───────────────────────────── 루프 ─────────────────────────────
  @override
  void update(double dt) {
    if (state.paused) {
      // 시간만 멈춘다. dt 0 으로 한 번 돌려서 대기 중인 컴포넌트 추가·제거는
      // 처리해 준다 — 아예 건너뛰면 마침 그 프레임에 죽은 몬스터가 화면에
      // 그대로 남고, 멈춘 채로 붙은 컴포넌트는 아예 뜨지 않는다.
      super.update(0);
      return;
    }
    final base = math.min(dt, 1 / 30);
    final steps = state.speedMultiplier.clamp(1, 3);
    for (var i = 0; i < steps; i++) {
      _tick(base);
      super.update(base);
    }
  }

  void _tick(double dt) {
    state.tickToast(dt);
    _damageTextBudget = math.min(20, _damageTextBudget + dt * 45);
    _updateShake(dt);

    if (!state.started || state.isFinished) {
      return;
    }

    if (state.autoMerge) {
      var merges = 0;
      // 도박(어려움의 초월 합성)은 자동으로 걸지 않는다. 거는 판단은 플레이어 몫.
      while (merges < 3 && mergeOnce(certainOnly: true)) {
        merges++;
      }
    }

    if (_pendingSpawns > 0) {
      _spawnTimer -= dt;
      while (_pendingSpawns > 0 && _spawnTimer <= 0) {
        _spawnEnemy();
        _pendingSpawns--;
        _spawnTimer += math.max(0.05, _spawnInterval);
      }
    }

    state.waveCountdown -= dt;
    if (state.waveCountdown <= 0) {
      if (state.isFinalWave) {
        // 클리어 모드의 마지막 웨이브. 다음 웨이브는 없다.
        state.waveCountdown = 1;
      } else {
        _startWave();
      }
    }

    // 마지막 웨이브를 남김없이 처리하면 클리어.
    if (state.isFinalWave && _pendingSpawns == 0 && enemies.isEmpty) {
      _clearGame();
      return;
    }

    _hudTimer -= dt;
    if (_hudDirty || _hudTimer <= 0) {
      _hudTimer = 0.1;
      _hudDirty = false;
      _syncHud();
    }
  }

  void _updateShake(double dt) {
    if (_shakeTime <= 0) {
      if (fieldRoot.position.length2 != 0) {
        fieldRoot.position.setZero();
      }
      return;
    }
    _shakeTime -= dt;
    final k =
        _shakeMagnitude *
        math.max(0, _shakeTime / 0.35) *
        layout.bandHeight *
        0.16;
    fieldRoot.position.setValues(
      (rng.nextDouble() - 0.5) * k * 2,
      (rng.nextDouble() - 0.5) * k * 2,
    );
  }

  void shake(double magnitude) {
    _shakeTime = 0.35;
    _shakeMagnitude = magnitude;
  }

  void _syncHud() {
    state.unitCount = units.length;
    state.bossName = boss?.kind.name;
    state.bossHpRatio = boss?.hpRatio ?? 0;
    state.notify();
  }

  // ───────────────────────────── 웨이브 ─────────────────────────────
  void _startWave() {
    state.wave++;
    state.phase = GamePhase.playing;
    state.waveCountdown = Balance.waveInterval;

    final w = state.wave;
    final isBoss = w % Balance.bossEvery == 0;
    final isRush = !isBoss && w % Balance.rushEvery == 0;

    final income = (Balance.clearGold(w) * state.goldMultiplier).round();
    state.gold += income;

    final center = Vector2(layout.size.x / 2, layout.size.y * 0.40);

    if (isBoss) {
      final kind = bossForWave(w);
      _spawnKind = kind;
      _spawnHp = _hpAt(w) * Balance.bossHpMultiplier;
      _spawnLap = Balance.lapSeconds(w) * Balance.bossLapMultiplier;
      _spawnIsBoss = true;
      _pendingSpawns = 1;
      _spawnInterval = 0;
      fieldRoot.add(
        WaveBanner(
          kind.name,
          'BOSS · WAVE $w',
          const Color(0xFFFF5C6E),
          center,
        ),
      );
      shake(0.5);
    } else {
      final kind = mobForWave(w);
      _spawnKind = kind;
      _spawnHp = _hpAt(w) * (isRush ? Balance.rushHpMultiplier : 1.0);
      _spawnLap =
          Balance.lapSeconds(w) * (isRush ? Balance.rushLapMultiplier : 1.0);
      _spawnIsBoss = false;
      final count =
          (Balance.enemyCount(w) * (isRush ? Balance.rushCountMultiplier : 1.0))
              .round();
      _pendingSpawns = count;
      _spawnInterval = math.min(0.55, Balance.waveInterval * 0.62 / count);
      fieldRoot.add(
        WaveBanner(
          isRush ? '러시 웨이브' : 'WAVE $w',
          isRush ? '${kind.name} 대군 · 고속' : kind.name,
          isRush ? const Color(0xFFFFC44D) : const Color(0xFF8FA3FF),
          center,
        ),
      );
    }
    _spawnTimer = 0;
    _hudDirty = true;
  }

  double _hpAt(int wave) => Balance.enemyHp(wave, state.mode);

  void _spawnEnemy() {
    final kind = _spawnKind;
    if (kind == null) {
      return;
    }
    final e = EnemyComponent(
      game: this,
      kind: kind,
      maxHp: _spawnHp,
      lapSeconds: _spawnLap,
      wave: state.wave,
      isBoss: _spawnIsBoss,
    )..position.setFrom(layout.spawnPoint);
    enemies.add(e);
    fieldRoot.add(e);
    if (_spawnIsBoss) {
      boss = e;
      state.bossName = kind.name;
    }
  }

  // ───────────────────────────── 전투 ─────────────────────────────
  EnemyComponent? findTarget(Vector2 from, double range) {
    final r2 = range * range;
    EnemyComponent? best;
    var bestProgress = -1.0;
    for (final e in enemies) {
      if (e.dead) {
        continue;
      }
      if (e.position.distanceToSquared(from) > r2) {
        continue;
      }
      if (e.progress > bestProgress) {
        bestProgress = e.progress;
        best = e;
      }
    }
    return best;
  }

  EnemyComponent? _nearestExcluding(
    Vector2 from,
    double range,
    List<EnemyComponent> exclude,
  ) {
    final r2 = range * range;
    EnemyComponent? best;
    var bestDist = double.infinity;
    for (final e in enemies) {
      if (e.dead || exclude.contains(e)) {
        continue;
      }
      final d = e.position.distanceToSquared(from);
      if (d <= r2 && d < bestDist) {
        bestDist = d;
        best = e;
      }
    }
    return best;
  }

  void fireAt(UnitComponent unit, EnemyComponent target) {
    final spec = unit.spec;
    final origin = unit.position.clone();
    fieldRoot.add(
      ProjectileComponent(
        game: this,
        origin: origin,
        target: target,
        style: spec.style,
        color: spec.style == AttackStyle.single
            ? spec.rarity.color
            : spec.style.color,
        speed: layout.bandHeight * 9,
        radius: math.max(2.5, layout.bandHeight * 0.055),
        onHit: (hitPos, victim) => _applyHit(spec, origin, hitPos, victim),
      ),
    );
  }

  void _applyHit(
    UnitSpec spec,
    Vector2 origin,
    Vector2 hitPos,
    EnemyComponent? victim,
  ) {
    if (victim == null || victim.dead) {
      return;
    }
    final damage = spec.damage * state.damageMultiplierOf(spec.rarity);
    final accent = spec.style.color;

    switch (spec.style) {
      case AttackStyle.single:
        victim.takeDamage(damage, by: spec.id);

      case AttackStyle.splash:
        final radius = spec.param * layout.bandHeight;
        fieldRoot.add(SplashRing(hitPos, radius, spec.rarity.color));
        final r2 = radius * radius;
        for (final e in List<EnemyComponent>.of(enemies)) {
          if (e.dead) {
            continue;
          }
          final d2 = e.position.distanceToSquared(hitPos);
          if (d2 > r2) {
            continue;
          }
          final falloff = 1 - 0.45 * (math.sqrt(d2) / radius);
          e.takeDamage(
            damage * falloff,
            color: accent,
            showText: identical(e, victim),
            by: spec.id,
          );
        }

      case AttackStyle.slow:
        victim
          ..takeDamage(damage, color: accent, by: spec.id)
          ..applySlow(spec.param, kSlowDuration);

      case AttackStyle.poison:
        victim
          ..takeDamage(damage, color: accent, by: spec.id)
          ..applyPoison(damage * spec.param, kPoisonDuration, by: spec.id);

      case AttackStyle.chain:
        final maxTargets = spec.param.toInt();
        final chainRange = layout.bandHeight * 1.15;
        final hit = <EnemyComponent>[];
        final points = <Vector2>[origin.clone()];
        var current = victim;
        var currentDamage = damage;
        while (hit.length < maxTargets) {
          hit.add(current);
          points.add(current.position.clone());
          current.takeDamage(
            currentDamage,
            color: accent,
            showText: hit.length <= 2,
            by: spec.id,
          );
          currentDamage *= 0.84;
          final next = _nearestExcluding(current.position, chainRange, hit);
          if (next == null) {
            break;
          }
          current = next;
        }
        if (points.length >= 2) {
          fieldRoot.add(ChainLightning(points, accent));
        }

      case AttackStyle.execute:
        victim.takeDamage(damage, color: accent, by: spec.id);
        if (!victim.dead && !victim.isBoss && rng.nextDouble() < spec.param) {
          victim.execute(by: spec.id);
        }

      case AttackStyle.greed:
        victim.takeDamage(damage, color: accent, by: spec.id);
        if (rng.nextDouble() < spec.param) {
          final bonus = math.max(
            1,
            (Balance.killGold(math.max(1, state.wave)) *
                    0.9 *
                    state.goldMultiplier)
                .round(),
          );
          state.gold += bonus;
          _hudDirty = true;
          fieldRoot.add(
            FloatingText(
              '+$bonus',
              hitPos,
              color: const Color(0xFFFFD34E),
              fontSize: math.max(10, layout.bandHeight * 0.18),
              rise: layout.bandHeight * 0.5,
            ),
          );
        }
    }
  }

  void spawnDamageText(Vector2 at, double amount, Color color) {
    if (_damageTextBudget < 1) {
      return;
    }
    _damageTextBudget -= 1;
    fieldRoot.add(
      FloatingText(
        formatNumber(amount),
        at,
        color: color,
        fontSize: math.max(10, layout.bandHeight * 0.19),
        rise: layout.bandHeight * 0.55,
        duration: 0.6,
      ),
    );
  }

  void spawnExecuteText(Vector2 at) {
    fieldRoot.add(
      FloatingText(
        '처형!',
        at,
        color: const Color(0xFFFF6B8A),
        fontSize: math.max(12, layout.bandHeight * 0.24),
        rise: layout.bandHeight * 0.7,
        duration: 0.9,
      ),
    );
  }

  /// [by] 는 마지막 일격을 넣은 유닛의 도감 id. 유닛별 킬 수를 세는 데 쓴다.
  void onEnemyKilled(EnemyComponent e, {String? by}) {
    if (e.dead && !enemies.contains(e)) {
      return;
    }
    e.dead = true;
    enemies.remove(e);
    e.removeFromParent();
    if (identical(boss, e)) {
      boss = null;
      state.bossName = null;
    }

    fieldRoot.add(
      BurstEffect(
        e.position,
        e.kind.color,
        count: e.isBoss ? 28 : 9,
        speed: layout.bandHeight * (e.isBoss ? 3.2 : 1.6),
        size: layout.bandHeight * (e.isBoss ? 0.08 : 0.05),
      ),
    );

    state.totalKills++;
    if (by != null) {
      state.killsByUnit.update(by, (v) => v + 1, ifAbsent: () => 1);
    }
    if (e.isBoss) {
      final gold = (Balance.bossGold(e.wave) * state.goldMultiplier).round();
      final gems = Balance.bossGems(e.wave);
      state.gold += gold;
      state.gems += gems;
      fieldRoot.add(
        FloatingText(
          '보스 격파!  +$gold G  +$gems 💎',
          e.position,
          color: const Color(0xFFFFD34E),
          fontSize: math.max(13, layout.bandHeight * 0.26),
          rise: layout.bandHeight,
          duration: 1.6,
        ),
      );
      shake(0.55);
    } else {
      state.gold += (Balance.killGold(e.wave) * state.goldMultiplier).round();
    }
    _hudDirty = true;
  }

  void onEnemyReachedBase(EnemyComponent e) {
    if (e.dead && !enemies.contains(e)) {
      return;
    }
    e.dead = true;
    enemies.remove(e);
    e.removeFromParent();
    if (identical(boss, e)) {
      boss = null;
      state.bossName = null;
    }

    final cost = e.isBoss ? Balance.bossLifeCost : 1;
    state.lives = math.max(0, state.lives - cost);
    shake(e.isBoss ? 0.7 : 0.28);
    fieldRoot.add(
      FloatingText(
        '-$cost ❤️',
        layout.basePoint,
        color: const Color(0xFFFF5C6E),
        fontSize: math.max(12, layout.bandHeight * 0.24),
        rise: layout.bandHeight * 0.7,
        duration: 0.9,
      ),
    );
    if (state.lives <= 0) {
      _gameOver();
    }
    _hudDirty = true;
  }

  /// 일시정지 토글.
  void togglePause() {
    if (!state.started || state.isFinished) {
      return;
    }
    state.paused = !state.paused;
    state.notify();
  }

  /// 인트로를 닫고 전투를 시작한다.
  void startGame() {
    state.started = true;
    state.phase = GamePhase.playing;
    state.notify();
  }

  /// 클리어 모드에서 마지막 웨이브까지 막아냈다.
  void _clearGame() {
    state.phase = GamePhase.cleared;
    _pendingSpawns = 0;
    submitRecord();
    shake(0.45);
    fieldRoot.add(
      WaveBanner(
        '정복 완료',
        'WAVE ${Balance.clearWave(state.mode)} CLEAR',
        const Color(0xFFFFD34E),
        Vector2(layout.size.x / 2, layout.size.y * 0.40),
      ),
    );
    state.notify();
  }

  /// 인트로에서 플레이 방식을 고른다.
  void setMode(GameMode mode) {
    if (state.mode == mode) {
      return;
    }
    state.mode = mode;
    state.notify();
  }

  void _gameOver() {
    state.phase = GamePhase.gameOver;
    _pendingSpawns = 0;
    submitRecord();
    state.notify();
  }

  /// 이번 판 성적을 모드 랭킹에 올린다.
  ///
  /// 한 판에 한 번만 받는다 — 결과 화면이 떠 있는 동안 여러 번 누르면 같은
  /// 기록이 여러 줄로 쌓인다. 이름은 [normalizeRankName] 을 통과해야 한다.
  Future<bool> submitRank(String rawName) async {
    final name = normalizeRankName(rawName);
    if (name == null ||
        state.rankSubmitted ||
        !state.mode.hasRanking ||
        state.wave <= 0) {
      return false;
    }
    final ok = await leaderboard.submit(
      state.mode,
      RankEntry(name: name, wave: state.wave, achievedAt: DateTime.now()),
    );
    if (ok) {
      state.rankSubmitted = true;
      state.notify();
      unawaited(saveRankName(name));
    }
    return ok;
  }

  Future<void> _loadBestRecord() async {
    state.best = await _records.load();
    state.notify();
  }

  /// 이번 판 성적을 최고 기록과 견주어 갱신한다.
  ///
  /// 게임오버뿐 아니라 앱이 백그라운드로 갈 때도 불러서,
  /// 죽지 않고 앱을 닫아도 진행도가 남게 한다.
  void submitRecord() {
    if (state.wave <= 0) {
      return;
    }
    final candidate = BestRecord(
      wave: state.wave,
      kills: state.totalKills,
      rarityTier: state.bestRarityTier,
      summons: state.totalSummons,
      merges: state.totalMerges,
      achievedAt: DateTime.now(),
    );
    if (!candidate.isBetterThan(state.best)) {
      return;
    }
    state.best = candidate;
    state.isNewRecord = true;
    unawaited(_records.save(candidate));
  }

  // ───────────────────────────── 유닛 관리 ─────────────────────────────
  int _firstFreeSlot() {
    final used = <int>{for (final u in units) u.slotIndex};
    for (var i = 0; i < layout.slotCount; i++) {
      if (!used.contains(i)) {
        return i;
      }
    }
    return -1;
  }

  void _recount() {
    unitCounts.clear();
    for (final u in units) {
      unitCounts.update(u.spec.id, (v) => v + 1, ifAbsent: () => 1);
    }
    state.unitCount = units.length;

    final sacrifice = _autoSellCandidate();
    state.autoSellName = sacrifice?.spec.name;
    state.autoSellRarity = sacrifice?.spec.rarity;
    state.autoSellRefund = sacrifice?.spec.sellPrice ?? 0;

    // 고급소환이 무엇을 줄지. 자리가 없으면 자동 판매가 먼저 일어나므로,
    // 그 유닛을 뺀 보드로 계산해야 실제로 나오는 것과 같아진다.
    final specs = [for (final u in units) u.spec];
    if (sacrifice != null && units.length >= layout.slotCount) {
      specs.remove(sacrifice.spec);
    }
    final target = pickHighSummonTarget(specs);
    state.highSummonName = target?.name;
    state.highSummonEmoji = target?.emoji;
    state.highSummonRarity = target?.rarity;

    var groups = 0;
    unitCounts.forEach((id, count) {
      final spec = kUnitById[id];
      if (spec != null && spec.rarity.next != null) {
        groups += count ~/ Balance.mergeCount;
      }
    });
    state.mergeableGroups = groups;
  }

  void _addUnit(UnitSpec spec, int slot, {bool announce = false}) {
    final unit = UnitComponent(game: this, spec: spec, slotIndex: slot);
    units.add(unit);
    fieldRoot.add(unit);
    _recount();
    if (spec.rarity.index > state.bestRarityTier) {
      state.bestRarityTier = spec.rarity.index;
    }
    if (announce) {
      fieldRoot.add(
        SummonFlash(
          layout.slotCenters[slot],
          spec.rarity.label,
          spec.name,
          spec.rarity.color,
          spec.rarity.index,
        ),
      );
      if (spec.rarity.index >= Rarity.epic.index) {
        shake(0.3);
        fieldRoot.add(
          BurstEffect(
            layout.slotCenters[slot],
            spec.rarity.color,
            count: 18,
            speed: layout.bandHeight * 2.2,
            size: layout.bandHeight * 0.06,
          ),
        );
      }
    }
    _hudDirty = true;
  }

  void _destroyUnit(UnitComponent unit) {
    units.remove(unit);
    unit.removeFromParent();
    if (identical(selected, unit)) {
      selected = null;
    }
  }

  /// 자리가 없을 때 대신 팔려 나갈 유닛. 규칙은 [pickAutoSellIndex] 참고.
  UnitComponent? _autoSellCandidate() {
    if (units.isEmpty) {
      return null;
    }
    final index = pickAutoSellIndex(
      units.map((u) => u.spec).toList(growable: false),
    );
    return index < 0 ? null : units[index];
  }

  /// 자리를 비우려고 한 기를 판다. 어떤 유닛이 나갔는지 눈에 보이게 알린다.
  void _autoSell(UnitComponent unit) {
    final spec = unit.spec;
    fieldRoot.add(
      BurstEffect(
        unit.position,
        spec.rarity.color,
        count: 12,
        speed: layout.bandHeight * 1.5,
        size: layout.bandHeight * 0.05,
      ),
    );
    sellUnit(unit);
    state.showToast(
      '자리가 없어 ${spec.name} 자동 판매  +${formatNumber(spec.sellPrice)} G',
      color: 0xFFFFD34E,
    );
  }

  bool summon() {
    if (state.isFinished) {
      return false;
    }

    var slot = _firstFreeSlot();
    UnitComponent? sacrifice;
    var cost = state.summonCost;

    if (slot < 0 && state.autoSell) {
      sacrifice = _autoSellCandidate();
      if (sacrifice == null) {
        state.showToast('빈 슬롯이 없습니다 · 합성하거나 판매하세요', color: 0xFFFFC44D);
        return false;
      }
      // 한 기를 팔면 보유 수가 줄어 소환 비용도 함께 내려간다.
      cost = Balance.summonCost(units.length - 1);
      if (state.gold + sacrifice.spec.sellPrice < cost) {
        // 팔아도 모자라면 아예 팔지 않는다. 손해만 보고 끝나면 안 된다.
        state.showToast('골드가 부족합니다', color: 0xFFFF5C6E);
        return false;
      }
    } else if (slot < 0) {
      state.showToast('빈 슬롯이 없습니다 · 합성하거나 판매하세요', color: 0xFFFFC44D);
      return false;
    } else if (state.gold < cost) {
      state.showToast('골드가 부족합니다', color: 0xFFFF5C6E);
      return false;
    }

    if (sacrifice != null) {
      slot = sacrifice.slotIndex;
      _autoSell(sacrifice);
    }

    state.gold -= cost;
    state.totalSummons++;
    _addUnit(rollSummon(rng, state.luckLevel), slot, announce: true);
    return true;
  }

  bool highSummon() {
    if (state.isFinished) {
      return false;
    }
    if (state.gems < Balance.highSummonGems) {
      state.showToast('다이아가 부족합니다', color: 0xFFFF5C6E);
      return false;
    }

    var slot = _firstFreeSlot();
    if (slot < 0) {
      final sacrifice = state.autoSell ? _autoSellCandidate() : null;
      if (sacrifice == null) {
        state.showToast('빈 슬롯이 없습니다 · 합성하거나 판매하세요', color: 0xFFFFC44D);
        return false;
      }
      slot = sacrifice.slotIndex;
      _autoSell(sacrifice);
    }

    state.gems -= Balance.highSummonGems;
    state.totalSummons++;
    // 자리를 비운 «뒤» 의 보드로 겨냥한다. 미리 보기도 같은 기준이라 어긋나지 않는다.
    final target = pickHighSummonTarget([for (final u in units) u.spec]);
    _addUnit(
      target ?? rollHighSummon(rng, state.luckLevel),
      slot,
      announce: true,
    );
    return true;
  }

  /// 보드에 [spec] 을 [count] 기 올려 둔다. 빈 자리가 없으면 거기서 멈춘다.
  ///
  /// 소환은 무작위라 신화 같은 고등급을 손에 넣으려면 합성을 몇 겹씩 거쳐야
  /// 한다. 합성 규칙 자체를 검증하려면 보드를 직접 꾸밀 수 있어야 한다.
  @visibleForTesting
  void placeUnits(UnitSpec spec, int count) {
    for (var i = 0; i < count; i++) {
      final slot = _firstFreeSlot();
      if (slot < 0) {
        return;
      }
      _addUnit(spec, slot);
    }
  }

  /// 지금 합성할 수 있는 유닛. [certainOnly] 면 확정 합성만 고른다.
  String? _firstMergeableId({bool certainOnly = false}) {
    String? found;
    unitCounts.forEach((id, count) {
      if (found != null) {
        return;
      }
      final spec = kUnitById[id];
      if (spec != null &&
          spec.rarity.next != null &&
          count >= Balance.mergeCount &&
          (!certainOnly || mergeChanceOf(spec) >= 1)) {
        found = id;
      }
    });
    return found;
  }

  /// [spec] 3개를 합성했을 때의 성공 확률. 1 이면 확정이다.
  double mergeChanceOf(UnitSpec spec) =>
      Balance.mergeChance(spec.rarity.index, state.mode);

  /// 같은 유닛 3개를 모아 다음 등급 유닛 1개로 만든다.
  ///
  /// 어려움에서 신화를 초월로 올릴 때만 도박이 된다([Balance.mergeChance]).
  /// 실패하면 재료가 [Balance.mergeFailLoss] 개 사라지고 아무것도 나오지 않는다.
  /// 자동 합성은 확정 합성만 하므로, 걸지 말지는 늘 플레이어가 고른다.
  bool mergeOnce({String? specId, bool certainOnly = false}) {
    final id = specId ?? _firstMergeableId(certainOnly: certainOnly);
    if (id == null) {
      return false;
    }
    final group = units.where((u) => u.spec.id == id).toList();
    if (group.length < Balance.mergeCount) {
      return false;
    }
    final next = group.first.spec.rarity.next;
    if (next == null) {
      return false;
    }

    final chance = mergeChanceOf(group.first.spec);
    final failed = chance < 1 && rng.nextDouble() >= chance;
    final slot = group.first.slotIndex;
    final burned = failed ? Balance.mergeFailLoss : Balance.mergeCount;
    for (var i = 0; i < burned; i++) {
      _destroyUnit(group[i]);
    }
    _recount();

    if (failed) {
      state.failedMerges++;
      state.showToast(
        '합성 실패 · ${group.first.spec.name} $burned기 소멸',
        color: 0xFFFF5C6E,
      );
      fieldRoot.add(
        FloatingText(
          '실패',
          layout.slotCenters[slot],
          color: const Color(0xFFFF5C6E),
          fontSize: math.max(12, layout.bandHeight * 0.24),
          rise: layout.bandHeight * 0.6,
        ),
      );
      fieldRoot.add(
        BurstEffect(
          layout.slotCenters[slot],
          const Color(0xFFFF5C6E),
          count: 10,
          speed: layout.bandHeight * 1.2,
          size: layout.bandHeight * 0.04,
        ),
      );
      return true;
    }

    _addUnit(randomOfRarity(rng, next), slot, announce: true);
    state.totalMerges++;
    fieldRoot.add(
      BurstEffect(
        layout.slotCenters[slot],
        next.color,
        count: 16,
        speed: layout.bandHeight * 1.9,
        size: layout.bandHeight * 0.055,
      ),
    );
    return true;
  }

  void sellUnit(UnitComponent unit) {
    final price = unit.spec.sellPrice;
    state.gold += price;
    fieldRoot.add(
      FloatingText(
        '+$price',
        unit.position,
        color: const Color(0xFFFFD34E),
        fontSize: math.max(11, layout.bandHeight * 0.2),
        rise: layout.bandHeight * 0.5,
      ),
    );
    _destroyUnit(unit);
    _recount();
    _hudDirty = true;
  }

  /// 탭: 같은 유닛을 다시 누르면 선택 해제된다.
  void selectUnit(UnitComponent? unit) {
    selected = identical(selected, unit) ? null : unit;
    _hudDirty = true;
  }

  /// 드래그처럼 토글이 아니라 무조건 선택해야 할 때.
  void focusUnit(UnitComponent unit) {
    if (!identical(selected, unit)) {
      selected = unit;
      _hudDirty = true;
    }
  }

  void clearSelection() {
    if (selected != null) {
      selected = null;
      _hudDirty = true;
    }
  }

  void moveUnitToSlot(UnitComponent unit, int slot) {
    if (slot < 0 || slot >= layout.slotCount) {
      unit.syncToSlot();
      return;
    }
    UnitComponent? occupant;
    for (final u in units) {
      if (!identical(u, unit) && u.slotIndex == slot) {
        occupant = u;
        break;
      }
    }
    if (occupant != null) {
      occupant
        ..slotIndex = unit.slotIndex
        ..syncToSlot();
    }
    unit
      ..slotIndex = slot
      ..syncToSlot();
  }

  // ───────────────────────────── 강화 ─────────────────────────────
  bool upgradeAttack() => _buyGold(state.atkCost, () => state.atkLevel++);
  bool upgradeSpeed() => _buyGold(state.spdCost, () => state.spdLevel++);
  bool upgradeGold() => _buyGold(state.goldCost, () => state.goldLevel++);

  bool _buyGold(int cost, VoidCallback apply) {
    if (state.gold < cost) {
      state.showToast('골드가 부족합니다', color: 0xFFFF5C6E);
      return false;
    }
    state.gold -= cost;
    apply();
    _hudDirty = true;
    return true;
  }

  bool upgradeLuck() {
    if (state.luckMaxed) {
      state.showToast('행운 강화가 최대입니다');
      return false;
    }
    final cost = state.luckCost;
    if (state.gems < cost) {
      state.showToast('다이아가 부족합니다', color: 0xFFFF5C6E);
      return false;
    }
    state.gems -= cost;
    state.luckLevel++;
    _hudDirty = true;
    return true;
  }

  bool buyLife() {
    if (state.gems < Balance.reviveGems) {
      state.showToast('다이아가 부족합니다', color: 0xFFFF5C6E);
      return false;
    }
    state.gems -= Balance.reviveGems;
    state.lives += 1;
    _hudDirty = true;
    return true;
  }

  /// 판을 새로 시작한다. [toIntro] 면 플레이 방식을 다시 고르도록 인트로로 간다.
  void restart({bool toIntro = false}) {
    for (final c in fieldRoot.children.toList()) {
      final permanent =
          identical(c, _background) ||
          identical(c, _tapCatcher) ||
          identical(c, _pathComponent) ||
          identical(c, _slotLayer) ||
          identical(c, _bossBanner);
      if (!permanent) {
        c.removeFromParent();
      }
    }
    units.clear();
    enemies.clear();
    unitCounts.clear();
    selected = null;
    boss = null;
    dropTargetSlot = null;
    _pendingSpawns = 0;
    _spawnKind = null;
    _shakeTime = 0;
    fieldRoot.position.setZero();

    state.reset();
    if (toIntro) {
      state.started = false;
      state.phase = GamePhase.ready;
    }
    state.slotCount = layout.slotCount;
    _recount();
    _hudDirty = true;
  }
}

/// 빈 공간을 눌렀을 때 선택을 해제하기 위한 투명 레이어.
class _FieldTapCatcher extends PositionComponent with TapCallbacks {
  _FieldTapCatcher(this.game) : super(priority: -40);

  final LuckyDefenseGame game;

  @override
  void onTapDown(TapDownEvent event) => game.clearSelection();

  @override
  void render(Canvas canvas) {}
}

/// 상단 보스 체력 배너.
class _BossBanner extends PositionComponent {
  _BossBanner(this.game) : super(priority: 45, anchor: Anchor.center);

  final LuckyDefenseGame game;
  double _appear = 0;

  @override
  void update(double dt) {
    final visible = game.boss != null;
    _appear = (_appear + (visible ? dt * 4 : -dt * 4)).clamp(0.0, 1.0);
  }

  @override
  void render(Canvas canvas) {
    final b = game.boss;
    if (_appear <= 0.01 || b == null) {
      return;
    }
    final w = math.min(game.layout.size.x * 0.82, 420.0);
    const h = 40.0;
    final alpha = _appear;
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: w, height: h),
      const Radius.circular(12),
    );
    canvas.drawRRect(
      rect,
      Paint()..color = fadeColor(const Color(0xFF0E1322), alpha * 0.92),
    );
    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = fadeColor(const Color(0xFFFF5C6E), alpha * 0.8),
    );

    drawTextCentered(
      canvas,
      '${b.kind.emoji}  ${b.kind.name}',
      TextStyle(
        fontSize: 12,
        color: fadeColor(Colors.white, alpha),
        fontWeight: FontWeight.w800,
      ),
      const Offset(0, -9),
    );

    final barWidth = w - 28;
    final barRect = Rect.fromLTWH(-barWidth / 2, 5, barWidth, 9);
    canvas.drawRRect(
      RRect.fromRectAndRadius(barRect, const Radius.circular(5)),
      Paint()..color = fadeColor(Colors.black, alpha * 0.6),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-barWidth / 2, 5, barWidth * b.hpRatio, 9),
        const Radius.circular(5),
      ),
      Paint()..color = fadeColor(const Color(0xFFFF5C6E), alpha),
    );
  }
}
