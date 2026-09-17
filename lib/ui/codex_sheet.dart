import 'package:flutter/material.dart';

import '../game/components/render_utils.dart';
import '../game/data/balance.dart';
import '../game/data/rarity.dart';
import '../game/data/unit_catalog.dart';
import 'theme.dart';

/// 소환 확률과 전체 유닛 도감을 보여주는 바텀시트.
Future<void> showCodexSheet(BuildContext context, int luckLevel) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: GameColors.panel,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (context) => _CodexSheet(luckLevel: luckLevel),
  );
}

class _CodexSheet extends StatelessWidget {
  const _CodexSheet({required this.luckLevel});

  final int luckLevel;

  @override
  Widget build(BuildContext context) {
    final rates = Balance.summonRates(luckLevel);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.92,
      builder: (context, controller) => Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: GameColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Text(
                  '유닛 도감 & 소환 확률',
                  style: TextStyle(
                    color: GameColors.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '행운 Lv.$luckLevel · 같은 유닛 ${Balance.mergeCount}개를 모으면 '
                '다음 등급으로 합성됩니다.',
                style: const TextStyle(
                  color: GameColors.sub,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              children: [
                for (final rarity in Rarity.values)
                  _RaritySection(
                    rarity: rarity,
                    rate: rarity.index < rates.length
                        ? rates[rarity.index]
                        : null,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RaritySection extends StatelessWidget {
  const _RaritySection({required this.rarity, required this.rate});

  final Rarity rarity;
  final double? rate;

  @override
  Widget build(BuildContext context) {
    final units = kUnitsByRarity[rarity] ?? const <UnitSpec>[];
    if (units.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: rarity.deep.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: rarity.color.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 15,
                decoration: BoxDecoration(
                  color: rarity.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 7),
              Text(
                rarity.label,
                style: TextStyle(
                  color: rarity.color,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              Text(
                rate != null
                    ? '소환 확률 ${rate!.toStringAsFixed(rate! < 10 ? 2 : 1)}%'
                    : '합성 전용',
                style: TextStyle(
                  color: rate != null ? GameColors.sub : GameColors.green,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final unit in units) _UnitRow(unit: unit),
        ],
      ),
    );
  }
}

class _UnitRow extends StatelessWidget {
  const _UnitRow({required this.unit});

  final UnitSpec unit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: unit.rarity.color.withValues(alpha: 0.5),
              ),
            ),
            child: Text(unit.emoji, style: const TextStyle(fontSize: 18)),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      unit.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: unit.style.color.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        unit.style.label,
                        style: TextStyle(
                          color: unit.style.color,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 1),
                Text(
                  unit.skillText,
                  style: const TextStyle(
                    color: GameColors.sub,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'DPS ${formatNumber(unit.dps)}',
                style: const TextStyle(
                  color: GameColors.text,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                '판매 ${formatNumber(unit.sellPrice)} G',
                style: const TextStyle(
                  color: GameColors.sub,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
