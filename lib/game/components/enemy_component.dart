import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../data/enemy_catalog.dart';
import '../lucky_defense_game.dart';
import 'render_utils.dart';

/// 경로를 따라 걷는 몬스터.
/// 프레임마다 `withValues` 로 다시 만들 이유가 없는 색들.
const _shadow = Color(0x52000000);
const _outline = Color(0x73000000);
const _slowRing = Color(0xD97FD8FF);
const _poisonDot = Color(0xD98BE36B);
const _hpBarBg = Color(0x99000000);

class EnemyComponent extends PositionComponent {
  EnemyComponent({
    required this.game,
    required this.kind,
    required this.maxHp,
    required this.lapSeconds,
    required this.wave,
    this.isBoss = false,
  }) : super(priority: 10, anchor: Anchor.center) {
    hp = maxHp;
    _phase = game.rng.nextDouble() * math.pi * 2;
    _lane = (game.rng.nextDouble() - 0.5);
  }

  final LuckyDefenseGame game;
  final EnemyKind kind;
  final double maxHp;

  /// 한 바퀴를 도는 데 걸리는 시간(초).
  final double lapSeconds;
  final int wave;
  final bool isBoss;

  late double hp;

  /// 경로 진행도 0.0 ~ 1.0.
  double progress = 0;
  bool dead = false;

  double _speedFactor = 1;
  double _slowTimer = 0;
  double _slowAmount = 0;
  double _poisonDps = 0;
  String? _poisonBy;
  double _poisonTimer = 0;
  double _hitFlash = 0;
  double _phase = 0;
  double _lane = 0;
  double _spawnPop = 0;

  double get radius => game.layout.bandHeight * (isBoss ? 0.40 : 0.24);
  double get pathDistance => progress * game.layout.path.length;
  double get hpRatio => (hp / maxHp).clamp(0.0, 1.0);
  bool get isSlowed => _slowTimer > 0;
  bool get isPoisoned => _poisonTimer > 0;

  @override
  void update(double dt) {
    if (dead) {
      return;
    }
    _spawnPop = math.min(1, _spawnPop + dt * 5);
    _phase += dt * 6;
    _hitFlash = math.max(0, _hitFlash - dt * 5);

    if (_slowTimer > 0) {
      _slowTimer -= dt;
      if (_slowTimer <= 0) {
        _slowAmount = 0;
        _speedFactor = 1;
      }
    }
    if (_poisonTimer > 0) {
      _poisonTimer -= dt;
      takeDamage(
        _poisonDps * dt,
        color: const Color(0xFF8BE36B),
        showText: false,
        by: _poisonBy,
      );
      if (dead) {
        return;
      }
      if (_poisonTimer <= 0) {
        _poisonDps = 0;
      }
    }

    progress += dt / lapSeconds * _speedFactor;
    if (progress >= 1) {
      progress = 1;
      game.onEnemyReachedBase(this);
      return;
    }

    final path = game.layout.path;
    final p = path.positionAt(pathDistance);
    final t = path.tangentAt(pathDistance);
    // 같은 자리에 겹치지 않도록 경로 옆으로 살짝 흩뿌린다.
    final offset = game.layout.pathWidth * 0.26 * _lane;
    position
      ..x = p.x - t.y * offset
      ..y = p.y + t.x * offset;
  }

  /// [by] 는 때린 유닛의 도감 id. 마지막 일격을 넣은 유닛에게 킬이 붙는다.
  void takeDamage(
    double amount, {
    Color color = Colors.white,
    bool showText = true,
    String? by,
  }) {
    if (dead || amount <= 0) {
      return;
    }
    hp -= amount;
    _hitFlash = 1;
    if (showText) {
      game.spawnDamageText(position, amount, color);
    }
    if (hp <= 0) {
      hp = 0;
      game.onEnemyKilled(this, by: by);
    }
  }

  /// 즉사(처형). 보스에게는 적용되지 않는다.
  void execute({String? by}) {
    if (dead || isBoss) {
      return;
    }
    hp = 0;
    game.spawnExecuteText(position);
    game.onEnemyKilled(this, by: by);
  }

  void applySlow(double amount, double duration) {
    if (dead) {
      return;
    }
    if (amount >= _slowAmount) {
      _slowAmount = amount;
      _speedFactor = (1 - amount).clamp(0.2, 1.0);
    }
    _slowTimer = math.max(_slowTimer, duration);
  }

  /// 중독은 시간이 지나 터지므로, 건 유닛을 기억해 뒀다가 킬을 돌려준다.
  /// 더 센 중독이 덮어쓰면 출처도 같이 바뀐다.
  void applyPoison(double dps, double duration, {String? by}) {
    if (dead) {
      return;
    }
    if (dps >= _poisonDps) {
      _poisonDps = dps;
      _poisonBy = by;
    }
    _poisonTimer = math.max(_poisonTimer, duration);
  }

  @override
  void render(Canvas canvas) {
    final r = radius * (0.5 + 0.5 * _spawnPop);
    final bob = math.sin(_phase) * r * 0.08;

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(0, r * 0.95),
        width: r * 1.7,
        height: r * 0.5,
      ),
      fillPaint(_shadow),
    );

    canvas.save();
    canvas.translate(0, bob);

    if (isBoss) {
      canvas.drawCircle(
        Offset.zero,
        r * 1.45,
        blurPaint(kind.color.withValues(alpha: 0.35), 10),
      );
    }

    canvas.drawCircle(
      Offset.zero,
      r,
      shaderPaint(orbShader(kind.color, r)),
    );

    canvas.drawCircle(
      Offset.zero,
      r,
      strokePaint(_outline, isBoss ? 3 : 1.6),
    );

    drawTextCentered(
      canvas,
      kind.emoji,
      TextStyle(fontSize: r * 1.25),
      Offset(0, -r * 0.02),
    );

    if (_hitFlash > 0) {
      canvas.drawCircle(
        Offset.zero,
        r,
        fillPaint(fadeColor(Colors.white, _hitFlash * 0.6)),
      );
    }
    if (isSlowed) {
      canvas.drawCircle(
        Offset.zero,
        r * 1.16,
        strokePaint(_slowRing, 2),
      );
    }
    if (isPoisoned) {
      for (var i = 0; i < 3; i++) {
        final a = _phase * 0.6 + i * 2.1;
        canvas.drawCircle(
          Offset(math.cos(a) * r * 0.9, math.sin(a) * r * 0.7 - r * 0.5),
          r * 0.16,
          fillPaint(_poisonDot),
        );
      }
    }
    canvas.restore();

    _drawHpBar(canvas, r);
  }

  void _drawHpBar(Canvas canvas, double r) {
    if (hpRatio >= 1 && !isBoss) {
      return;
    }
    final w = r * (isBoss ? 2.6 : 2.2);
    final h = isBoss ? 6.0 : 4.0;
    final top = -r - h - 5;
    final bg = RRect.fromRectAndRadius(
      Rect.fromLTWH(-w / 2, top, w, h),
      Radius.circular(h / 2),
    );
    canvas.drawRRect(bg, fillPaint(_hpBarBg));
    final fillColor = hpRatio > 0.5
        ? const Color(0xFF5BD98A)
        : hpRatio > 0.22
        ? const Color(0xFFFFC44D)
        : const Color(0xFFFF5C6E);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-w / 2, top, w * hpRatio, h),
        Radius.circular(h / 2),
      ),
      fillPaint(fillColor),
    );
  }
}
