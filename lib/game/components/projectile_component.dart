import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../data/unit_catalog.dart';
import '../lucky_defense_game.dart';
import 'enemy_component.dart';
import 'render_utils.dart';

/// 유닛이 발사하는 유도 투사체. 대상이 죽으면 근처의 다른 적을 재추적한다.
const _gloss = Color(0xB3FFFFFF);

class ProjectileComponent extends PositionComponent {
  ProjectileComponent({
    required this.game,
    required Vector2 origin,
    required this.target,
    required this.style,
    required this.color,
    required this.speed,
    required this.radius,
    required this.onHit,
  }) : super(position: origin.clone(), priority: 30, anchor: Anchor.center);

  final LuckyDefenseGame game;
  EnemyComponent? target;
  final AttackStyle style;
  final Color color;
  final double speed;
  final double radius;
  final void Function(Vector2 hitPosition, EnemyComponent? victim) onHit;

  double _angle = 0;
  double _life = 0;

  /// 꼬리 자취. 프레임마다 Vector2 를 새로 만들지 않도록 미리 잡아 두고
  /// 가장 오래된 칸을 덮어쓰며 돌려 쓴다([_trailHead] 가 최신).
  final List<Vector2> _trail = List.generate(5, (_) => Vector2.zero());
  int _trailLen = 0;
  int _trailHead = 0;

  /// 화살촉 모양. 반지름이 변하지 않으므로 한 번만 만든다 — CanvasKit 에서
  /// Path 도 네이티브 객체라, 프레임마다 만들면 그대로 쌓인다.
  late final Path _arrow = Path()
    ..moveTo(radius * 1.9, 0)
    ..lineTo(-radius * 1.1, radius * 0.85)
    ..lineTo(-radius * 0.4, 0)
    ..lineTo(-radius * 1.1, -radius * 0.85)
    ..close();

  @override
  void update(double dt) {
    if (game.state.paused) {
      return;
    }
    _life += dt;
    if (_life > 3) {
      removeFromParent();
      return;
    }

    var t = target;
    if (t == null || t.dead || t.isRemoved) {
      t = game.findTarget(position, game.layout.bandHeight * 2.4);
      if (t == null) {
        removeFromParent();
        return;
      }
      target = t;
    }

    _trailHead = (_trailHead - 1) % _trail.length;
    if (_trailHead < 0) {
      _trailHead += _trail.length;
    }
    _trail[_trailHead].setFrom(position);
    if (_trailLen < _trail.length) {
      _trailLen++;
    }

    final dir = t.position - position;
    final dist = dir.length;
    final step = speed * dt;
    _angle = math.atan2(dir.y, dir.x);

    if (dist <= step + t.radius * 0.4) {
      final hitPos = t.position.clone();
      position.setFrom(hitPos);
      onHit(hitPos, t);
      removeFromParent();
      return;
    }
    position.add(dir.normalized() * step);
  }

  @override
  void render(Canvas canvas) {
    // 오래된 것부터 그린다. 논리 0번이 가장 최근 위치다.
    for (var i = _trailLen - 1; i >= 0; i--) {
      final alpha = (1 - i / _trail.length) * 0.35;
      final p = _trail[(_trailHead + i) % _trail.length];
      canvas.drawCircle(
        Offset(p.x - position.x, p.y - position.y),
        radius * (1 - i / (_trail.length + 1)) * 0.8,
        fillPaint(fadeColor(color, alpha)),
      );
    }

    canvas.save();
    canvas.rotate(_angle);
    switch (style) {
      case AttackStyle.splash:
        canvas.drawCircle(
          Offset.zero,
          radius * 1.25,
          fillPaint(color.withValues(alpha: 0.35)),
        );
        canvas.drawCircle(Offset.zero, radius, fillPaint(color));
      case AttackStyle.chain:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset.zero,
              width: radius * 3.2,
              height: radius * 0.9,
            ),
            Radius.circular(radius * 0.45),
          ),
          fillPaint(color),
        );
      case AttackStyle.single:
      case AttackStyle.execute:
        canvas.drawPath(_arrow, fillPaint(color));
      case AttackStyle.slow:
      case AttackStyle.poison:
      case AttackStyle.greed:
        canvas.drawCircle(Offset.zero, radius, fillPaint(color));
        canvas.drawCircle(
          Offset(-radius * 0.3, -radius * 0.3),
          radius * 0.4,
          fillPaint(_gloss),
        );
    }
    canvas.restore();
  }
}
