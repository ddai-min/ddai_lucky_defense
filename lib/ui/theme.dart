import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'shortcuts.dart';

/// 마우스로도 스크롤 영역을 끌 수 있게 한다.
///
/// Flutter 기본값(`MaterialScrollBehavior.dragDevices`)은 터치·스타일러스만
/// 드래그로 인정한다. 그래서 웹·데스크톱에서는 하단 강화 메뉴 같은 가로 목록을
/// 마우스로 잡아끌어도 움직이지 않고, 휠이나 스크롤바를 써야 한다.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => PointerDeviceKind.values.toSet();
}

class GameColors {
  GameColors._();

  static const bg = Color(0xFF070A14);
  static const panel = Color(0xFF111726);
  static const panelSoft = Color(0xFF1A2235);
  static const border = Color(0xFF26314C);
  static const text = Color(0xFFE6EAF4);
  static const sub = Color(0xFF8A94AC);
  static const gold = Color(0xFFFFD34E);
  static const gem = Color(0xFF58E0FF);
  static const life = Color(0xFFFF5C6E);
  static const accent = Color(0xFF6C8CFF);
  static const green = Color(0xFF23C77E);
}

/// 버튼에 얹는 키보드 키캡. «이 키를 누르면 이 버튼» 을 알린다.
///
/// 키보드가 없는 기기에서는 [hasPhysicalKeyboard] 가 거짓이라 호출하는 쪽에서
/// 아예 그리지 않는다.
class KeyCap extends StatelessWidget {
  const KeyCap(this.shortcut, {super.key, this.enabled = true});

  final GameKey shortcut;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final color = enabled ? GameColors.sub : GameColors.sub.withValues(alpha: 0.4);
    return Container(
      width: 16,
      height: 16,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        shortcut.hint,
        style: TextStyle(
          color: color,
          fontSize: 9.5,
          height: 1,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

/// HUD에서 쓰는 아이콘 + 수치 칩.
class StatChip extends StatelessWidget {
  const StatChip({
    super.key,
    required this.icon,
    required this.value,
    required this.color,
    this.label,
    this.compact = false,
  });

  final String icon;
  final String value;
  final Color color;
  final String? label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 7 : 9, vertical: 5),
      decoration: BoxDecoration(
        color: GameColors.panelSoft,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon, style: TextStyle(fontSize: compact ? 11 : 13)),
          const SizedBox(width: 5),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: compact ? 12 : 13.5,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
          if (label != null) ...[
            const SizedBox(width: 3),
            Text(
              label!,
              style: const TextStyle(
                color: GameColors.sub,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 컨트롤 패널 공용 버튼.
class ActionButton extends StatelessWidget {
  const ActionButton({
    super.key,
    required this.label,
    required this.onTap,
    this.sub,
    this.icon,
    this.color = GameColors.accent,
    this.enabled = true,
    this.filled = false,
    this.height = 46,
    this.badge,
    this.shortcut,
  });

  final String label;
  final String? sub;
  final String? icon;
  final Color color;
  final bool enabled;
  final bool filled;
  final double height;
  final String? badge;

  /// 이 버튼을 누르는 키보드 단축키. 키보드가 있는 환경에서만 키캡을 띄운다.
  final GameKey? shortcut;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final base = enabled ? color : GameColors.sub.withValues(alpha: 0.35);
    final content = Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: filled && enabled
            ? base.withValues(alpha: 0.20)
            : GameColors.panelSoft,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: enabled ? base.withValues(alpha: 0.75) : GameColors.border,
          width: filled ? 1.6 : 1.2,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Text(icon!, style: const TextStyle(fontSize: 15)),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: enabled ? GameColors.text : GameColors.sub,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
                if (sub != null)
                  Text(
                    sub!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: enabled ? base : GameColors.sub,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
              ],
            ),
          ),
          if (shortcut != null && hasPhysicalKeyboard) ...[
            const SizedBox(width: 6),
            KeyCap(shortcut!, enabled: enabled),
          ],
        ],
      ),
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: badge == null
            ? content
            : Stack(
                clipBehavior: Clip.none,
                children: [
                  content,
                  Positioned(
                    right: -5,
                    top: -5,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: GameColors.green,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: GameColors.bg, width: 1.5),
                      ),
                      child: Text(
                        badge!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// 작은 토글 버튼(자동합성 / 배속).
class ToggleChip extends StatelessWidget {
  const ToggleChip({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
    this.color = GameColors.accent,
    this.width,
  });

  final String label;
  final bool active;
  final Color color;
  final double? width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        height: 46,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.22) : GameColors.panelSoft,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: active ? color : GameColors.border,
            width: active ? 1.6 : 1.2,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: active ? color : GameColors.sub,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            height: 1.15,
          ),
        ),
      ),
    );
  }
}
