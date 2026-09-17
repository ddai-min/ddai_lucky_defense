# 운빨 디펜스 (Lucky Defense)

스타크래프트 유즈맵 「메이플 운빨 디펜스」 계열의 **뽑기 기반 랜덤 디펜스** 게임입니다.
Flutter + [Flame](https://flame-engine.org) 게임 엔진으로 만들었고, **이미지 에셋이 전혀 없이**
전부 Canvas 드로잉과 이모지로 렌더링합니다.

**웹에서 바로 플레이** → <https://ddai-min.github.io/ddai_lucky_defense/>

## 실행

```bash
fvm flutter pub get
fvm flutter run            # 또는 ./.fvm/flutter_sdk/bin/flutter run
fvm flutter test           # 게임 로직 + 반응형 레이아웃 테스트
```

세로 화면 기준으로 설계했지만 레이아웃은 화면 크기에 맞춰 계산되므로
폰·태블릿·데스크톱 어디서든 동작합니다.

## 게임 규칙

| 요소 | 내용 |
| --- | --- |
| 소환 | 골드를 내면 **무작위 등급**의 유닛이 빈 슬롯에 배치됩니다. 보유 유닛이 많을수록 소환 비용이 올라갑니다. |
| 슬롯 | 한 줄 6칸 × 3줄 = **18칸 고정**. 화면이 커지면 칸 수가 아니라 칸 크기가 커집니다. |
| 합성 | **같은 유닛 3개** → 상위 등급 유닛 1개. 슬롯도 2칸 비고 전투력은 올라갑니다. |
| 등급 | 노말 → 레어 → 유니크 → 에픽 → 레전더리 → **신화** → **초월** (신화 이상은 합성 전용) |
| 웨이브 | 22초마다 자동 시작. 몬스터는 🌀에서 나와 지그재그 경로를 한 바퀴 돌아 🏰에 닿으면 라이프가 깎입니다. |
| 보스 | 10웨이브마다 등장. 처치하면 다이아를 줍니다. 뚫리면 라이프 5 소모. |
| 러시 | 5·15·25… 웨이브는 체력이 낮은 대신 수가 많고 빠릅니다. |
| 강화 | 골드로 공격력/공격속도/골드획득, 다이아로 **행운**(상위 등급 확률)과 라이프를 올립니다. |
| 최고 기록 | 도달 웨이브 기준으로 기기에 저장됩니다. HUD의 🏆, 인트로, 결과 화면에 표시됩니다. |

**조작** — 유닛 탭: 정보·판매·합성 / 유닛 드래그: 자리 교체 / 빈 곳 탭: 선택 해제

### 유닛 공격 타입

`단일` `광역` `둔화` `중독` `연쇄` `처형`(즉사 확률) `약탈`(골드 추가 획득)

등급이 오를수록 **사거리도 넓어져** 신화 이상은 두 칸 건너 레인까지 닿습니다.
사거리는 화면 픽셀이 아니라 레인 간격(밴드)의 배수로 정의되어 해상도와 무관하게 같은 체감을 줍니다.

## 프로젝트 구조

```
lib/
├─ main.dart                       앱 진입점 · 화면 레이아웃(HUD / 게임 / 조작 패널)
├─ game/
│  ├─ lucky_defense_game.dart      FlameGame 본체 — 웨이브·전투·소환·합성 규칙
│  ├─ field_layout.dart            화면 크기 → 몬스터 경로 + 유닛 슬롯 좌표 계산
│  ├─ game_state.dart              자원/웨이브/강화 상태 (ChangeNotifier)
│  ├─ record_store.dart            최고 기록 영구 저장 (SharedPreferences)
│  ├─ data/
│  │  ├─ balance.dart              ★ 모든 밸런스 수치
│  │  ├─ rarity.dart               등급 정의
│  │  ├─ unit_catalog.dart         유닛 도감 + 소환 추첨
│  │  └─ enemy_catalog.dart        몬스터 · 보스 도감
│  └─ components/                  Flame 컴포넌트 (유닛/몬스터/투사체/이펙트/배경)
└─ ui/                             HUD · 조작 패널 · 도감 시트 · 오버레이
```

## 밸런스 조정

수치는 전부 [`lib/game/data/balance.dart`](lib/game/data/balance.dart) 한 곳에 모여 있습니다.

```dart
static const List<double> damage = [10, 34, 116, 400, 1400, 5200, 21000]; // 등급별 공격력
static double enemyHp(int wave) => 55 * math.pow(1.225, wave - 1);        // 몬스터 체력 곡선
static int summonCost(int unitCount) => 20 + 6 * unitCount;               // 소환 비용
static List<double> summonWeights(int luck) { ... }                       // 등급별 소환 확률
```

유닛을 추가하려면 `unit_catalog.dart`의 `kUnitCatalog`에 `UnitSpec` 한 줄만 넣으면
도감·소환·합성에 자동으로 반영됩니다.

## 웹 배포

GitHub Pages 에 올라간다. `main` 에 푸시하면
[`.github/workflows/web-deploy.yml`](.github/workflows/web-deploy.yml) 이
analyze · test 를 돌린 뒤 빌드해서 배포한다. 수동으로 돌리려면 Actions 탭의
«웹 배포» 에서 *Run workflow*.

저장소 이름이 경로에 붙는 주소이므로 `--base-href "/<저장소 이름>/"` 가 필요하다.
이걸 빼면 `flutter_bootstrap.js` 를 루트에서 찾다가 404 가 나고 빈 화면만 보인다.
로컬에서 같은 조건으로 확인하려면:

```sh
fvm flutter build web --release --base-href /ddai_lucky_defense/
mkdir -p /tmp/pages && cp -R build/web /tmp/pages/ddai_lucky_defense
(cd /tmp/pages && python3 -m http.server 8098)
# → http://127.0.0.1:8098/ddai_lucky_defense/
```

콜드 로딩은 약 4.7MB다. 자체 호스팅하는 건 `main.dart.js` 뿐이고(2.1MB, gzip 0.6MB),
나머지는 gstatic CDN 에서 온다 — CanvasKit 2.8MB(brotli), Noto Color Emoji 0.69MB,
Noto Sans Symbols2 0.37MB, Noto Sans KR 0.17MB. 두 번째 방문부터는 캐시를 쓴다.

한글 글꼴을 앱에 넣지 않은 이유: 이 게임은 유닛·몬스터가 전부 이모지라 어차피
Noto Color Emoji 가 필요한데, 그건 10MB짜리라 번들이 현실적이지 않다. gstatic 이
막히면 이모지부터 깨지므로, 한글만 번들해도 얻는 게 없다. 대신 Flutter 가 첫
프레임을 그릴 때까지 몇 초가 걸리므로 `web/index.html` 에 HTML/CSS 만으로 즉시 뜨는
로딩 화면을 깔아 두었다.

## 구현 노트

- **카메라 미사용** — 모든 컴포넌트를 `fieldRoot` 아래 화면 좌표 그대로 배치해 좌표 계산이 단순합니다.
  화면 흔들림은 `fieldRoot.position`을 흔들어 처리합니다.
- **`update()` 안에서 `notifyListeners()` 금지** — Flame의 `GameWidget`은 `update()`를
  `LayoutBuilder` 콜백(빌드 단계) 안에서 호출합니다. 그래서 `GameState.notify()`는
  빌드 중이면 프레임 종료 후로 알림을 미룹니다.
- **리사이즈 가드** — `onGameResize`는 위젯이 리빌드될 때마다 호출되므로,
  크기가 실제로 달라졌을 때만 경로·슬롯을 다시 계산합니다.
- **렌더 캐시** — 그라데이션 셰이더, 점선 슬롯 경로, 배경 격자, 이모지 `TextPainter`를
  캐시해 프레임마다 재생성하지 않습니다.
- **배속(×2/×3)** 은 dt를 키우는 대신 서브스텝을 여러 번 돌려 투사체가 적을 건너뛰지 않게 합니다.
- **넓은 화면** 에서는 앱을 480 폭으로 가운데 세웁니다. 세로 화면 기준으로 만든 게임이라
  그대로 늘리면 필드가 납작해지고 버튼만 길어집니다.
- **슬롯 격자는 고정** 입니다(`FieldLayout.slotCols` · `slotRows`). 화면에 맞춰 칸 수를
  늘리면 기기나 브라우저 확대 배율에 따라 놓을 수 있는 유닛 수가 달라져 난이도가
  통째로 바뀝니다. 칸 수는 고정하고 칸 크기만 늘립니다.
- **스크롤은 마우스로도** 끌립니다(`AppScrollBehavior`). Flutter 기본값은 터치·스타일러스만
  드래그로 인정해서, 웹에서는 가로 목록을 마우스로 잡아끌어도 움직이지 않습니다.
- **최고 기록** 은 `RecordStore` 인터페이스 뒤에 있습니다. 실제 저장은 `PrefsRecordStore`가,
  테스트는 `MemoryRecordStore`가 담당하므로 플러그인 목 없이도 갱신 규칙을 검증할 수 있습니다.
  저장소 I/O는 `onLoad`를 막지 않도록 백그라운드로 돌리고, 읽기/쓰기 실패는 삼켜서
  저장소를 못 쓰는 환경에서도 게임이 그대로 동작합니다.
  게임오버 시점뿐 아니라 앱이 백그라운드로 갈 때도(`AppLifecycleListener`) 기록을 제출해,
  죽지 않고 앱을 닫아도 진행도가 남습니다.
