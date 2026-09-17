import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

final LinkedHashMap<String, TextPainter> _painterCache =
    LinkedHashMap<String, TextPainter>();

/// 반복 호출되는 텍스트(이모지·숫자)의 TextPainter를 재사용한다.
TextPainter cachedPainter(String text, TextStyle style) {
  final key = '$text|${style.fontSize}|${style.color?.toARGB32()}'
      '|${style.fontWeight?.value}|${style.letterSpacing}';
  final hit = _painterCache[key];
  if (hit != null) {
    return hit;
  }
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  if (_painterCache.length > 600) {
    _painterCache.remove(_painterCache.keys.first);
  }
  _painterCache[key] = painter;
  return painter;
}

void drawTextCentered(
  Canvas canvas,
  String text,
  TextStyle style,
  Offset center,
) {
  final tp = cachedPainter(text, style);
  tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
}

/// 알파를 8단계로 양자화해 캐시 폭발을 막는다.
Color fadeColor(Color base, double alpha) =>
    base.withValues(alpha: (alpha.clamp(0.0, 1.0) * 8).round() / 8);

/// 별 모양 경로(초월 등급 연출용).
Path starPath(Offset center, double outer, double inner, int points) {
  final path = Path();
  for (var i = 0; i < points * 2; i++) {
    final r = i.isEven ? outer : inner;
    final a = -math.pi / 2 + i * math.pi / points;
    final p = center + Offset(math.cos(a) * r, math.sin(a) * r);
    if (i == 0) {
      path.moveTo(p.dx, p.dy);
    } else {
      path.lineTo(p.dx, p.dy);
    }
  }
  return path..close();
}

String formatNumber(num value) {
  final v = value.abs();
  if (v >= 1e12) {
    return '${(value / 1e12).toStringAsFixed(1)}조';
  }
  if (v >= 1e8) {
    return '${(value / 1e8).toStringAsFixed(1)}억';
  }
  if (v >= 1e4) {
    return '${(value / 1e4).toStringAsFixed(1)}만';
  }
  if (v >= 1000) {
    final s = value.round().toString();
    return s.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'),
      (m) => '${m[1]},',
    );
  }
  return value.round().toString();
}


final LinkedHashMap<String, ui.Shader> _shaderCache =
    LinkedHashMap<String, ui.Shader>();

ui.Shader _cacheShader(String key, ui.Shader Function() build) {
  final hit = _shaderCache[key];
  if (hit != null) {
    return hit;
  }
  if (_shaderCache.length > 120) {
    _shaderCache.remove(_shaderCache.keys.first);
  }
  final shader = build();
  _shaderCache[key] = shader;
  return shader;
}

/// 몬스터 몸통용 구형 그라데이션. 프레임마다 새로 만들지 않도록 캐시한다.
ui.Shader orbShader(Color color, double radius) {
  return _cacheShader(
    'orb|${color.toARGB32()}|${radius.toStringAsFixed(1)}',
    () => ui.Gradient.radial(
      Offset(-radius * 0.3, -radius * 0.4),
      radius,
      [
        Color.lerp(color, Colors.white, 0.35)!,
        color,
        Color.lerp(color, Colors.black, 0.45)!,
      ],
      const [0, 0.55, 1],
    ),
  );
}

/// 유닛 배지용 대각선 그라데이션.
ui.Shader badgeShader(Color from, Color to, double half) {
  return _cacheShader(
    'badge|${from.toARGB32()}|${to.toARGB32()}|${half.toStringAsFixed(1)}',
    () => ui.Gradient.linear(
      Offset(-half, -half),
      Offset(half, half),
      [from, to],
    ),
  );
}
