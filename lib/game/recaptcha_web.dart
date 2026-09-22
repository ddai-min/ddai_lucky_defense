import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

@JS('grecaptcha')
external JSObject? get _grecaptcha;

extension type _Grecaptcha(JSObject _) implements JSObject {
  external void ready(JSFunction callback);
  external JSPromise<JSString> execute(String siteKey, _Action options);
}

/// `grecaptcha.execute(key, {action: 'submit'})` 의 두 번째 인자.
extension type _Action._(JSObject _) implements JSObject {
  external factory _Action({String action});
}

/// reCAPTCHA v3 토큰 하나를 받는다. 스크립트는 처음 부를 때 한 번만 심는다.
///
/// 사이트 키가 등록된 도메인이 아니면 reCAPTCHA 가 토큰을 주지 않는다 —
/// 로컬에서 띄운 빌드가 걸리는 지점이 여기다.
Future<String?> recaptchaToken(String siteKey) async {
  try {
    await _loadScript(siteKey);
    final api = _grecaptcha;
    if (api == null) {
      return null;
    }
    final ready = Completer<void>();
    _Grecaptcha(api).ready((() => ready.complete()).toJS);
    await ready.future.timeout(const Duration(seconds: 10));
    final token = await _Grecaptcha(
      api,
    ).execute(siteKey, _Action(action: 'submit')).toDart;
    return token.toDart;
  } catch (_) {
    return null;
  }
}

Future<void>? _loading;

Future<void> _loadScript(String siteKey) {
  return _loading ??= () {
    final done = Completer<void>();
    final script = web.document.createElement('script') as web.HTMLScriptElement
      ..src = 'https://www.google.com/recaptcha/api.js?render=$siteKey'
      ..async = true;
    script.onload = ((JSAny _) => done.complete()).toJS;
    script.onerror = ((JSAny _) => done.complete()).toJS;
    web.document.head!.appendChild(script);
    return done.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {},
    );
  }();
}
