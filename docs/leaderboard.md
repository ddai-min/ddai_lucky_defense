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

## 더 막아 보려다 알게 된 것

저장소가 public 이라 **누구나 소스를 받아 밸런스 수치를 고친 뒤 «150웨이브
클리어» 를 올릴 수 있습니다.** 이걸 막아 보려고 세 가지를 시도했고, 전부
Spark 요금제에서는 쓸 수 없었습니다. 같은 길을 두 번 가지 않도록 적어 둡니다.

### 1. API 키를 숨기는 것 — 애초에 불가능

키는 GitHub 소스 어디에도 없고 Secrets 에서 빌드 때만 들어갑니다. 그런데
배포된 번들에는 그대로 실립니다.

```sh
curl -s https://ddai-min.github.io/ddai_lucky_defense/main.dart.js \
  | grep -o 'AIzaSy[A-Za-z0-9_-]\{20,\}'
```

정적 웹 앱이라 **클라이언트가 보내야 하는 값은 클라이언트 안에 있어야 합니다.**
비밀값을 하나 더 만들어 Secrets 에 넣어도 결과는 같습니다. 인증 토큰 없이
`curl` 한 줄로 기록이 등록되는 것도 확인했습니다(200).

### 2. API 키 HTTP 리퍼러 제한 — Firestore 가 보지 않음

`ddai-min.github.io` 만 허용하도록 걸어 두고 5분간(70·140·210·280초) 재 봤지만
`localhost` 에서 보낸 요청이 계속 200 이었습니다. 제한 자체는 정상입니다 —
같은 키로 다른 API 를 찔러 비교했습니다.

| 리퍼러 | Firestore REST | Identity Toolkit |
| --- | --- | --- |
| 없음 | 200 | **403** |
| 허용 도메인 | 200 | 400 (키는 통과) |
| 엉뚱한 도메인 | **200** | **403** |

Firebase 는 API 키를 «권한» 이 아니라 «프로젝트 식별자» 로 씁니다. Firestore
접근 제어는 보안 규칙과 App Check 이 맡고, 키 제한은 관여하지 않습니다.

### 3. App Check — Spark 에서는 못 씀

구현까지 해서 배포했다가 걷어냈습니다(`git log` 에 남아 있습니다).

- **고전 reCAPTCHA v3** — 지원 중단이라 콘솔에서 **새로 등록하는 길이 막혀** 있습니다
- **reCAPTCHA Enterprise** — 등록은 되지만 `403 App attestation failed` 가 납니다.
  Cloud 프로젝트에 **결제(Blaze)가 붙어 있어야** assessment 가 돕니다
  (월 1만 건까지 무료지만 카드 등록은 필요)

### 결론

**Blaze 로 올리기 전에는 막을 방법이 없습니다.** 올린다면 App Check 을 다시
붙이면 되고, 그때는 **Enterprise 경로** 로 짜야 합니다(v3 는 등록이 막힘) —
`enterprise.js` · `grecaptcha.enterprise.execute` ·
`exchangeRecaptchaEnterpriseToken` 세 군데가 다릅니다.

그때까지 랭킹은 «명예의 전당» 입니다. 규칙이 웨이브 범위·이름 길이·필드 구성은
여전히 막고, 이상한 기록은 콘솔에서 지우면 됩니다.
