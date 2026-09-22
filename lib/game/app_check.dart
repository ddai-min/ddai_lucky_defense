import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'recaptcha_stub.dart' if (dart.library.js_interop) 'recaptcha_web.dart';

/// 랭킹 등록이 «이 사이트에서 온 진짜 앱» 에서 왔는지 증명하는 토큰을 만든다.
///
/// 왜 필요한가 — 이 게임은 정적 웹 앱이라 Firebase API 키가 빌드된 JS 에 그대로
/// 실린다. 배포된 사이트에서 `grep` 한 번이면 꺼낼 수 있으므로, 소스를 받아
/// 밸런스 수치를 고친 뒤 그 키로 «150웨이브 클리어» 를 올릴 수 있다. GitHub
/// Secrets 로 키를 숨기는 것은 포크를 갈라 놓을 뿐 이 구멍을 막지 못한다.
///
/// App Check 는 reCAPTCHA v3 토큰을 받아 App Check 토큰으로 바꾼다. reCAPTCHA
/// 사이트 키는 **도메인에 묶여 있어** 등록되지 않은 곳(로컬 빌드 포함)에서는
/// 토큰이 발급되지 않는다. Firestore 쪽에서 이 토큰을 요구하도록 켜 두면
/// 고친 빌드는 등록에 실패한다.
///
/// **막지 못하는 것** — 진짜 사이트를 열어 개발자도구로 점수를 조작하는 것.
/// 이 토큰이 증명하는 것은 «어디서 왔는가» 지 «정말 깼는가» 가 아니다.
class AppCheck {
  AppCheck({
    http.Client? client,
    String? projectId,
    String? appId,
    String? siteKey,
  }) : _client = client ?? http.Client(),
       _projectId = projectId ?? _envProjectId,
       _appId = appId ?? _envAppId,
       _siteKey = siteKey ?? _envSiteKey;

  static const String _envProjectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
  );
  static const String _envAppId = String.fromEnvironment('FIREBASE_APP_ID');
  static const String _envSiteKey = String.fromEnvironment(
    'RECAPTCHA_SITE_KEY',
  );
  static const String _envApiKey = String.fromEnvironment('FIREBASE_API_KEY');

  final http.Client _client;
  final String _projectId;
  final String _appId;
  final String _siteKey;

  String? _token;
  DateTime? _expiresAt;
  Future<String?>? _inFlight;

  /// 설정이 갖춰진 빌드인지. 하나라도 비면 토큰 없이 그냥 보낸다 —
  /// 설정 전 빌드가 갑자기 랭킹을 못 쓰게 되는 것보다 낫다.
  bool get isConfigured =>
      kIsWeb &&
      _projectId.isNotEmpty &&
      _appId.isNotEmpty &&
      _siteKey.isNotEmpty &&
      _envApiKey.isNotEmpty;

  /// 유효한 App Check 토큰. 못 받으면 null.
  ///
  /// 받아 둔 토큰은 만료 1분 전까지 다시 쓴다. 같은 순간에 여러 번 불려도
  /// 교환은 한 번만 한다.
  Future<String?> token() {
    if (!isConfigured) {
      return Future.value(null);
    }
    final cached = _token;
    final until = _expiresAt;
    if (cached != null &&
        until != null &&
        DateTime.now().isBefore(until.subtract(const Duration(minutes: 1)))) {
      return Future.value(cached);
    }
    return _inFlight ??= _mint().whenComplete(() => _inFlight = null);
  }

  Future<String?> _mint() async {
    try {
      final recaptcha = await recaptchaToken(_siteKey);
      if (recaptcha == null) {
        return null;
      }
      final response = await _client.post(
        Uri.parse(
          'https://firebaseappcheck.googleapis.com/v1/projects/$_projectId'
          '/apps/$_appId:exchangeRecaptchaV3Token?key=$_envApiKey',
        ),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'recaptcha_v3_token': recaptcha}),
      );
      if (response.statusCode != 200) {
        debugPrint('App Check 토큰 교환 실패: ${response.statusCode}');
        return null;
      }
      final body = jsonDecode(response.body);
      if (body is! Map) {
        return null;
      }
      final token = body['token'];
      if (token is! String || token.isEmpty) {
        return null;
      }
      // ttl 은 "1800s" 꼴이다. 못 읽으면 짧게 잡아 다음에 다시 받는다.
      final ttl = '${body['ttl']}';
      final seconds = int.tryParse(ttl.replaceAll(RegExp(r'[^0-9]'), '')) ?? 300;
      _token = token;
      _expiresAt = DateTime.now().add(Duration(seconds: seconds));
      return token;
    } catch (error) {
      debugPrint('App Check 토큰을 받지 못했습니다: $error');
      return null;
    }
  }
}
