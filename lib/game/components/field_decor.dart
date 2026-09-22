import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../lucky_defense_game.dart';
import 'render_utils.dart';

/// 필드 배경(그라데이션 + 격자 + 상단 광원).
class BackgroundComponent extends PositionComponent {
  BackgroundComponent(this.game) : super(priority: -30);

  final LuckyDefenseGame game;

  Paint? _skyPaint;
  Paint? _glowPaint;
  Path? _gridPath;
  final Paint _gridPaint = Paint()
    ..color = Colors.white.withValues(alpha: 0.025)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;

  /// 레이아웃이 바뀔 때만 셰이더와 격자를 다시 만든다.
  void rebuild() {
    final w = game.layout.size.x;
    final h = game.layout.size.y;
    final rect = Rect.fromLTWH(0, 0, w, h);

    _skyPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF131A2C), Color(0xFF0B1020), Color(0xFF070A14)],
        stops: [0, 0.55, 1],
      ).createShader(rect);

    final glowCenter = Offset(w * 0.5, -h * 0.25);
    _glowPaint = Paint()
      ..shader = ui.Gradient.radial(glowCenter, h * 0.7, const [
        Color(0x33627BFF),
        Color(0x00627BFF),
      ]);

    final grid = Path();
    final step = game.layout.bandHeight * 0.5;
    for (var x = 0.0; x < w; x += step) {
      grid
        ..moveTo(x, 0)
        ..lineTo(x, h);
    }
    for (var y = 0.0; y < h; y += step) {
      grid
        ..moveTo(0, y)
        ..lineTo(w, y);
    }
    _gridPath = grid;
  }

  @override
  void render(Canvas canvas) {
    final sky = _skyPaint;
    final glow = _glowPaint;
    final grid = _gridPath;
    if (sky == null || glow == null || grid == null) {
      return;
    }
    final w = game.layout.size.x;
    final h = game.layout.size.y;

    canvas
      ..drawRect(Rect.fromLTWH(0, 0, w, h), sky)
      ..drawPath(grid, _gridPaint)
      ..drawCircle(Offset(w * 0.5, -h * 0.25), h * 0.7, glow);
  }
}

/// 몬스터 이동 경로.
class PathComponent extends PositionComponent {
  PathComponent(this.game) : super(priority: -20);

  final LuckyDefenseGame game;

  ui.Path? _dashed;
  List<({Offset pos, double angle})> _arrows = const [];

  /// 원점 기준 화살표 하나. 위치·각도는 캔버스 변환으로 준다.
  Path? _arrowShape;

  /// 알파만 매 프레임 바뀌므로 공용 스크래치 대신 이 한 벌을 계속 고쳐 쓴다
  /// (루프 안에서 다른 그리기가 스크래치를 건드려도 안전하게).
  final Paint _arrowPaint = Paint();

  static const _dashLine = Color(0x1AFFFFFF);
  double _flow = 0;

  /// 레이아웃이 바뀌면 다시 계산한다.
  void rebuild() {
    final path = game.layout.path;
    final dash = ui.Path();
    for (final metric in path.uiPath.computeMetrics()) {
      var d = 0.0;
      final len = math.max(10.0, game.layout.bandHeight * 0.22);
      while (d < metric.length) {
        final next = math.min(d + len, metric.length);
        dash.addPath(metric.extractPath(d, next), Offset.zero);
        d = next + len;
      }
    }
    _dashed = dash;

    final arrows = <({Offset pos, double angle})>[];
    final gap = game.layout.bandHeight * 2.2;
    for (var d = gap * 0.6; d < path.length; d += gap) {
      final p = path.positionAt(d);
      final t = path.tangentAt(d);
      arrows.add((pos: Offset(p.x, p.y), angle: math.atan2(t.y, t.x)));
    }
    _arrows = arrows;

    final arrowSize = game.layout.bandHeight * 0.16;
    _arrowShape = Path()
      ..moveTo(arrowSize, 0)
      ..lineTo(-arrowSize * 0.7, arrowSize * 0.75)
      ..lineTo(-arrowSize * 0.7, -arrowSize * 0.75)
      ..close();
  }

  @override
  void update(double dt) {
    _flow = (_flow + dt * 0.8) % 1.0;
  }

  @override
  void render(Canvas canvas) {
    final layout = game.layout;
    final uiPath = layout.path.uiPath;
    final w = layout.pathWidth;

    canvas.drawPath(
      uiPath,
      strokePaint(
        const Color(0xFF1B2136),
        w + 8,
        cap: StrokeCap.round,
        join: StrokeJoin.round,
      ),
    );
    canvas.drawPath(
      uiPath,
      strokePaint(
        const Color(0xFF2C3654),
        w,
        cap: StrokeCap.round,
        join: StrokeJoin.round,
      ),
    );
    canvas.drawPath(
      uiPath,
      strokePaint(
        const Color(0xFF333F63),
        w * 0.62,
        cap: StrokeCap.round,
        join: StrokeJoin.round,
      ),
    );

    final dashed = _dashed;
    if (dashed != null) {
      canvas.drawPath(
        dashed,
        strokePaint(_dashLine, 2),
      );
    }

    // 진행 방향 화살표
    final arrow = _arrowShape;
    final pulse = 0.35 + 0.3 * math.sin(_flow * math.pi * 2);
    // 모양은 전부 같고 위치·각도만 다르다. 화살표마다 Path 를 새로 만들면
    // 프레임마다 네이티브 객체가 수십 개씩 생긴다.
    _arrowPaint.color = const Color(0xFF8FA3FF).withValues(alpha: pulse);
    if (arrow != null) {
      for (final a in _arrows) {
        canvas.save();
        canvas.translate(a.pos.dx, a.pos.dy);
        canvas.rotate(a.angle);
        canvas.drawPath(arrow, _arrowPaint);
        canvas.restore();
      }
    }

    _drawTerminal(canvas, layout.spawnPoint, '🌀', const Color(0xFF7C5CFF));
    _drawTerminal(canvas, layout.basePoint, '🏰', const Color(0xFF4ED8A0));
  }

  void _drawTerminal(Canvas canvas, Vector2 at, String emoji, Color color) {
    final r = game.layout.bandHeight * 0.34;
    final c = Offset(at.x, at.y);
    canvas.drawCircle(
      c,
      r * 1.25,
      blurPaint(color.withValues(alpha: 0.22), 8),
    );
    canvas.drawCircle(c, r, fillPaint(const Color(0xFF161C2E)));
    canvas.drawCircle(
      c,
      r,
      strokePaint(color, 2.5),
    );
    drawTextCentered(canvas, emoji, TextStyle(fontSize: r * 1.1), c);
  }
}

/// 빈 유닛 슬롯 표시 + 드래그 중 하이라이트.
class SlotLayerComponent extends PositionComponent {
  SlotLayerComponent(this.game) : super(priority: -10);

  final LuckyDefenseGame game;

  final Paint _border = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5
    ..color = Colors.white.withValues(alpha: 0.13);
  final Paint _fill = Paint()..color = Colors.white.withValues(alpha: 0.035);
  final Paint _targetFill = Paint()
    ..color = const Color(0xFF6BE3B8).withValues(alpha: 0.22);
  final Paint _targetBorder = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.5
    ..color = const Color(0xFF6BE3B8);

  /// 원점 기준 빈 슬롯 모양(점선 포함). 슬롯마다 다시 계산하지 않는다.
  Path? _dashedSlot;
  RRect? _slotShape;
  List<bool> _occupied = const [];

  void rebuild() {
    final size = game.layout.slotSize - 2;
    final shape = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: size, height: size),
      Radius.circular(size * 0.26),
    );
    _slotShape = shape;

    final dash = size * 0.14;
    final source = Path()..addRRect(shape);
    final out = Path();
    for (final metric in source.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        final next = math.min(d + dash, metric.length);
        out.addPath(metric.extractPath(d, next), Offset.zero);
        d = next + dash;
      }
    }
    _dashedSlot = out;
    _occupied = List<bool>.filled(game.layout.slotCount, false);
  }

  @override
  void render(Canvas canvas) {
    final shape = _slotShape;
    final dashed = _dashedSlot;
    if (shape == null || dashed == null) {
      return;
    }
    final layout = game.layout;
    if (_occupied.length != layout.slotCount) {
      _occupied = List<bool>.filled(layout.slotCount, false);
    }
    _occupied.fillRange(0, _occupied.length, false);
    for (final u in game.units) {
      if (u.slotIndex >= 0 && u.slotIndex < _occupied.length) {
        _occupied[u.slotIndex] = true;
      }
    }

    for (var i = 0; i < layout.slotCount; i++) {
      final isTarget = game.dropTargetSlot == i;
      if (_occupied[i] && !isTarget) {
        continue;
      }
      final center = layout.slotCenters[i];
      canvas.save();
      canvas.translate(center.x, center.y);
      if (isTarget) {
        canvas
          ..drawRRect(shape, _targetFill)
          ..drawRRect(shape, _targetBorder);
      } else {
        canvas
          ..drawRRect(shape, _fill)
          ..drawPath(dashed, _border);
      }
      canvas.restore();
    }
  }
}
