import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'data/balance.dart';
import 'data/game_mode.dart';
import 'data/rarity.dart';
import 'record_store.dart';

export 'data/game_mode.dart';

enum GamePhase { ready, playing, gameOver, cleared }

/// HUD/컨트롤 패널이 구독하는 게임 진행 상태.
class GameState extends ChangeNotifier {
  int gold = Balance.startGold;
  int gems = Balance.startGems;
  int lives = Balance.startLives;

  /// 현재 진행 중인 웨이브 번호(0이면 아직 시작 전).
  int wave = 0;

  /// 다음 웨이브까지 남은 시간(초).
  double waveCountdown = Balance.firstWaveDelay;

  int atkLevel = 0;
  int spdLevel = 0;
  int goldLevel = 0;
  int luckLevel = 0;

  bool autoMerge = false;

  /// 자리가 없을 때 가장 낮은 등급을 자동으로 팔지 여부.
  bool autoSell = true;

  /// 일시정지. 켜지면 게임 루프가 통째로 멈춘다.
  bool paused = false;

  int speedMultiplier = 1;
  GamePhase phase = GamePhase.ready;

  /// 인트로에서 고른 플레이 방식. 다시 시작해도 유지된다.
  GameMode mode = GameMode.easy;

  /// 인트로를 닫고 실제로 전투가 시작됐는지.
  bool started = false;

  int unitCount = 0;
  int slotCount = 0;

  /// 지금 바로 합성 가능한 조합의 수.
  int mergeableGroups = 0;

  /// 자리가 없을 때 자동으로 팔릴 유닛. 유닛이 하나도 없으면 null.
  String? autoSellName;
  Rarity? autoSellRarity;
  int autoSellRefund = 0;

  /// 고급소환이 콕 집어 줄 유닛([pickHighSummonTarget]). 없으면 null —
  /// 그때는 유니크 이상 무작위다.
  String? highSummonName;
  String? highSummonEmoji;
  Rarity? highSummonRarity;

  int totalKills = 0;
  int totalSummons = 0;
  int totalMerges = 0;

  /// 어려움에서 초월 합성에 실패한 횟수([Balance.mergeChance]).
  int failedMerges = 0;
  int bestRarityTier = 0;

  /// 기기에 저장된 최고 기록. 판을 다시 시작해도 유지된다.
  BestRecord best = const BestRecord();

  /// 이번 판에서 최고 기록을 갈아치웠는지.
  bool isNewRecord = false;

  /// 보스 상태(없으면 null).
  String? bossName;
  double bossHpRatio = 0;

  String? toastMessage;
  int toastColor = 0xFFFFFFFF;
  double _toastTimer = 0;

  bool _disposed = false;
  bool _notifyScheduled = false;

  bool get isGameOver => phase == GamePhase.gameOver;
  bool get isCleared => phase == GamePhase.cleared;

  /// 이겼든 졌든 판이 끝났는지.
  bool get isFinished => isGameOver || isCleared;

  /// 클리어 모드의 마지막 웨이브에 들어섰는지. 여기서는 다음 웨이브가 없다.
  bool get isFinalWave => !mode.isEndless && wave >= Balance.clearWave;
  int get summonCost => Balance.summonCost(unitCount);
  bool get slotsFull => unitCount >= slotCount && slotCount > 0;

  /// 소환을 누르면 자동 판매가 함께 일어나는 상태인지.
  bool get willAutoSell => autoSell && slotsFull && autoSellName != null;

  /// 자동 판매까지 감안한 실제 소환 비용.
  ///
  /// 한 기를 팔면 보유 수가 하나 줄어 소환 비용도 그만큼 내려간다.
  int get effectiveSummonCost =>
      willAutoSell ? Balance.summonCost(unitCount - 1) : summonCost;

  bool get canSummon {
    if (isFinished) {
      return false;
    }
    if (!slotsFull) {
      return gold >= summonCost;
    }
    // 자리가 없으면 가장 낮은 등급을 판 값까지 합쳐 계산한다.
    return willAutoSell && gold + autoSellRefund >= effectiveSummonCost;
  }

  bool get canHighSummon =>
      gems >= Balance.highSummonGems &&
      !isFinished &&
      (!slotsFull || willAutoSell);

  int get atkCost => Balance.atkUpgradeCost(atkLevel);
  int get spdCost => Balance.spdUpgradeCost(spdLevel);
  int get goldCost => Balance.goldUpgradeCost(goldLevel);
  int get luckCost => Balance.luckCost(luckLevel);
  bool get luckMaxed => luckLevel >= Balance.luckMaxLevel;

  double get damageMultiplier => Balance.atkBonus(atkLevel);

  /// [rarity] 유닛이 받는 피해 배수. 강화에 모드 보정까지 곱한 값이다.
  double damageMultiplierOf(Rarity rarity) =>
      damageMultiplier * Balance.rarityDamageBonus(rarity.index, mode);
  double get attackSpeedMultiplier => Balance.spdBonus(spdLevel);
  double get goldMultiplier => Balance.goldBonus(goldLevel);

  void reset() {
    gold = Balance.startGold;
    gems = Balance.startGems;
    lives = Balance.startLives;
    wave = 0;
    waveCountdown = Balance.firstWaveDelay;
    atkLevel = 0;
    spdLevel = 0;
    goldLevel = 0;
    luckLevel = 0;
    autoMerge = false;
    autoSell = true;
    paused = false;
    speedMultiplier = 1;
    phase = GamePhase.playing;
    started = true;
    // mode(플레이 방식)는 판을 넘어 유지된다.
    unitCount = 0;
    mergeableGroups = 0;
    autoSellName = null;
    autoSellRarity = null;
    autoSellRefund = 0;
    highSummonName = null;
    highSummonEmoji = null;
    highSummonRarity = null;
    totalKills = 0;
    totalSummons = 0;
    totalMerges = 0;
    failedMerges = 0;
    bestRarityTier = 0;
    // best(최고 기록)는 판을 넘어 유지된다.
    isNewRecord = false;
    bossName = null;
    bossHpRatio = 0;
    toastMessage = null;
    _toastTimer = 0;
    notify();
  }

  void showToast(String message, {int color = 0xFFFFFFFF}) {
    toastMessage = message;
    toastColor = color;
    _toastTimer = 2.0;
    notify();
  }

  /// 매 프레임 호출. 토스트 만료 시에만 알림을 보낸다.
  void tickToast(double dt) {
    if (_toastTimer <= 0) {
      return;
    }
    _toastTimer -= dt;
    if (_toastTimer <= 0) {
      toastMessage = null;
      notify();
    }
  }

  /// 프레임 빌드/레이아웃 도중에 호출돼도 안전한 알림.
  ///
  /// Flame의 GameWidget은 `update()`를 LayoutBuilder 콜백 안에서 실행한다.
  /// 그 시점에 바로 notifyListeners()를 부르면
  /// "setState() called during build" 오류가 나므로 프레임 종료 후로 미룬다.
  void notify() {
    if (_disposed) {
      return;
    }
    if (!isInBuildPhase) {
      notifyListeners();
      return;
    }
    if (_notifyScheduled) {
      return;
    }
    _notifyScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _notifyScheduled = false;
      if (!_disposed) {
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// 지금이 위젯 빌드/레이아웃/페인트 단계인지.
bool get isInBuildPhase =>
    SchedulerBinding.instance.schedulerPhase ==
    SchedulerPhase.persistentCallbacks;

/// 빌드 단계라면 프레임이 끝난 뒤에 실행한다.
void runAfterFrame(VoidCallback action) {
  if (!isInBuildPhase) {
    action();
    return;
  }
  SchedulerBinding.instance.addPostFrameCallback((_) => action());
}
