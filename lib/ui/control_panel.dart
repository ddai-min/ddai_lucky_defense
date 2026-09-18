import 'package:flutter/material.dart';

import '../game/components/render_utils.dart';
import '../game/components/unit_component.dart';
import '../game/data/balance.dart';
import '../game/data/rarity.dart';
import '../game/game_state.dart';
import '../game/lucky_defense_game.dart';
import 'codex_sheet.dart';
import 'shortcuts.dart';
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
                  onTap: () => showCodexSheet(context, state.luckLevel, state.mode),
                ),
              if (state.willAutoSell) _AutoSellNotice(state: state),
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

/// 자리가 가득 찼을 때, 소환을 누르면 무엇이 팔려 나가는지 미리 알린다.
///
/// 유닛이 영구히 사라지는 동작이라 누르고 나서 알게 되면 곤란하다.
class _AutoSellNotice extends StatelessWidget {
  const _AutoSellNotice({required this.state});

  final GameState state;

  @override
  Widget build(BuildContext context) {
    final color = state.autoSellRarity?.color ?? GameColors.text;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: GameColors.gold.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: GameColors.gold.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          const Text('♻️', style: TextStyle(fontSize: 11)),
          const SizedBox(width: 6),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: '자리 가득 · 소환하면 '),
                  TextSpan(
                    text: state.autoSellName ?? '',
                    style: TextStyle(color: color, fontWeight: FontWeight.w900),
                  ),
                  const TextSpan(text: ' 자동 판매'),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: GameColors.sub,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '+${formatNumber(state.autoSellRefund)} G',
            style: const TextStyle(
              color: GameColors.gold,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
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
            icon: state.willAutoSell ? '♻️' : '🎲',
            label: '소환',
            sub: '${formatNumber(state.effectiveSummonCost)} G',
            color: GameColors.gold,
            filled: true,
            enabled: state.canSummon,
            shortcut: GameKey.summon,
            onTap: game.summon,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          flex: 4,
          // 무엇이 나올지 미리 보여 준다 — 합성까지 하나 남은 유닛이 있으면
          // 고급소환은 그 유닛을 콕 집어 준다([pickHighSummonTarget]).
          //
          // 이름을 «고급소환» 옆에 덧붙이면 320pt 화면에서 둘 다 잘려 값도
          // 이름도 안 보인다. 그래서 겨냥한 대상이 있으면 이름을 라벨 자리에
          // 그대로 세우고, 정체는 이모지·등급색·💎 값으로 알린다.
          child: ActionButton(
            icon: state.highSummonEmoji,
            label: state.highSummonName ?? '고급소환',
            sub: '${Balance.highSummonGems} 💎',
            color: state.highSummonRarity?.color ?? GameColors.gem,
            enabled: state.canHighSummon,
            shortcut: GameKey.highSummon,
            onTap: game.highSummon,
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
          width: 50,
          label: '자동\n판매',
          active: state.autoSell,
          color: GameColors.gold,
          onTap: () {
            state.autoSell = !state.autoSell;
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

class _UpgradeRow extends StatefulWidget {
  const _UpgradeRow({required this.game});

  final LuckyDefenseGame game;

  @override
  State<_UpgradeRow> createState() => _UpgradeRowState();
}

class _UpgradeRowState extends State<_UpgradeRow> {
  final ScrollController _controller = ScrollController();
  bool _canScrollLeft = false;
  bool _canScrollRight = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_syncArrows);
    // 첫 레이아웃이 끝나야 스크롤 범위를 알 수 있다.
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncArrows());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _syncArrows() {
    if (!mounted || !_controller.hasClients) {
      return;
    }
    final position = _controller.position;
    final left = position.pixels > 1;
    final right = position.pixels < position.maxScrollExtent - 1;
    if (left == _canScrollLeft && right == _canScrollRight) {
      return;
    }
    setState(() {
      _canScrollLeft = left;
      _canScrollRight = right;
    });
  }

  void _nudge(int direction) {
    if (!_controller.hasClients) {
      return;
    }
    final position = _controller.position;
    final target = (position.pixels + direction * 150).clamp(
      0.0,
      position.maxScrollExtent,
    );
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.game.state;
    final game = widget.game;
    return SizedBox(
      height: 46,
      child: NotificationListener<ScrollMetricsNotification>(
        // 창 크기·확대 배율이 바뀌면 스크롤 범위도 달라진다.
        // 레이아웃 도중에 오는 알림이라 프레임이 끝난 뒤에 반영한다.
        onNotification: (_) {
          runAfterFrame(_syncArrows);
          return false;
        },
        child: Stack(
          children: [
            ListView(
              controller: _controller,
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
                  shortcut: GameKey.attack,
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
                  shortcut: GameKey.attackSpeed,
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
                  shortcut: GameKey.goldGain,
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
                  shortcut: GameKey.luck,
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
                  shortcut: GameKey.life,
                  onTap: game.buyLife,
                  levelPrefix: '보유 ',
                ),
              ],
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: _EdgeArrow(
                visible: _canScrollLeft,
                pointsLeft: true,
                onTap: () => _nudge(-1),
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: _EdgeArrow(
                visible: _canScrollRight,
                pointsLeft: false,
                onTap: () => _nudge(1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 가로 목록의 양 끝에 겹쳐 두는 넘김 화살표.
///
/// 아래 내용이 배경색으로 흐려지도록 그라데이션을 깔아, 버튼을 가리는 게 아니라
/// «더 있다» 는 표시로 보이게 한다. 더 넘길 곳이 없으면 사라진다.
class _EdgeArrow extends StatelessWidget {
  const _EdgeArrow({
    required this.visible,
    required this.pointsLeft,
    required this.onTap,
  });

  final bool visible;
  final bool pointsLeft;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 160),
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 38,
            alignment: pointsLeft
                ? Alignment.centerLeft
                : Alignment.centerRight,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: pointsLeft
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
                end: pointsLeft ? Alignment.centerRight : Alignment.centerLeft,
                colors: [
                  GameColors.panel,
                  GameColors.panel.withValues(alpha: 0),
                ],
                stops: const [0.5, 1],
              ),
            ),
            child: Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: GameColors.panelSoft,
                shape: BoxShape.circle,
                border: Border.all(color: GameColors.border),
              ),
              child: Icon(
                pointsLeft ? Icons.chevron_left : Icons.chevron_right,
                size: 17,
                color: GameColors.text,
              ),
            ),
          ),
        ),
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
    required this.shortcut,
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

  /// 이 버튼을 누르는 키보드 단축키.
  final GameKey shortcut;

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
              color: enabled ? color.withValues(alpha: 0.6) : GameColors.border,
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
                  if (hasPhysicalKeyboard) ...[
                    const SizedBox(width: 5),
                    KeyCap(shortcut, enabled: enabled),
                  ],
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
                      '${Rarity.values[i].label} ${rates[i].toStringAsFixed(rates[i] < 10 ? 1 : 0)}%',
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
    // 어려움의 초월 합성은 도박이다. 누르기 전에 확률과 잃는 개수를 보여 준다.
    final chance = game.mergeChanceOf(spec);
    final gamble = chance < 1;

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
                  'DPS ${formatNumber(spec.dps * game.state.damageMultiplierOf(spec.rarity) * game.state.attackSpeedMultiplier)}'
                  '  ·  보유 $count개  ·  '
                  '${gamble ? '합성 실패 시 ${Balance.mergeFailLoss}기 소멸' : spec.skillText}',
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
            label: gamble ? '도박' : '합성',
            sub: gamble
                ? '${(chance * 100).round()}%'
                : '$count/${Balance.mergeCount}',
            color: gamble ? GameColors.life : GameColors.green,
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
          border: Border.all(color: enabled ? color : GameColors.border),
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
