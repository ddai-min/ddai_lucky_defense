import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../data/unit_catalog.dart';
import '../lucky_defense_game.dart';
import 'enemy_component.dart';
import 'render_utils.dart';

/// 유닛이 발사하는 유도 투사체. 대상이 죽으면 근처의 다른 적을 재추적한다.
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
  final List<Vector2> _trail = [];

  @override
  void update(double dt) {
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

    _trail.insert(0, position.clone());
    if (_trail.length > 5) {
      _trail.removeLast();
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
    for (var i = _trail.length - 1; i >= 0; i--) {
      final alpha = (1 - i / _trail.length) * 0.35;
      final p = _trail[i] - position;
      canvas.drawCircle(
        Offset(p.x, p.y),
        radius * (1 - i / (_trail.length + 1)) * 0.8,
        Paint()..color = fadeColor(color, alpha),
      );
    }

    canvas.save();
    canvas.rotate(_angle);
    switch (style) {
      case AttackStyle.splash:
        canvas.drawCircle(
          Offset.zero,
          radius * 1.25,
          Paint()..color = color.withValues(alpha: 0.35),
        );
        canvas.drawCircle(Offset.zero, radius, Paint()..color = color);
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
          Paint()..color = color,
        );
      case AttackStyle.single:
      case AttackStyle.execute:
        final p = Path()
          ..moveTo(radius * 1.9, 0)
          ..lineTo(-radius * 1.1, radius * 0.85)
          ..lineTo(-radius * 0.4, 0)
          ..lineTo(-radius * 1.1, -radius * 0.85)
          ..close();
        canvas.drawPath(p, Paint()..color = color);
      case AttackStyle.slow:
      case AttackStyle.poison:
      case AttackStyle.greed:
        canvas.drawCircle(Offset.zero, radius, Paint()..color = color);
        canvas.drawCircle(
          Offset(-radius * 0.3, -radius * 0.3),
          radius * 0.4,
          Paint()..color = Colors.white.withValues(alpha: 0.7),
        );
    }
    canvas.restore();
  }
}
