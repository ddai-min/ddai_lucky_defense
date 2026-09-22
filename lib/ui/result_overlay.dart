import 'package:flutter/material.dart';

import '../game/components/render_utils.dart';
import '../game/data/balance.dart';
import '../game/data/rarity.dart';
import '../game/game_state.dart';
import '../game/leaderboard.dart';
import '../game/lucky_defense_game.dart';
import 'ranking_sheet.dart';
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
                    cleared
                        ? '정복 완료!'
                        : state.failedByBossEscape
                        ? '보스 격퇴 실패'
                        : '방어 실패',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    cleared
                        ? '${Balance.clearWave(state.mode)} 웨이브를 모두 막아냈습니다'
                        : state.failedByBossEscape
                        // 라이프가 남아 있는데 진 경우라 이유를 밝혀 준다.
                        ? '마지막 보스를 놓쳤습니다 · 라이프 ${state.lives} 남음'
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
                  if (state.mode.hasRanking && game.leaderboard.isAvailable)
                    _RankSubmit(game: game),
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

/// 결과 화면에서 이름을 받아 랭킹에 올리는 줄.
///
/// 랭킹이 있는 모드(어려움·무한)이고 설정이 된 빌드에서만 뜬다.
class _RankSubmit extends StatefulWidget {
  const _RankSubmit({required this.game});

  final LuckyDefenseGame game;

  @override
  State<_RankSubmit> createState() => _RankSubmitState();
}

class _RankSubmitState extends State<_RankSubmit> {
  final TextEditingController _name = TextEditingController();
  bool _sending = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    // 지난번에 쓴 이름을 채워 둔다. 매판 다시 치게 할 이유가 없다.
    loadRankName().then((saved) {
      if (mounted && saved != null && _name.text.isEmpty) {
        _name.text = saved;
      }
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_sending) {
      return;
    }
    setState(() {
      _sending = true;
      _failed = false;
    });
    final ok = await widget.game.submitRank(_name.text);
    if (!mounted) {
      return;
    }
    setState(() {
      _sending = false;
      _failed = !ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.game.state;
    final done = state.rankSubmitted;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🏆', style: TextStyle(fontSize: 13)),
              const SizedBox(width: 6),
              Text(
                done ? '랭킹에 올렸습니다' : '${state.mode.label} 랭킹에 기록 남기기',
                style: TextStyle(
                  color: done ? GameColors.green : GameColors.sub,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          if (done)
            ActionButton(
              icon: '📋',
              label: '랭킹 보기',
              height: 44,
              onTap: () => showRankingSheet(
                context,
                widget.game.leaderboard,
                initialMode: state.mode,
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _name,
                    maxLength: kMaxRankNameLength,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      counterText: '',
                      hintText: '이름',
                      hintStyle: const TextStyle(
                        color: GameColors.sub,
                        fontSize: 13,
                      ),
                      filled: true,
                      fillColor: GameColors.panelSoft,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(11),
                        borderSide: const BorderSide(color: GameColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(11),
                        borderSide: const BorderSide(color: GameColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(11),
                        borderSide: const BorderSide(color: GameColors.gold),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                SizedBox(
                  width: 92,
                  child: ActionButton(
                    label: _sending ? '올리는 중' : '등록',
                    color: GameColors.gold,
                    filled: true,
                    height: 44,
                    enabled: !_sending,
                    onTap: _submit,
                  ),
                ),
              ],
            ),
          if (_failed) ...[
            const SizedBox(height: 6),
            const Text(
              '등록하지 못했습니다. 이름을 확인하고 다시 눌러 보세요.',
              style: TextStyle(
                color: GameColors.life,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
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
