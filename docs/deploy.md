# 웹 배포

GitHub Pages 에 올라간다. `main` 에 푸시하면
[`.github/workflows/web-deploy.yml`](../.github/workflows/web-deploy.yml) 이
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

## 로딩 용량

콜드 로딩은 약 4.7MB다. 자체 호스팅하는 건 `main.dart.js` 뿐이고(2.1MB, gzip 0.6MB),
나머지는 gstatic CDN 에서 온다 — CanvasKit 2.8MB(brotli), Noto Color Emoji 0.69MB,
Noto Sans Symbols2 0.37MB, Noto Sans KR 0.17MB. 두 번째 방문부터는 캐시를 쓴다.

한글 글꼴을 앱에 넣지 않은 이유: 이 게임은 유닛·몬스터가 전부 이모지라 어차피
Noto Color Emoji 가 필요한데, 그건 10MB짜리라 번들이 현실적이지 않다. gstatic 이
막히면 이모지부터 깨지므로, 한글만 번들해도 얻는 게 없다. 대신 Flutter 가 첫
프레임을 그릴 때까지 몇 초가 걸리므로 `web/index.html` 에 HTML/CSS 만으로 즉시 뜨는
로딩 화면을 깔아 두었다.
