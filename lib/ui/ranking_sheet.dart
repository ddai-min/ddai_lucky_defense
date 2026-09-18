import 'package:flutter/material.dart';

import '../game/data/game_mode.dart';
import '../game/leaderboard.dart';
import 'theme.dart';

/// 모드별 랭킹을 보여주는 바텀시트.
Future<void> showRankingSheet(
  BuildContext context,
  Leaderboard leaderboard, {
  GameMode? initialMode,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: GameColors.panel,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (context) => _RankingSheet(
      leaderboard: leaderboard,
      initialMode: initialMode?.hasRanking == true
          ? initialMode!
          : GameMode.hard,
    ),
  );
}

class _RankingSheet extends StatefulWidget {
  const _RankingSheet({required this.leaderboard, required this.initialMode});

  final Leaderboard leaderboard;
  final GameMode initialMode;

  @override
  State<_RankingSheet> createState() => _RankingSheetState();
}

class _RankingSheetState extends State<_RankingSheet> {
  late GameMode _mode = widget.initialMode;
  late Future<List<RankEntry>> _entries = _load();

  Future<List<RankEntry>> _load() => widget.leaderboard.top(_mode);

  void _select(GameMode mode) {
    if (mode == _mode) {
      return;
    }
    setState(() {
      _mode = mode;
      _entries = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ranked = GameMode.values.where((m) => m.hasRanking).toList();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                const Text('🏆', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                const Text(
                  '랭킹',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Spacer(),
                for (final mode in ranked) ...[
                  if (mode != ranked.first) const SizedBox(width: 6),
                  _ModeChip(
                    mode: mode,
                    selected: mode == _mode,
                    onTap: () => _select(mode),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<RankEntry>>(
              future: _entries,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }
                final entries = snapshot.data ?? const <RankEntry>[];
                if (entries.isEmpty) {
                  return const _Empty();
                }
                return ListView.builder(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                  itemCount: entries.length,
                  itemBuilder: (context, index) =>
                      _RankRow(rank: index + 1, entry: entries[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 30),
        child: Text(
          '아직 아무도 기록을 올리지 않았습니다.\n첫 줄을 차지해 보세요.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: GameColors.sub,
            fontSize: 12.5,
            height: 1.6,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final GameMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = mode.isEndless ? GameColors.accent : GameColors.life;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.18) : GameColors.panelSoft,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: selected ? color : GameColors.border,
            width: selected ? 1.5 : 1.2,
          ),
        ),
        child: Text(
          '${mode.icon} ${mode.label}',
          style: TextStyle(
            color: selected ? Colors.white : GameColors.sub,
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({required this.rank, required this.entry});

  final int rank;
  final RankEntry entry;

  @override
  Widget build(BuildContext context) {
    // 1·2·3등만 색으로 구분한다. 그 아래는 줄만 세도 충분하다.
    final medal = switch (rank) {
      1 => GameColors.gold,
      2 => const Color(0xFFC8D2E4),
      3 => const Color(0xFFCD8A54),
      _ => GameColors.sub,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: rank <= 3
              ? medal.withValues(alpha: 0.10)
              : GameColors.panelSoft,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: rank <= 3 ? medal.withValues(alpha: 0.5) : GameColors.border,
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text(
                '$rank',
                style: TextStyle(
                  color: medal,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Expanded(
              child: Text(
                entry.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: GameColors.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              '${entry.wave} 웨이브',
              style: TextStyle(
                color: medal,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
