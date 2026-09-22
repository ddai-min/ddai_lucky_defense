import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 그리기 한 번에만 쓰고 버리는 공용 [Paint].
///
/// 웹(CanvasKit)에서 `Paint` 하나하나는 네이티브 SkPaint 를 붙들고 있고, 그
/// 메모리는 Dart 쪽 객체가 GC 될 때에야 풀린다. 그런데 이 게임은 Dart 힙을
/// 거의 쓰지 않아(20MB 언저리에서 평평) GC 가 좀처럼 돌지 않는다. 그래서
/// 프레임마다 새로 만든 Paint 가 네이티브에 그대로 쌓여, 실측으로 렌더러
/// 메모리가 **분당 17MB** 씩 늘었다. 몇십 분이면 탭이 죽는다.
///
/// Skia 는 draw 호출 시점에 Paint 값을 복사하므로, 한 벌을 고쳐 가며 계속
/// 쓰면 된다. **draw 에 곧바로 넘길 때만 쓸 것** — 두 개를 동시에 들고 있으면
/// 나중에 얻은 쪽이 앞의 것을 덮어쓴다. 오래 들고 있어야 하면 그 컴포넌트의
/// 필드로 Paint 를 하나 두는 편이 낫다.
final Paint _scratchPaint = Paint();

Paint _resetScratch() => _scratchPaint
  ..shader = null
  ..maskFilter = null
  ..style = PaintingStyle.fill
  ..strokeWidth = 0
  ..strokeCap = StrokeCap.butt
  ..strokeJoin = StrokeJoin.miter
  ..color = const Color(0xFF000000);

/// 채우기용 공용 Paint. 규칙은 [_scratchPaint] 설명을 따른다.
Paint fillPaint(Color color) => _resetScratch()..color = color;

/// 선용 공용 Paint.
Paint strokePaint(
  Color color,
  double width, {
  StrokeCap cap = StrokeCap.butt,
  StrokeJoin join = StrokeJoin.miter,
}) => _resetScratch()
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = cap
  ..strokeJoin = join
  ..color = color;

/// 그라데이션용 공용 Paint.
Paint shaderPaint(ui.Shader shader) => _resetScratch()..shader = shader;

/// 번짐 세기별 MaskFilter. 종류가 몇 개 안 되므로 만들어 두고 돌려 쓴다.
final Map<int, MaskFilter> _blurFilters = {};

/// 번짐(글로우)용 공용 Paint.
Paint blurPaint(Color color, double sigma) => _resetScratch()
  ..color = color
  ..maskFilter = _blurFilters.putIfAbsent(
    (sigma * 2).round(),
    () => MaskFilter.blur(BlurStyle.normal, sigma),
  );

final LinkedHashMap<String, TextPainter> _painterCache =
    LinkedHashMap<String, TextPainter>();

/// 글자 크기를 끊어 쓰는 단위(px).
///
/// 몬스터가 튀어나오는 0.2초 동안 반지름이 연속으로 변하는데, 그 값을 그대로
/// 키에 쓰면 **한 마리 나올 때마다 서로 다른 키가 열몇 개씩** 생긴다. 그러면
/// 캐시가 쉴 새 없이 갈리고, 밀려난 자리마다 네이티브 문단이 하나씩 남는다.
const double _fontStep = 0.5;

/// 반복 호출되는 텍스트(이모지·숫자)의 TextPainter를 재사용한다.
TextPainter cachedPainter(String text, TextStyle style) {
  final size = ((style.fontSize ?? 14) / _fontStep).round() * _fontStep;
  final key =
      '$text|$size|${style.color?.toARGB32()}'
      '|${style.fontWeight?.value}|${style.letterSpacing}';
  final hit = _painterCache[key];
  if (hit != null) {
    return hit;
  }
  final painter = TextPainter(
    text: TextSpan(text: text, style: style.copyWith(fontSize: size)),
    textDirection: TextDirection.ltr,
  )..layout();
  if (_painterCache.length >= _painterCacheMax) {
    // 밀려나는 문단을 여기서 dispose() 하면 안 된다. Canvas 는 그리기를
    // «기록» 만 해 두고 실제 래스터라이즈는 프레임 끝에 하므로, 같은 프레임에
    // 이미 그린 문단을 해제해 버리면 그 글자가 두부(□)로 나온다. 실제로
    // 포털·성 이모지가 깨졌다. GC 에 맡긴다.
    _painterCache.remove(_painterCache.keys.first);
  }
  _painterCache[key] = painter;
  return painter;
}

const int _painterCacheMax = 240;


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
    return s.replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
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
  if (_shaderCache.length >= 64) {
    // 문단과 같은 이유로 여기서도 dispose() 하지 않는다 — 이미 기록된
    // 그리기가 이 셰이더를 참조하고 있을 수 있다.
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

/// 웨이브 배너용 가로 띠 그라데이션.
///
/// 알파가 매 프레임 변하지만 [fadeColor] 가 8단계로 끊어 주므로 종류는 몇 개뿐
/// 이다. 캐시를 안 태우면 프레임마다 네이티브 셰이더가 새로 생긴다.
ui.Shader bandShader(Color color, double alpha, Rect rect) {
  final mid = fadeColor(color, alpha);
  return _cacheShader(
    'band|${mid.toARGB32()}|${rect.width.toStringAsFixed(0)}',
    () => ui.Gradient.linear(
      rect.centerLeft,
      rect.centerRight,
      [color.withValues(alpha: 0), mid, color.withValues(alpha: 0)],
      const [0, 0.5, 1],
    ),
  );
}

/// 유닛 배지용 대각선 그라데이션.
ui.Shader badgeShader(Color from, Color to, double half) {
  return _cacheShader(
    'badge|${from.toARGB32()}|${to.toARGB32()}|${half.toStringAsFixed(1)}',
    () => ui.Gradient.linear(Offset(-half, -half), Offset(half, half), [
      from,
      to,
    ]),
  );
}
