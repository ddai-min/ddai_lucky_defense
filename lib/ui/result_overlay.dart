import 'package:flutter/material.dart';

import '../game/components/render_utils.dart';
import '../game/data/balance.dart';
import '../game/data/rarity.dart';
import '../game/game_state.dart';
import '../game/lucky_defense_game.dart';
import 'theme.dart';

/// 판이 끝나면 뜨는 결과 화면. 클리어와 패배를 함께 다룬다.
class ResultOverlay extends StatelessWidget {
  const ResultOverlay({super.key, required this.game});

  final LuckyDefenseGame game;

  @override
  Widget build(BuildContext context) {
    final GameState state = game.state;
    final bestRarity =
        Rarity.values[state.bestRarityTier.clamp(0, Rarity.values.length - 1)];
    final cleared = state.isCleared;
    final accent = cleared ? GameColors.gold : GameColors.life;

    // 뒤쪽 HUD/조작 패널이 눌리지 않도록 포인터를 흡수한다.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.78),
        child: Center(
          child: SingleChildScrollView(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 26),
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
              decoration: BoxDecoration(
                color: GameColors.panel,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: accent.withValues(alpha: 0.6)),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.18),
                    blurRadius: 30,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    cleared ? '🏆' : '💀',
                    style: const TextStyle(fontSize: 42),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    cleared ? '정복 완료!' : '방어 실패',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    cleared
                        ? '${Balance.clearWave} 웨이브를 모두 막아냈습니다'
                        : '${state.wave} 웨이브에서 무너졌습니다',
                    style: const TextStyle(
                      color: GameColors.sub,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (state.isNewRecord) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: GameColors.gold.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: GameColors.gold),
                      ),
                      child: const Text(
                        '신기록 달성!',
                        style: TextStyle(
                          color: GameColors.gold,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  _ResultRow(label: '도달 웨이브', value: '${state.wave}'),
                  _ResultRow(
                    label: '처치한 몬스터',
                    value: formatNumber(state.totalKills),
                  ),
                  _ResultRow(label: '소환 횟수', value: '${state.totalSummons}'),
                  _ResultRow(label: '합성 횟수', value: '${state.totalMerges}'),
                  // 어려움에서만 나오는 줄. 이 판의 운을 한 숫자로 보여 준다.
                  if (state.failedMerges > 0)
                    _ResultRow(
                      label: '합성 실패',
                      value: '${state.failedMerges}',
                      valueColor: GameColors.life,
                    ),
                  _ResultRow(
                    label: '최고 등급',
                    value: bestRarity.label,
                    valueColor: bestRarity.color,
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: Divider(height: 1, color: GameColors.border),
                  ),
                  _ResultRow(
                    label: '🏆 최고 기록',
                    value: state.best.isEmpty ? '-' : '${state.best.wave} 웨이브',
                    valueColor: GameColors.gold,
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: ActionButton(
                          icon: '🔄',
                          label: '다시 시작',
                          sub: state.mode.label,
                          color: GameColors.accent,
                          filled: true,
                          height: 50,
                          onTap: game.restart,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: ActionButton(
                          label: '모드 선택',
                          height: 50,
                          onTap: () => game.restart(toIntro: true),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: GameColors.sub,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? GameColors.text,
              fontSize: 13.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
