import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';

import '../data/rarity.dart';
import '../data/unit_catalog.dart';
import '../lucky_defense_game.dart';
import 'render_utils.dart';

/// 슬롯에 배치되어 자동으로 공격하는 유닛.
const _unitShadow = Color(0x59000000);
const _lockFill = Color(0xF21A1F2E);
const _lockRing = Color(0xFFFFD34E);
const _badgeRing = Color(0xBFFFFFFF);

class UnitComponent extends PositionComponent with TapCallbacks, DragCallbacks {
  UnitComponent({
    required this.game,
    required this.spec,
    required this.slotIndex,
  }) : super(priority: 20, anchor: Anchor.center) {
    _phase = game.rng.nextDouble() * math.pi * 2;
    syncToSlot();
  }

  final LuckyDefenseGame game;
  UnitSpec spec;
  int slotIndex;

  double _cooldown = 0;
  double _recoil = 0;
  double _phase = 0;
  double _spawnPop = 0;
  Vector2 _aim = Vector2(1, 0);
  Vector2? _dragAnchor;

  bool get isSelected => game.selected == this;
  bool get isMergeReady =>
      (game.unitCounts[spec.id] ?? 0) >= 3 && spec.rarity.next != null;

  double get range => game.layout.bandHeight * spec.rangeFactor;
  double get damage =>
      spec.damage * game.state.damageMultiplierOf(spec.rarity);
  double get attacksPerSecond =>
      spec.attacksPerSecond * game.state.attackSpeedMultiplier;

  void syncToSlot() {
    size = Vector2.all(game.layout.slotSize);
    if (slotIndex >= 0 && slotIndex < game.layout.slotCount) {
      position.setFrom(game.layout.slotCenters[slotIndex]);
    }
  }

  @override
  void update(double dt) {
    _spawnPop = math.min(1, _spawnPop + dt * 6);
    _phase += dt;
    _recoil = math.max(0, _recoil - dt * 7);

    if (game.state.isFinished || game.state.paused) {
      return;
    }

    _cooldown -= dt;
    if (_cooldown <= 0) {
      final target = game.findTarget(position, range);
      if (target != null) {
        final d = target.position - position;
        if (d.length2 > 0) {
          _aim = d.normalized();
        }
        game.fireAt(this, target);
        _recoil = 1;
        _cooldown = 1 / math.max(0.05, attacksPerSecond);
      } else {
        _cooldown = 0;
      }
    }
  }

  // ─────────────────────────── 입력 ───────────────────────────
  @override
  void onTapDown(TapDownEvent event) {
    game.selectUnit(this);
  }

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    _dragAnchor = position.clone();
    priority = 60;
    // 드래그 시작으로 선택이 토글돼 풀리면 안 되므로 focus를 쓴다.
    game.focusUnit(this);
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    position.add(event.canvasDelta);
    game.dropTargetSlot = game.layout.nearestSlot(position);
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    priority = 20;
    final target = game.dropTargetSlot;
    game.dropTargetSlot = -1;
    if (target != null && target >= 0) {
      game.moveUnitToSlot(this, target);
    } else {
      final anchor = _dragAnchor;
      if (anchor != null) {
        position.setFrom(anchor);
      }
    }
    _dragAnchor = null;
  }

  // ─────────────────────────── 렌더 ───────────────────────────
  @override
  void render(Canvas canvas) {
    final s = size.x;
    final center = Offset(s / 2, s / 2);
    final rarity = spec.rarity;

    if (isSelected) {
      canvas.drawCircle(
        center,
        range,
        fillPaint(rarity.color.withValues(alpha: 0.07)),
      );
      canvas.drawCircle(
        center,
        range,
        strokePaint(rarity.color.withValues(alpha: 0.55), 1.5),
      );
    }

    final pop = Curves.easeOutBack.transform(_spawnPop.clamp(0.0, 1.0));
    final breathe = 1 + math.sin(_phase * 2 + _phase) * 0.012;
    final kick = 1 + _recoil * 0.12;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale((pop * breathe * kick).clamp(0.01, 2.0));

    final half = s * 0.44;
    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: half * 2, height: half * 2),
      Radius.circular(half * 0.42),
    );

    canvas.drawRRect(
      body.shift(const Offset(0, 3)),
      fillPaint(_unitShadow),
    );

    if (rarity.index >= Rarity.epic.index) {
      canvas.drawRRect(
        body,
        blurPaint(
          rarity.color.withValues(alpha: 0.35 + 0.2 * math.sin(_phase * 3)),
          9,
        ),
      );
    }

    canvas.drawRRect(
      body,
      shaderPaint(
        badgeShader(
          Color.lerp(rarity.deep, rarity.color, 0.35)!,
          rarity.deep,
          half,
        ),
      ),
    );
    canvas.drawRRect(
      body,
      strokePaint(isSelected ? Colors.white : rarity.color, isSelected ? 3 : 2),
    );

    // 공격 시 총구 섬광
    if (_recoil > 0.05) {
      canvas.drawCircle(
        Offset(_aim.x * half * 0.9, _aim.y * half * 0.9),
        half * 0.22 * _recoil,
        fillPaint(fadeColor(spec.style.color, _recoil)),
      );
    }

    drawTextCentered(
      canvas,
      spec.emoji,
      TextStyle(fontSize: half * 1.05),
      Offset(0, -half * 0.06),
    );

    // 공격 타입 점
    canvas.drawCircle(
      Offset(-half * 0.68, half * 0.68),
      half * 0.15,
      fillPaint(spec.style.color),
    );

    canvas.restore();

    _drawCountBadge(canvas, center, half);
    _drawLockBadge(canvas, center, half);

    if (isMergeReady) {
      final glow = 0.5 + 0.5 * math.sin(_phase * 5);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: center,
            width: half * 2 + 7,
            height: half * 2 + 7,
          ),
          Radius.circular(half * 0.5),
        ),
        strokePaint(
          const Color(0xFF6BFFB0).withValues(alpha: 0.45 + glow * 0.5),
          2.4,
        ),
      );
    }
  }

  /// 자동 합성에서 빠져 있다는 표시. 보유 수 배지 반대쪽(왼쪽 위)에 둔다.
  void _drawLockBadge(Canvas canvas, Offset center, double half) {
    if (!game.state.mergeLocked.contains(spec.id)) {
      return;
    }
    final c = center + Offset(-half * 0.82, -half * 0.82);
    final r = half * 0.32;
    canvas
      ..drawCircle(c, r, fillPaint(_lockFill))
      ..drawCircle(c, r, strokePaint(_lockRing, 1.5));
    // 이모지는 글자보다 여백이 넓어, 숫자 배지와 같은 크기로 보이려면 더 키워야
    // 한다. 작으면 «뭔가 붙어 있다» 로만 보이고 자물쇠인 줄 모른다.
    drawTextCentered(canvas, '🔒', TextStyle(fontSize: r * 1.6), c);
  }

  void _drawCountBadge(Canvas canvas, Offset center, double half) {
    final count = game.unitCounts[spec.id] ?? 0;
    if (count < 2) {
      return;
    }
    final ready = count >= 3 && spec.rarity.next != null;
    final c = center + Offset(half * 0.82, -half * 0.82);
    final r = half * 0.30;
    canvas.drawCircle(
      c,
      r,
      fillPaint(ready ? const Color(0xFF23C77E) : const Color(0xFF2B3346)),
    );
    canvas.drawCircle(
      c,
      r,
      strokePaint(_badgeRing, 1.4),
    );
    drawTextCentered(
      canvas,
      '$count',
      TextStyle(
        fontSize: r * 1.25,
        color: Colors.white,
        fontWeight: FontWeight.w900,
      ),
      c,
    );
  }
}
