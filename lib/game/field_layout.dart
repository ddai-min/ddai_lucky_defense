import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';

/// 몬스터가 따라 걷는 꺾은선 경로. 거리(px) 기준으로 위치를 조회한다.
class EnemyPath {
  EnemyPath(this.points) : assert(points.length >= 2, '경로는 최소 2개의 점이 필요합니다.') {
    _cumulative = List<double>.filled(points.length, 0);
    for (var i = 1; i < points.length; i++) {
      _cumulative[i] = _cumulative[i - 1] + points[i].distanceTo(points[i - 1]);
    }
    length = _cumulative.last;

    final p = ui.Path()..moveTo(points.first.x, points.first.y);
    for (var i = 1; i < points.length; i++) {
      p.lineTo(points[i].x, points[i].y);
    }
    uiPath = p;
  }

  final List<Vector2> points;
  late final List<double> _cumulative;
  late final double length;
  late final ui.Path uiPath;

  Vector2 get start => points.first;
  Vector2 get end => points.last;

  int _segmentAt(double distance) {
    var lo = 0;
    var hi = points.length - 1;
    while (lo < hi - 1) {
      final mid = (lo + hi) >> 1;
      if (_cumulative[mid] <= distance) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  Vector2 positionAt(double distance) {
    if (distance <= 0) {
      return points.first.clone();
    }
    if (distance >= length) {
      return points.last.clone();
    }
    final i = _segmentAt(distance);
    final segment = _cumulative[i + 1] - _cumulative[i];
    final t = segment <= 0 ? 0.0 : (distance - _cumulative[i]) / segment;
    return points[i] + (points[i + 1] - points[i]) * t;
  }

  /// 진행 방향 단위 벡터.
  Vector2 tangentAt(double distance) {
    final i = _segmentAt(distance.clamp(0, length - 0.001));
    final d = points[i + 1] - points[i];
    if (d.length2 == 0) {
      return Vector2(1, 0);
    }
    return d.normalized();
  }
}

/// 필드 크기에 맞춰 경로와 유닛 슬롯 위치를 계산한다.
/// 해상도가 달라져도 체감이 같도록 모든 수치를 화면 비율로 산출한다.
class FieldLayout {
  FieldLayout(this.size) {
    final w = size.x;
    final h = size.y;

    const bands = lanes * 2 - 1;
    final marginX = w * 0.055;
    final marginTop = h * 0.055;
    final marginBottom = h * 0.045;

    bandHeight = (h - marginTop - marginBottom) / bands;
    pathWidth = math.min(bandHeight * 0.52, 46.0);

    final left = marginX;
    final right = w - marginX;

    laneY = <double>[
      for (var i = 0; i < lanes; i++) marginTop + bandHeight * (2 * i + 0.5),
    ];
    final rowY = <double>[
      for (var j = 0; j < slotRows; j++) marginTop + bandHeight * (2 * j + 1.5),
    ];

    // 지그재그(부스트로페돈) 경로: 좌우를 번갈아 훑으며 아래로 내려간다.
    final raw = <Vector2>[];
    for (var i = 0; i < lanes; i++) {
      final goingRight = i.isEven;
      final xa = goingRight ? left : right;
      final xb = goingRight ? right : left;
      if (i == 0) {
        raw.add(Vector2(xa, laneY[i]));
      }
      raw.add(Vector2(xb, laneY[i]));
      if (i < lanes - 1) {
        raw.add(Vector2(xb, laneY[i + 1]));
      }
    }
    final cornerRadius = math.min(bandHeight * 0.55, (right - left) * 0.12);
    path = EnemyPath(_roundCorners(raw, cornerRadius));

    // 슬롯은 좌우 끝의 세로 연결 구간을 피해 안쪽에만 배치한다.
    // 칸 수는 고정이고, 칸 크기만 화면에 맞춰 늘고 준다.
    final maxSlot = math.min(bandHeight * 0.78, 92.0);
    final available = (right - left) - pathWidth - 12;
    slotSize = math.min(maxSlot, available / (1 + 1.06 * (slotCols - 1)));
    final pad = pathWidth / 2 + slotSize / 2 + 6;
    final areaLeft = left + pad;
    final areaRight = right - pad;
    final step = (areaRight - areaLeft) / (slotCols - 1);

    slotCenters = <Vector2>[
      for (var j = 0; j < slotRows; j++)
        for (var i = 0; i < slotCols; i++)
          Vector2(areaLeft + step * i, rowY[j]),
    ];
  }

  final Vector2 size;

  /// 몬스터가 지나는 가로 레인 수.
  static const int lanes = 4;

  /// 레인 사이에 끼워 넣는 유닛 슬롯 줄 수.
  static const int slotRows = lanes - 1;

  /// 한 줄에 놓이는 슬롯 수.
  static const int slotCols = 6;

  /// 배치 가능한 총 슬롯 수. 화면 크기·확대 배율과 무관하게 고정이다.
  ///
  /// 화면에 맞춰 칸 수를 늘리면 기기나 브라우저 확대 배율에 따라 놓을 수 있는
  /// 유닛 수가 달라져 난이도가 통째로 바뀐다. 칸 수는 고정하고 칸 크기만 늘린다.
  static const int maxSlots = slotRows * slotCols;

  /// 레인 한 칸의 세로 간격. 사거리·이펙트 크기의 기준 단위다.
  late final double bandHeight;
  late final double pathWidth;
  late final double slotSize;
  late final List<double> laneY;
  late final EnemyPath path;
  late final List<Vector2> slotCenters;

  int get slotCount => slotCenters.length;

  Vector2 get spawnPoint => path.start;
  Vector2 get basePoint => path.end;

  ui.Rect slotRect(int index) {
    final c = slotCenters[index];
    return ui.Rect.fromCenter(
      center: ui.Offset(c.x, c.y),
      width: slotSize,
      height: slotSize,
    );
  }

  /// 좌표에서 가장 가까운 슬롯 인덱스.
  int nearestSlot(Vector2 p) {
    var best = 0;
    var bestDist = double.infinity;
    for (var i = 0; i < slotCenters.length; i++) {
      final d = slotCenters[i].distanceToSquared(p);
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    }
    return best;
  }

  /// 꺾인 지점을 2차 베지어로 부드럽게 만든다.
  static List<Vector2> _roundCorners(
    List<Vector2> raw,
    double radius, {
    int segments = 10,
  }) {
    if (raw.length < 3) {
      return raw;
    }
    final out = <Vector2>[raw.first.clone()];
    for (var i = 1; i < raw.length - 1; i++) {
      final p = raw[i];
      final a = raw[i - 1];
      final b = raw[i + 1];
      final r = math.min(
        radius,
        math.min(p.distanceTo(a), p.distanceTo(b)) * 0.5,
      );
      final v1 = (a - p).normalized();
      final v2 = (b - p).normalized();
      final p1 = p + v1 * r;
      final p2 = p + v2 * r;
      out.add(p1);
      for (var s = 1; s < segments; s++) {
        final t = s / segments;
        final u = 1 - t;
        out.add(p1 * (u * u) + p * (2 * u * t) + p2 * (t * t));
      }
      out.add(p2);
    }
    out.add(raw.last.clone());
    return out;
  }
}
