import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/components/render_utils.dart';
import '../game/data/unit_catalog.dart';
import '../game/game_state.dart';
import 'theme.dart';

/// 필드 우측 상단의 «유닛별 처치 수» 드롭다운.
///
/// 열려 있는 동안에도 게임은 계속 돌아가므로, 목록은 매 프레임 갱신된다.
/// 팔거나 합성해 사라진 유닛의 몫도 판이 끝날 때까지 남는다 — «이번 판에서
/// 무엇이 일했나» 를 보는 것이지 «지금 뭘 들고 있나» 를 보는 게 아니다.
class KillBoard extends StatefulWidget {
  const KillBoard({super.key, required this.state});

  final GameState state;

  @override
  State<KillBoard> createState() => _KillBoardState();
}

class _KillBoardState extends State<KillBoard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    // 인트로 뒤에서 «💀 0» 이 떠 있어 봐야 읽을 게 없다.
    if (!widget.state.started) {
      return const SizedBox.shrink();
    }
    // 필드가 낮은 화면(가로 모드·작은 창)에서는 260 을 그대로 쓰면 넘친다.
    // Positioned 가 주는 여유 높이에서 토글과 여백을 빼고 남는 만큼만 쓴다.
    return LayoutBuilder(
      builder: (context, constraints) {
        final room = constraints.maxHeight.isFinite
            ? math.min(260.0, constraints.maxHeight - 52)
            : 260.0;
        return Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            _Toggle(
              open: _open,
              state: widget.state,
              onTap: () => setState(() => _open = !_open),
            ),
            if (_open && room > 60) ...[
              const SizedBox(height: 6),
              _Panel(state: widget.state, maxHeight: room),
            ],
          ],
        );
      },
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.open,
    required this.state,
    required this.onTap,
  });

  final bool open;
  final GameState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: GameColors.panel.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: open ? GameColors.life : GameColors.border,
            width: open ? 1.5 : 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('💀', style: TextStyle(fontSize: 12)),
            const SizedBox(width: 5),
            Text(
              formatNumber(state.totalKills),
              style: const TextStyle(
                color: GameColors.text,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(width: 3),
            Icon(
              open
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: GameColors.sub,
            ),
          ],
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.state, required this.maxHeight});

  final GameState state;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    // 많이 잡은 순. 같으면 도감 순서(등급 오름차순)로 갈라 순서가 흔들리지 않게 한다.
    final order = {
      for (var i = 0; i < kUnitCatalog.length; i++) kUnitCatalog[i].id: i,
    };
    final rows = state.killsByUnit.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) {
        final byKills = b.value.compareTo(a.value);
        return byKills != 0
            ? byKills
            : (order[a.key] ?? 0).compareTo(order[b.key] ?? 0);
      });

    return Container(
      width: 186,
      constraints: BoxConstraints(maxHeight: maxHeight),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: GameColors.panel.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: GameColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '유닛별 처치',
            style: TextStyle(
              color: GameColors.sub,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 7),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text(
                '아직 처치 기록이 없습니다.',
                style: TextStyle(
                  color: GameColors.sub,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: rows.length,
                itemBuilder: (context, index) {
                  final row = rows[index];
                  return _KillRow(
                    spec: kUnitById[row.key],
                    kills: row.value,
                    share: state.totalKills <= 0
                        ? 0
                        : row.value / state.totalKills,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _KillRow extends StatelessWidget {
  const _KillRow({
    required this.spec,
    required this.kills,
    required this.share,
  });

  final UnitSpec? spec;
  final int kills;
  final double share;

  @override
  Widget build(BuildContext context) {
    final color = spec?.rarity.color ?? GameColors.sub;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        children: [
          Text(spec?.emoji ?? '❔', style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  spec?.name ?? '알 수 없음',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                // 전체에서 차지하는 몫. 숫자만 보면 누가 일했는지 가늠이 안 된다.
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: share.clamp(0.0, 1.0),
                    minHeight: 3,
                    backgroundColor: GameColors.panelSoft,
                    valueColor: AlwaysStoppedAnimation(
                      color.withValues(alpha: 0.75),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 7),
          Text(
            formatNumber(kills),
            style: const TextStyle(
              color: GameColors.text,
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
