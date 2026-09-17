import 'package:flutter/material.dart';

import '../game/components/render_utils.dart';
import '../game/components/unit_component.dart';
import '../game/data/balance.dart';
import '../game/data/rarity.dart';
import '../game/game_state.dart';
import '../game/lucky_defense_game.dart';
import 'codex_sheet.dart';
import 'theme.dart';

/// 하단 조작 패널: 소환 / 합성 / 강화 + 선택한 유닛 정보.
class ControlPanel extends StatelessWidget {
  const ControlPanel({super.key, required this.game});

  final LuckyDefenseGame game;

  GameState get state => game.state;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        final selected = game.selected;
        return Container(
          decoration: const BoxDecoration(
            color: GameColors.panel,
            border: Border(top: BorderSide(color: GameColors.border)),
          ),
          padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected != null)
                _SelectionCard(game: game, unit: selected)
              else
                _RatesStrip(
                  luckLevel: state.luckLevel,
                  onTap: () => showCodexSheet(context, state.luckLevel),
                ),
              const SizedBox(height: 8),
              _ActionRow(game: game),
              const SizedBox(height: 8),
              _UpgradeRow(game: game),
            ],
          ),
        );
      },
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.game});

  final LuckyDefenseGame game;

  @override
  Widget build(BuildContext context) {
    final state = game.state;
    return Row(
      children: [
        Expanded(
          flex: 5,
          child: ActionButton(
            icon: '🎲',
            label: '소환',
            sub: '${formatNumber(state.summonCost)} G',
            color: GameColors.gold,
            filled: true,
            enabled: state.canSummon,
            onTap: game.summon,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          flex: 4,
          child: ActionButton(
            label: '고급소환',
            sub: '${Balance.highSummonGems} 💎',
            color: GameColors.gem,
            enabled: state.canHighSummon,
            onTap: game.highSummon,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          flex: 4,
          child: ActionButton(
            label: '합성',
            sub: state.mergeableGroups > 0
                ? '${state.mergeableGroups}조합'
                : '3개↑',
            color: GameColors.green,
            enabled: state.mergeableGroups > 0,
            badge: state.mergeableGroups > 0 ? '${state.mergeableGroups}' : null,
            onTap: game.mergeAll,
          ),
        ),
        const SizedBox(width: 6),
        ToggleChip(
          width: 50,
          label: '자동\n합성',
          active: state.autoMerge,
          color: GameColors.green,
          onTap: () {
            state.autoMerge = !state.autoMerge;
            state.notify();
          },
        ),
        const SizedBox(width: 6),
        ToggleChip(
          width: 44,
          label: '×${state.speedMultiplier}',
          active: state.speedMultiplier > 1,
          onTap: () {
            state.speedMultiplier = state.speedMultiplier % 3 + 1;
            state.notify();
          },
        ),
      ],
    );
  }
}

class _UpgradeRow extends StatelessWidget {
  const _UpgradeRow({required this.game});

  final LuckyDefenseGame game;

  @override
  Widget build(BuildContext context) {
    final state = game.state;
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        children: [
          _UpgradeButton(
            icon: '⚔️',
            title: '공격력',
            level: state.atkLevel,
            effect: '×${state.damageMultiplier.toStringAsFixed(2)}',
            cost: '${formatNumber(state.atkCost)} G',
            color: GameColors.life,
            enabled: state.gold >= state.atkCost,
            onTap: game.upgradeAttack,
          ),
          _UpgradeButton(
            icon: '⚡',
            title: '공격속도',
            level: state.spdLevel,
            effect: '×${state.attackSpeedMultiplier.toStringAsFixed(2)}',
            cost: '${formatNumber(state.spdCost)} G',
            color: GameColors.accent,
            enabled: state.gold >= state.spdCost,
            onTap: game.upgradeSpeed,
          ),
          _UpgradeButton(
            icon: '💰',
            title: '골드획득',
            level: state.goldLevel,
            effect: '×${state.goldMultiplier.toStringAsFixed(2)}',
            cost: '${formatNumber(state.goldCost)} G',
            color: GameColors.gold,
            enabled: state.gold >= state.goldCost,
            onTap: game.upgradeGold,
          ),
          _UpgradeButton(
            icon: '🍀',
            title: '행운',
            level: state.luckLevel,
            effect: state.luckMaxed ? 'MAX' : '상위등급↑',
            cost: state.luckMaxed ? '-' : '${state.luckCost} 💎',
            color: GameColors.green,
            enabled: !state.luckMaxed && state.gems >= state.luckCost,
            onTap: game.upgradeLuck,
          ),
          _UpgradeButton(
            icon: '❤️',
            title: '라이프',
            level: state.lives,
            effect: '+1',
            cost: '${Balance.reviveGems} 💎',
            color: GameColors.gem,
            enabled: state.gems >= Balance.reviveGems,
            onTap: game.buyLife,
            levelPrefix: '보유 ',
          ),
        ],
      ),
    );
  }
}

class _UpgradeButton extends StatelessWidget {
  const _UpgradeButton({
    required this.icon,
    required this.title,
    required this.level,
    required this.effect,
    required this.cost,
    required this.color,
    required this.enabled,
    required this.onTap,
    this.levelPrefix = 'Lv.',
  });

  final String icon;
  final String title;
  final int level;
  final String effect;
  final String cost;
  final Color color;
  final bool enabled;
  final String levelPrefix;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: GameColors.panelSoft,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: enabled
                  ? color.withValues(alpha: 0.6)
                  : GameColors.border,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(icon, style: const TextStyle(fontSize: 11)),
                  const SizedBox(width: 4),
                  Text(
                    title,
                    style: TextStyle(
                      color: enabled ? GameColors.text : GameColors.sub,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '$levelPrefix$level',
                    style: const TextStyle(
                      color: GameColors.sub,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Text(
                    cost,
                    style: TextStyle(
                      color: enabled ? color : GameColors.sub,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    effect,
                    style: const TextStyle(
                      color: GameColors.sub,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 현재 소환 확률을 한 줄로 보여주는 막대.
class _RatesStrip extends StatelessWidget {
  const _RatesStrip({required this.luckLevel, required this.onTap});

  final int luckLevel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rates = Balance.summonRates(luckLevel);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 54),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: GameColors.panelSoft,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: GameColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  '소환 확률',
                  style: TextStyle(
                    color: GameColors.text,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '행운 Lv.$luckLevel',
                  style: const TextStyle(
                    color: GameColors.green,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                const Text(
                  '도감 보기 ›',
                  style: TextStyle(
                    color: GameColors.accent,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 7,
                child: Row(
                  children: [
                    for (var i = 0; i < rates.length; i++)
                      Expanded(
                        flex: (rates[i] * 100).round().clamp(1, 1000000),
                        child: ColoredBox(color: Rarity.values[i].color),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
              children: [
                for (var i = 0; i < rates.length; i++) ...[
                  if (i > 0) const SizedBox(width: 7),
                  Text(
                    '${Rarity.values[i].label} ${rates[i].toStringAsFixed(
                      rates[i] < 10 ? 1 : 0,
                    )}%',
                    style: TextStyle(
                      color: Rarity.values[i].color,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 선택한 유닛의 상세 정보 + 판매/합성.
class _SelectionCard extends StatelessWidget {
  const _SelectionCard({required this.game, required this.unit});

  final LuckyDefenseGame game;
  final UnitComponent unit;

  @override
  Widget build(BuildContext context) {
    final spec = unit.spec;
    final count = game.unitCounts[spec.id] ?? 0;
    final canMerge = count >= Balance.mergeCount && spec.rarity.next != null;

    return Container(
      constraints: const BoxConstraints(minHeight: 54),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: spec.rarity.deep.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: spec.rarity.color.withValues(alpha: 0.75)),
      ),
      child: Row(
        children: [
          Text(spec.emoji, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        spec.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    _Tag(text: spec.rarity.label, color: spec.rarity.color),
                    const SizedBox(width: 4),
                    _Tag(text: spec.style.label, color: spec.style.color),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'DPS ${formatNumber(spec.dps * game.state.damageMultiplier * game.state.attackSpeedMultiplier)}'
                  '  ·  보유 $count개  ·  ${spec.skillText}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: GameColors.sub,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          _MiniButton(
            label: '합성',
            sub: '$count/${Balance.mergeCount}',
            color: GameColors.green,
            enabled: canMerge,
            onTap: () => game.mergeOnce(specId: spec.id),
          ),
          const SizedBox(width: 5),
          _MiniButton(
            label: '판매',
            sub: '+${formatNumber(spec.sellPrice)}',
            color: GameColors.gold,
            enabled: true,
            onTap: () => game.sellUnit(unit),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 8.5,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({
    required this.label,
    required this.sub,
    required this.color,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final String sub;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 52,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled
              ? color.withValues(alpha: 0.18)
              : Colors.black.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: enabled ? color : GameColors.border,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                color: enabled ? Colors.white : GameColors.sub,
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
                height: 1.1,
              ),
            ),
            Text(
              sub,
              style: TextStyle(
                color: enabled ? color : GameColors.sub,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
