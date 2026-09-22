import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import 'render_utils.dart';

const int kFxPriority = 40;

/// 위로 떠오르며 사라지는 숫자/문구.
class FloatingText extends PositionComponent {
  FloatingText(
    this.text,
    Vector2 at, {
    this.color = Colors.white,
    this.fontSize = 14,
    this.rise = 34,
    this.duration = 0.75,
    this.bold = true,
  }) : super(position: at.clone(), priority: kFxPriority + 5);

  final String text;
  final Color color;
  final double fontSize;
  final double rise;
  final double duration;
  final bool bold;

  double _t = 0;

  @override
  void update(double dt) {
    _t += dt;
    if (_t >= duration) {
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    final p = (_t / duration).clamp(0.0, 1.0);
    final alpha = p < 0.65 ? 1.0 : 1 - (p - 0.65) / 0.35;
    final scale = 1 + 0.25 * math.sin(math.min(p, 0.35) / 0.35 * math.pi / 2);
    drawTextCentered(
      canvas,
      text,
      TextStyle(
        fontSize: fontSize * scale,
        color: fadeColor(color, alpha),
        fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
        letterSpacing: -0.3,
      ),
      Offset(0, -rise * Curves.easeOut.transform(p)),
    );
  }
}

/// 광역 공격 폭발 링.
class SplashRing extends PositionComponent {
  SplashRing(Vector2 at, this.radius, this.color)
    : super(position: at.clone(), priority: kFxPriority);

  final double radius;
  final Color color;
  double _t = 0;
  static const double _duration = 0.32;

  @override
  void update(double dt) {
    _t += dt;
    if (_t >= _duration) {
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    final p = (_t / _duration).clamp(0.0, 1.0);
    final r = radius * Curves.easeOutCubic.transform(p);
    final alpha = 1 - p;
    canvas.drawCircle(
      Offset.zero,
      r,
      fillPaint(fadeColor(color, alpha * 0.22)),
    );
    canvas.drawCircle(
      Offset.zero,
      r,
      strokePaint(fadeColor(color, alpha), 3 * (1 - p) + 1),
    );
  }
}

/// 연쇄 번개.
class ChainLightning extends PositionComponent {
  ChainLightning(this.points, this.color) : super(priority: kFxPriority + 2);

  final List<Vector2> points;
  final Color color;
  double _t = 0;
  static const double _duration = 0.22;
  final math.Random _rng = math.Random();
  late final List<Offset> _jagged = _buildJagged();

  /// 꺾은선 모양은 변하지 않는다. Path 는 네이티브 객체라 프레임마다 만들면
  /// 그대로 쌓이므로 한 번만 만들어 둔다.
  late final Path _path = () {
    final path = Path();
    if (_jagged.isNotEmpty) {
      path.moveTo(_jagged.first.dx, _jagged.first.dy);
      for (var i = 1; i < _jagged.length; i++) {
        path.lineTo(_jagged[i].dx, _jagged[i].dy);
      }
    }
    return path;
  }();

  List<Offset> _buildJagged() {
    final out = <Offset>[];
    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];
      final dir = b - a;
      final len = dir.length;
      final normal = Vector2(-dir.y, dir.x)..normalize();
      const steps = 5;
      for (var s = 0; s <= steps; s++) {
        final t = s / steps;
        final base = a + dir * t;
        final jitter = (s == 0 || s == steps)
            ? 0.0
            : (_rng.nextDouble() - 0.5) * len * 0.16;
        final p = base + normal * jitter;
        out.add(Offset(p.x, p.y));
      }
    }
    return out;
  }

  @override
  void update(double dt) {
    _t += dt;
    if (_t >= _duration) {
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    if (_jagged.length < 2) {
      return;
    }
    final alpha = 1 - (_t / _duration).clamp(0.0, 1.0);
    canvas.drawPath(
      _path,
      strokePaint(fadeColor(color, alpha * 0.35), 7, cap: StrokeCap.round)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawPath(
      _path,
      strokePaint(fadeColor(Colors.white, alpha), 2.2, cap: StrokeCap.round),
    );
  }
}

class _Particle {
  _Particle(this.pos, this.vel, this.radius, this.color);
  Vector2 pos;
  Vector2 vel;
  double radius;
  Color color;
}

/// 처치/피격 시 튀는 파티클.
class BurstEffect extends PositionComponent {
  BurstEffect(
    Vector2 at,
    Color color, {
    int count = 10,
    double speed = 90,
    this.duration = 0.5,
    double size = 3,
  }) : super(position: at.clone(), priority: kFxPriority + 1) {
    final rng = math.Random();
    for (var i = 0; i < count; i++) {
      final a = rng.nextDouble() * math.pi * 2;
      final s = speed * (0.4 + rng.nextDouble() * 0.9);
      _particles.add(
        _Particle(
          Vector2.zero(),
          Vector2(math.cos(a) * s, math.sin(a) * s),
          size * (0.6 + rng.nextDouble() * 0.9),
          color,
        ),
      );
    }
  }

  final double duration;
  final List<_Particle> _particles = [];
  double _t = 0;

  @override
  void update(double dt) {
    _t += dt;
    if (_t >= duration) {
      removeFromParent();
      return;
    }
    for (final p in _particles) {
      p.pos += p.vel * dt;
      p.vel *= 1 - 2.4 * dt;
      p.vel.y += 140 * dt;
    }
  }

  @override
  void render(Canvas canvas) {
    final alpha = 1 - (_t / duration).clamp(0.0, 1.0);
    for (final p in _particles) {
      canvas.drawCircle(
        Offset(p.pos.x, p.pos.y),
        p.radius * alpha,
        fillPaint(fadeColor(p.color, alpha)),
      );
    }
  }
}

/// 소환 성공 시 유닛 위로 뜨는 등급 카드.
class SummonFlash extends PositionComponent {
  SummonFlash(Vector2 at, this.label, this.name, this.color, this.tier)
    : super(position: at.clone(), priority: kFxPriority + 6);

  final String label;
  final String name;
  final Color color;
  final int tier;

  double _t = 0;
  late final double _duration = tier >= 3 ? 1.5 : 0.95;

  @override
  void update(double dt) {
    _t += dt;
    if (_t >= _duration) {
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    final p = (_t / _duration).clamp(0.0, 1.0);
    final pop = Curves.easeOutBack.transform(math.min(1.0, p / 0.25));
    final alpha = p < 0.7 ? 1.0 : 1 - (p - 0.7) / 0.3;
    final dy = -28 - 16 * Curves.easeOut.transform(p);

    canvas.save();
    canvas.translate(0, dy);
    canvas.scale(pop.clamp(0.01, 2.0));

    const w = 108.0;
    const h = 34.0;
    final rect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-w / 2, -h / 2, w, h),
      const Radius.circular(9),
    );
    if (tier >= 3) {
      canvas.drawRRect(
        rect,
        blurPaint(fadeColor(color, alpha * 0.6), 12),
      );
    }
    canvas.drawRRect(
      rect,
      fillPaint(fadeColor(const Color(0xFF10151F), alpha * 0.95)),
    );
    canvas.drawRRect(
      rect,
      strokePaint(fadeColor(color, alpha), 2),
    );
    drawTextCentered(
      canvas,
      label,
      TextStyle(
        fontSize: 9,
        color: fadeColor(color, alpha),
        fontWeight: FontWeight.w900,
        letterSpacing: 0.6,
      ),
      const Offset(0, -8),
    );
    drawTextCentered(
      canvas,
      name,
      TextStyle(
        fontSize: 13,
        color: fadeColor(Colors.white, alpha),
        fontWeight: FontWeight.w800,
      ),
      const Offset(0, 6),
    );
    canvas.restore();
  }
}

/// 웨이브/보스 등장 배너.
class MeteorEffect extends PositionComponent {
  MeteorEffect(
    this.impact, {
    required this.onImpact,
    required this.band,
    this.delay = 0,
  }) : super(priority: kFxPriority + 3);

  /// 떨어질 자리.
  final Vector2 impact;

  /// 닿는 순간 한 번 불린다.
  final VoidCallback onImpact;

  /// 화면 크기에 맞춘 기준 길이(레인 간격).
  final double band;

  final double delay;

  static const _fallTime = 0.55;

  double _t = 0;
  bool _hit = false;

  late final Vector2 _from = impact + Vector2(-band * 2.2, -band * 9);

  @override
  void update(double dt) {
    _t += dt;
    final p = ((_t - delay) / _fallTime).clamp(0.0, 1.0);
    position
      ..setFrom(_from)
      ..lerp(impact, p);
    if (p >= 1 && !_hit) {
      _hit = true;
      onImpact();
    }
    // 터진 뒤 잔광이 사라질 때까지 조금 더 남는다.
    if (_t - delay > _fallTime + 0.45) {
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    final p = ((_t - delay) / _fallTime).clamp(0.0, 1.0);
    if (p <= 0) {
      return;
    }
    if (!_hit) {
      // 꼬리 — 뒤로 길게 늘어진 불꽃.
      for (var i = 0; i < 6; i++) {
        final back = i * band * 0.34;
        final a = (1 - i / 6) * 0.75;
        canvas.drawCircle(
          Offset(back * 0.24, -back),
          band * 0.2 * (1 - i / 8),
          fillPaint(fadeColor(const Color(0xFFFFA24D), a)),
        );
      }
      canvas
        ..drawCircle(
          Offset.zero,
          band * 0.32,
          blurPaint(const Color(0xFFFF6B3D), 8),
        )
        ..drawCircle(Offset.zero, band * 0.2, fillPaint(_meteorCore));
      return;
    }
    // 충격파.
    final k = ((_t - delay - _fallTime) / 0.45).clamp(0.0, 1.0);
    final r = band * (0.4 + k * 1.9);
    canvas.drawCircle(
      Offset.zero,
      r,
      strokePaint(fadeColor(const Color(0xFFFF6B3D), 1 - k), band * 0.16 * (1 - k)),
    );
  }
}

const _meteorCore = Color(0xFFFFE2B0);

const _bannerRect = Rect.fromLTWH(-260, -26, 520, 52);

class WaveBanner extends PositionComponent {
  WaveBanner(this.title, this.subtitle, this.color, Vector2 center)
    : super(position: center.clone(), priority: kFxPriority + 8);

  final String title;
  final String subtitle;
  final Color color;

  double _t = 0;
  static const double _duration = 1.9;

  @override
  void update(double dt) {
    _t += dt;
    if (_t >= _duration) {
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    final p = (_t / _duration).clamp(0.0, 1.0);
    final enter = Curves.easeOutCubic.transform(math.min(1.0, p / 0.22));
    final alpha = p < 0.72 ? 1.0 : 1 - (p - 0.72) / 0.28;
    final dx = (1 - enter) * 70;

    canvas.save();
    canvas.translate(dx, 0);
    canvas.drawRect(
      _bannerRect,
      shaderPaint(bandShader(color, alpha * 0.30, _bannerRect)),
    );
    drawTextCentered(
      canvas,
      title,
      TextStyle(
        fontSize: 27,
        color: fadeColor(Colors.white, alpha),
        fontWeight: FontWeight.w900,
        letterSpacing: 1,
      ),
      const Offset(0, -7),
    );
    drawTextCentered(
      canvas,
      subtitle,
      TextStyle(
        fontSize: 12,
        color: fadeColor(color, alpha),
        fontWeight: FontWeight.w700,
        letterSpacing: 2,
      ),
      const Offset(0, 16),
    );
    canvas.restore();
  }
}
