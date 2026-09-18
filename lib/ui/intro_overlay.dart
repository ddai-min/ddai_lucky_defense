import 'package:flutter/material.dart';

import '../game/data/balance.dart';
import '../game/game_state.dart';
import '../game/lucky_defense_game.dart';
import 'ranking_sheet.dart';
import 'theme.dart';

/// 첫 진입 시 규칙을 알려주는 화면.
class IntroOverlay extends StatelessWidget {
  const IntroOverlay({super.key, required this.game});

  final LuckyDefenseGame game;

  @override
  Widget build(BuildContext context) {
    // 뒤쪽 HUD/조작 패널이 눌리지 않도록 포인터를 흡수한다.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.82),
        child: Center(
          child: SingleChildScrollView(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 22),
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              decoration: BoxDecoration(
                color: GameColors.panel,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: GameColors.accent.withValues(alpha: 0.55),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('🎲', style: TextStyle(fontSize: 38)),
                  const SizedBox(height: 6),
                  const Text(
                    '운빨 디펜스',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 3),
                  const Text(
                    '뽑고, 합치고, 막아내세요',
                    style: TextStyle(
                      color: GameColors.sub,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (!game.state.best.isEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: GameColors.gold.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                          color: GameColors.gold.withValues(alpha: 0.55),
                        ),
                      ),
                      child: Text(
                        '🏆 최고 기록 ${game.state.best.wave} 웨이브',
                        style: const TextStyle(
                          color: GameColors.gold,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  const _Rule(
                    icon: '🎰',
                    title: '소환은 전부 운',
                    body: '골드로 유닛을 뽑습니다. 보유 유닛이 많을수록 소환 비용이 올라갑니다.',
                  ),
                  const _Rule(
                    icon: '✨',
                    title: '같은 유닛 3개 = 합성',
                    body: '같은 유닛을 3개 모으면 상위 등급 유닛 1개로 바뀝니다. 슬롯도 아낍니다.',
                  ),
                  const _Rule(
                    icon: '🛡️',
                    title: '경로를 한 바퀴 돌면 실점',
                    body: '몬스터가 🌀에서 나와 🏰에 닿으면 라이프가 깎입니다.',
                  ),
                  _Rule(
                    icon: '👹',
                    title: '${Balance.bossEvery}웨이브마다 보스',
                    body: '보스를 잡으면 다이아를 얻습니다. 다이아로 행운을 올려 고등급 확률을 높이세요.',
                  ),
                  const _Rule(
                    icon: '👆',
                    title: '조작',
                    body: '유닛을 탭하면 정보·판매·합성, 드래그하면 자리를 바꿉니다.',
                  ),
                  const SizedBox(height: 6),
                  // 모드가 넷이라 한 줄에 세우면 320pt 화면에서 카드가 뭉개진다.
                  for (var i = 0; i < GameMode.values.length; i += 2) ...[
                    if (i > 0) const SizedBox(height: 8),
                    Row(
                      children: [
                        for (final mode in GameMode.values.skip(i).take(2)) ...[
                          if (mode != GameMode.values[i])
                            const SizedBox(width: 8),
                          Expanded(
                            child: _ModeCard(
                              mode: mode,
                              selected: game.state.mode == mode,
                              onTap: () => game.setMode(mode),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                  if (game.state.mode == GameMode.hard) ...[
                    const SizedBox(height: 9),
                    const _GambleNote(),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ActionButton(
                          icon: '▶️',
                          label: '시작하기',
                          color: GameColors.green,
                          filled: true,
                          height: 50,
                          onTap: game.startGame,
                        ),
                      ),
                      // 랭킹은 어려움·무한에만 있고, 설정이 없는 빌드에서는
                      // 버튼 자체를 내보내지 않는다.
                      if (game.leaderboard.isAvailable) ...[
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 96,
                          child: ActionButton(
                            icon: '🏆',
                            label: '랭킹',
                            height: 50,
                            onTap: () => showRankingSheet(
                              context,
                              game.leaderboard,
                              initialMode: game.state.mode,
                            ),
                          ),
                        ),
                      ],
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

/// 플레이 방식 하나를 고르는 카드.
class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final GameMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = switch (mode) {
      GameMode.endless => GameColors.accent,
      GameMode.hard => GameColors.life,
      _ => GameColors.green,
    };
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.18)
              : GameColors.panelSoft,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: selected ? color : GameColors.border,
            width: selected ? 1.8 : 1.2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 카드 셋이 나란히 서므로 320pt 같은 좁은 화면에서는 폭이 빠듯하다.
            // 말줄임표로 잘리는 대신 통째로 조금 줄어들게 한다.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  Text(mode.icon, style: const TextStyle(fontSize: 13)),
                  const SizedBox(width: 5),
                  Text(
                    mode.label,
                    style: TextStyle(
                      color: selected ? Colors.white : GameColors.sub,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (selected) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.check_circle_rounded, size: 13, color: color),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 3),
            Text(
              mode.isEndless
                  ? '끝없이 · ${mode.tagline}'
                  : '${Balance.clearWave(mode)} 웨이브 · ${mode.tagline}',
              maxLines: 2,
              style: TextStyle(
                color: selected ? color : GameColors.sub,
                fontSize: 9.5,
                height: 1.3,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 어려움을 고른 동안만 뜨는 규칙 안내. 이 모드만 합성 규칙이 다르다.
class _GambleNote extends StatelessWidget {
  const _GambleNote();

  @override
  Widget build(BuildContext context) {
    final chance = (Balance.hardMergeChance * 100).round();
    final bonus = Balance.hardTopTierDamage.toStringAsFixed(0);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: GameColors.life.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: GameColors.life.withValues(alpha: 0.5)),
      ),
      child: Text(
        '🎲 어려움에서는 신화 3개를 초월로 올리는 합성이 $chance% 도박입니다. '
        '실패하면 ${Balance.mergeFailLoss}기가 사라지고, 성공하면 공격력이 '
        '$bonus배인 초월이 나옵니다. 초월을 몇 기 세웠느냐로 판이 갈립니다.',
        style: const TextStyle(
          color: GameColors.life,
          fontSize: 10.5,
          height: 1.4,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule({required this.icon, required this.title, required this.body});

  final String icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(icon, style: const TextStyle(fontSize: 17)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: GameColors.text,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  body,
                  style: const TextStyle(
                    color: GameColors.sub,
                    fontSize: 11,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
