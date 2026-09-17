import 'package:flutter/material.dart';

import '../game/components/render_utils.dart';
import '../game/data/balance.dart';
import '../game/game_state.dart';
import 'theme.dart';

/// 상단 정보 바: 웨이브 / 라이프 / 골드 / 다이아 / 다음 웨이브 타이머.
class HudBar extends StatelessWidget {
  const HudBar({super.key, required this.state});

  final GameState state;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        final isBossNext = (state.wave + 1) % Balance.bossEvery == 0;
        final progress = (1 - state.waveCountdown / Balance.waveInterval).clamp(
          0.0,
          1.0,
        );

        return Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
          decoration: const BoxDecoration(
            color: GameColors.panel,
            border: Border(bottom: BorderSide(color: GameColors.border)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  _WaveBadge(
                    wave: state.wave,
                    best: state.best.wave,
                    total: state.mode.isEndless ? null : Balance.clearWave,
                  ),
                  const SizedBox(width: 8),
                  StatChip(
                    icon: '❤️',
                    value: '${state.lives}',
                    color: GameColors.life,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    // 좁은 화면(320pt 등)에서도 칩이 잘리지 않도록 축소 허용.
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          StatChip(
                            icon: '🪙',
                            value: formatNumber(state.gold),
                            color: GameColors.gold,
                          ),
                          const SizedBox(width: 6),
                          StatChip(
                            icon: '💎',
                            value: '${state.gems}',
                            color: GameColors.gem,
                          ),
                          const SizedBox(width: 6),
                          StatChip(
                            icon: '🧩',
                            value: '${state.unitCount}/${state.slotCount}',
                            color: state.slotsFull
                                ? GameColors.life
                                : GameColors.sub,
                            compact: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Row(
                children: [
                  SizedBox(
                    width: 108,
                    child: Text(
                      state.isFinalWave
                          ? '마지막 웨이브!'
                          : state.wave == 0
                          ? '전투 준비 ${state.waveCountdown.ceil()}초'
                          : '다음 웨이브 ${state.waveCountdown.ceil()}초',
                      style: const TextStyle(
                        color: GameColors.sub,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 5,
                        backgroundColor: GameColors.panelSoft,
                        valueColor: AlwaysStoppedAnimation(
                          isBossNext ? GameColors.life : GameColors.accent,
                        ),
                      ),
                    ),
                  ),
                  if (isBossNext) ...[
                    const SizedBox(width: 7),
                    const Text(
                      'BOSS',
                      style: TextStyle(
                        color: GameColors.life,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
            ],
          ),
        );
      },
    );
  }
}

class _WaveBadge extends StatelessWidget {
  const _WaveBadge({
    required this.wave,
    required this.best,
    required this.total,
  });

  final int wave;

  /// 클리어 모드의 목표 웨이브. 무한 모드면 null.
  final int? total;

  /// 기기에 저장된 최고 도달 웨이브(0이면 기록 없음).
  final int best;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2B3A6B), Color(0xFF1B2440)],
        ),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: GameColors.accent.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'WAVE',
            style: TextStyle(
              color: GameColors.sub,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            '$wave',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          if (total != null)
            Text(
              '/$total',
              style: const TextStyle(
                color: GameColors.sub,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                height: 1.3,
              ),
            ),
          if (best > 0) ...[
            const SizedBox(width: 7),
            Container(width: 1, height: 12, color: GameColors.border),
            const SizedBox(width: 6),
            const Text('🏆', style: TextStyle(fontSize: 9)),
            const SizedBox(width: 3),
            Text(
              '$best',
              style: const TextStyle(
                color: GameColors.gold,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
