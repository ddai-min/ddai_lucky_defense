# 랭킹 (Firebase Firestore)

어려움·지옥·무한 세 모드에 사용자끼리 도달 웨이브를 겨루는 랭킹이 있습니다.
판이 끝나면 결과 화면에서 이름을 적어 올리고, 인트로의 🏆 버튼으로 목록을 봅니다.

**설정하기 전에는 기능이 통째로 숨습니다.** `FIREBASE_PROJECT_ID` 와
`FIREBASE_API_KEY` 가 비어 있으면 `Leaderboard.isAvailable` 이 거짓이 되어
인트로의 랭킹 버튼도, 결과 화면의 이름 입력도 나오지 않습니다. 그래서 설정을
안 한 사람이 받아 빌드해도 게임은 그대로 돌아갑니다.

## 지금 연결된 곳

| | |
| --- | --- |
| 프로젝트 | `ddai-lucky-defense` |
| Firestore 위치 | `asia-northeast3` (서울) — **한 번 정하면 못 바꿉니다** |
| 컬렉션 | `ranking_hard`, `ranking_hell`, `ranking_endless` |
| 배포 | 저장소 Secrets `FIREBASE_PROJECT_ID` · `FIREBASE_API_KEY` 로 들어갑니다 |

로컬에서 랭킹까지 띄우려면 두 값을 직접 넘깁니다. 값은
`firebase apps:sdkconfig WEB --project ddai-lucky-defense` 로 확인합니다.

```sh
fvm flutter run \
  --dart-define=FIREBASE_PROJECT_ID=ddai-lucky-defense \
  --dart-define=FIREBASE_API_KEY=AIza...
```

규칙을 고쳤다면 반드시 다시 배포해야 반영됩니다.

```sh
firebase deploy --only firestore:rules
```

## 처음부터 다시 세운다면

1. **프로젝트 만들기** — [console.firebase.google.com](https://console.firebase.google.com)
2. **Cloud Firestore API 켜기** — 콘솔에서 한 번 눌러 줘야 CLI 가 동작합니다
3. **데이터베이스 만들기** — 위치는 이때 정합니다(프로젝트 설정에는 없습니다)
   ```sh
   firebase firestore:databases:create "(default)" --location asia-northeast3
   ```
4. **규칙 배포** — `firebase deploy --only firestore:rules`
5. **웹 앱 등록** — `firebase apps:create WEB "이름"` 후 `apps:sdkconfig` 로 키 확인
6. **Secrets 등록** — `gh secret set FIREBASE_PROJECT_ID` · `FIREBASE_API_KEY`

`apiKey` 와 `projectId` 는 **비밀이 아닙니다** — 모든 Firebase 웹 앱이 브라우저에
그대로 내려보내고, 빌드된 `main.dart.js` 에도 실립니다. Secrets 에 둔 건 보안이
아니라 **포크 때문**입니다. 포크에는 값이 없어 랭킹이 조용히 빠지므로, 남의 포크가
이 저장소의 랭킹에 기록을 쌓지 않습니다. 접근을 실제로 막는 건 키가 아니라 규칙입니다.

## 만든 방식

`cloud_firestore` 패키지를 쓰지 않고 **REST API 를 직접 부릅니다.** 이 게임은
콜드 로딩이 4.7MB 인데 Firebase 웹 SDK 를 통째로 넣으면 수백 KB 가 더 붙습니다.
랭킹이 하는 일은 «상위 20개 읽기» 와 «한 줄 쓰기» 두 가지뿐이라 REST 로 충분합니다.

모드마다 컬렉션을 따로 씁니다(`ranking_hard`, `ranking_endless`). 한 컬렉션에
모드를 필드로 섞으면 «모드로 거르고 웨이브로 정렬» 에 복합 색인을 따로 만들어야
하는데, 컬렉션을 나누면 기본 색인만으로 됩니다.

저장소는 [`RecordStore`](../lib/game/record_store.dart) 와 같은 방식으로 인터페이스
뒤에 있습니다 — 실제 구현은 `FirestoreLeaderboard`, 테스트는 `MemoryLeaderboard`
가 맡아 네트워크 없이도 등록 규칙을 검증합니다.

## 위조에 대하여

**정적 웹 클라이언트가 직접 점수를 올리는 구조라, 범위 안의 거짓말은 막을 수
없습니다.** 브라우저 개발자도구로 «어려움 150웨이브» 를 그냥 POST 할 수 있습니다.
이 저장소는 «최소 방어» 를 택했습니다.

규칙이 막는 것

- 필드 구성이 정확히 `name`·`wave`·`createdAt` 인지 (다른 값 섞어 넣기 차단)
- 웨이브 범위 (어려움·지옥 1~150, 무한 1~999)
- 이름 길이 1~12자
- 수정·삭제 (한 번 올라간 기록은 누구도 못 고칩니다)

클라이언트가 막는 것

- 한 판에 한 번만 등록 (같은 기록이 여러 줄로 쌓이는 것)
- 이름 다듬기 — 앞뒤 공백·줄바꿈 제거, 연속 공백 한 칸, 12자에서 자름

**막지 못하는 것**

- 실제로 그 웨이브까지 갔는지. 범위 안이면 통과합니다.
- 같은 사람이 여러 판을 올리는 것. 레이트 리밋은 Firestore 규칙으로 표현할 수 없습니다.
- 욕설·사칭 이름. 지우려면 콘솔에서 직접 문서를 삭제해야 합니다.

여기까지 막으려면 서버에서 시드와 입력 기록으로 판을 다시 돌려 검증해야 하고,
그러려면 게임 로직을 결정론적으로 만들고 서버에서도 돌려야 합니다 — 작업량이
전혀 다른 일이라 하지 않았습니다.

규칙이 실제로 막는지는 서버에 직접 쏴서 확인했습니다.

| 시도 | 결과 |
| --- | --- |
| 어려움 42웨 · 이름 «테스트» | 200 통과 |
| 어려움 9999웨 (범위 초과) | **403** |
| 이름 13자 | **403** |
| `admin: true` 필드 끼워 넣기 | **403** |
| `secrets` 컬렉션에 쓰기 | **403** |
| 상위 기록 읽기 | 200 통과 |

## 고친 빌드를 막는 것 — App Check

**저장소가 public 이라 누구나 소스를 받아 밸런스 수치를 고칠 수 있습니다.** 키를
Secrets 에 둔 것은 아무 도움이 안 됩니다 — 배포된 `main.dart.js` 에 그대로 실려
있어서 `grep` 한 번이면 꺼냅니다.

```sh
curl -s https://ddai-min.github.io/ddai_lucky_defense/main.dart.js \
  | grep -o 'AIzaSy[A-Za-z0-9_-]\{20,\}'
```

그래서 **App Check** 을 씁니다. 등록을 보낼 때 «이 도메인에서 돌아가는 진짜 앱»
임을 증명하는 토큰(`X-Firebase-AppCheck`)을 함께 보내고, Firestore 가 그 토큰을
요구합니다. reCAPTCHA v3 사이트 키는 **도메인에 묶여 있어** 등록되지 않은
곳(로컬 빌드 포함)에서는 토큰이 아예 발급되지 않습니다.

읽기에는 붙이지 않았습니다. 랭킹은 누구나 봐도 되고, 막아야 할 것은 쓰기입니다.

### 켜는 순서

**순서가 중요합니다.** 토큰을 보내지 않는 빌드가 떠 있는 상태에서 강제를 먼저
켜면 랭킹 등록이 통째로 죽습니다.

#### 1. reCAPTCHA v3 키 만들기

[google.com/recaptcha/admin](https://www.google.com/recaptcha/admin/create) 에서
새 사이트를 등록합니다. Firebase 콘솔이 아니라 **여기서** 먼저 만듭니다.

| 항목 | 넣을 값 |
| --- | --- |
| 라벨 | 아무거나 (`따이 운빨 디펜스` 등) |
| reCAPTCHA 유형 | **점수 기반 (v3)** |
| 도메인 | `ddai-min.github.io` |

**«reCAPTCHA 솔루션의 출처 확인» 을 켠 채로 두세요.** 이 체크를 끄면 키가 어느
도메인에서든 동작해서, **이 방어가 통째로 무의미해집니다.** 기본값이 켜짐이니
건드리지만 않으면 됩니다.

도메인에 **`localhost` 를 넣지 마세요.** 넣는 순간 «소스를 받아 로컬에서 고쳐
돌리는» 바로 그 경우가 통과합니다.

> ⚠️ **유형을 «v3» 로 고르는 것이 중요합니다.** «Enterprise» 를 고르면 토큰
> 교환 엔드포인트가 달라져(`exchangeRecaptchaEnterpriseToken`) 지금 코드와
> 맞지 않습니다. 코드는 `exchangeRecaptchaV3Token` 을 부릅니다
> ([`lib/game/app_check.dart`](../lib/game/app_check.dart)).

만들고 나면 키가 **두 개** 나옵니다. 가는 곳이 서로 다릅니다.

| 키 | 어디로 | 왜 |
| --- | --- | --- |
| **사이트 키** | 우리 빌드 (`RECAPTCHA_SITE_KEY`) | 브라우저가 토큰을 받을 때 씁니다. 공개 값입니다. |
| **비밀 키** | Firebase 콘솔 | Firebase 가 그 토큰을 검증할 때 씁니다. **앱에 넣지 않습니다.** |

#### 2. Firebase 에 등록

[Firebase 콘솔 > App Check > 앱](https://console.firebase.google.com/project/ddai-lucky-defense/appcheck/apps)
에서 웹 앱(`운빨 디펜스 웹`)을 고르고 **reCAPTCHA v3** 공급자를 켠 뒤, 위에서
받은 **비밀 키** 를 붙여 넣습니다. 토큰 수명(TTL)은 기본 1시간이면 됩니다.

#### 3. 사이트 키를 Secrets 에

```sh
gh secret set RECAPTCHA_SITE_KEY
```

`FIREBASE_APP_ID` 는 이미 등록되어 있습니다(`1:428360073066:web:97ae21851c68885a196f13`).

#### 4. 배포하고, 토큰이 실리는지 먼저 확인

main 에 푸시해 배포한 뒤 **랭킹에 기록을 하나 올려 봅니다.** 그리고
[App Check > API](https://console.firebase.google.com/project/ddai-lucky-defense/appcheck/products)
에서 Cloud Firestore 의 요청 그래프를 봅니다.

- **확인된 요청** 이 올라간다 → 토큰이 잘 실리고 있습니다. 다음 단계로.
- **확인되지 않은 요청** 만 올라간다 → 아직 토큰이 안 실립니다. 여기서
  강제를 켜면 랭킹이 죽습니다. 사이트 키·App ID 가 빌드에 들어갔는지
  먼저 확인하세요.

#### 5. 마지막에 강제를 켠다

같은 화면에서 Cloud Firestore 의 **적용(Enforce)** 을 켭니다. 이때부터 토큰
없는 요청은 403 으로 거절됩니다 — 로컬에서 고쳐 돌린 빌드가 여기서 막힙니다.

#### 나중에 로컬에서 시험하고 싶다면

도메인에 `localhost` 를 넣는 대신 **디버그 토큰** 을 씁니다. 이건 사람이
하나씩 발급해 주는 것이라, 소스를 받은 사람이 스스로 만들 수 없습니다.

```sh
firebase appcheck:debugtokens:create --app 1:428360073066:web:97ae21851c68885a196f13
```

#### 비용

reCAPTCHA v3 는 월 10,000건까지 무료입니다. 등록 요청에만 붙이므로(읽기는
그냥 둡니다) 이 게임 규모에서는 넘길 일이 없습니다.

설정이 하나라도 비면 App Check 은 조용히 꺼진 채로 동작합니다
([`AppCheck.isConfigured`]). 그래서 위 순서 중간에 멈춰도 랭킹은 계속 돕니다.

### 그래도 막지 못하는 것

App Check 이 증명하는 것은 **«어디서 왔는가» 지 «정말 깼는가» 가 아닙니다.**
진짜 사이트를 열어 개발자도구로 점수를 조작하면 그대로 통과합니다. 여기까지
막으려면 게임 로직을 결정론적으로 만들고 시드와 입력 기록을 서버에서 다시
돌려 검증해야 합니다 — 작업량이 전혀 다른 일이라 하지 않았습니다.

**더 싼 방어 하나** — API 키에 HTTP 리퍼러 제한(`ddai-min.github.io` 만 허용)을
걸 수도 있습니다. Google Cloud 콘솔의 «API 및 서비스 > 사용자 인증 정보» 에서
설정하며, 코드 변경이 필요 없습니다. 다만 `curl` 은 헤더를 마음대로 넣을 수
있어 그대로 통과합니다. App Check 과 같이 걸면 겹겹이 됩니다.
