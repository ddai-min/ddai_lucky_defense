/// 웹이 아닌 곳에서는 reCAPTCHA 가 없다. 항상 null 이라 App Check 도 꺼진다.
Future<String?> recaptchaToken(String siteKey) async => null;
