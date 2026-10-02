import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tradutor/core/config/app_config.dart';
import 'package:tradutor/core/errors/translation_failure.dart';
import 'package:tradutor/models/translation_request.dart';
import 'package:tradutor/repositories/backend_translation_repository.dart';
import 'package:tradutor/services/api_client.dart';
import 'package:tradutor/utils/request_id.dart';

final _uuid = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');

http.Response jsonResponse(int status, Object body) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

Map<String, dynamic> successBody({String translated = 'Bom dia', String source = 'en'}) => {
      'success': true,
      'detectedLanguage': source,
      'sourceLanguage': source,
      'targetLanguage': 'pt-BR',
      'originalText': 'Good morning',
      'translatedText': translated,
    };

Map<String, dynamic> errorBody(String code) => {
      'success': false,
      'error': {'code': code, 'message': 'mensagem do servidor', 'requestId': 'x'},
    };

ApiClient apiWith(http.Client client, {Duration timeout = const Duration(seconds: 5)}) =>
    ApiClient(baseUrl: Uri.parse('https://api.exemplo.com/'), client: client, timeout: timeout);

BackendTranslationRepository repoWith(http.Client client) => BackendTranslationRepository(apiWith(client));

const request = TranslationRequest(text: 'Good morning', sourceLanguage: 'en');

Matcher throwsFailure<T extends TranslationFailure>() => throwsA(isA<T>());

void main() {
  group('ApiClient', () {
    test('envia POST JSON com X-Request-Id para a URL centralizada', () async {
      late http.Request captured;
      final api = apiWith(MockClient((req) async {
        captured = req;
        return jsonResponse(200, successBody());
      }));

      final response = await api.postJson('api/v1/translate', request.toJson());

      expect(response.statusCode, 200);
      expect(captured.method, 'POST');
      expect(captured.url.toString(), 'https://api.exemplo.com/api/v1/translate');
      expect(captured.headers['Content-Type'], startsWith('application/json'));
      expect(captured.headers['X-Request-Id'], matches(_uuid));
      expect(jsonDecode(captured.body), {'text': 'Good morning', 'sourceLanguage': 'en', 'targetLanguage': 'pt-BR'});
    });

    test('timeout vira TimeoutFailure', () async {
      final api = apiWith(
        MockClient((_) => Completer<http.Response>().future),
        timeout: const Duration(milliseconds: 20),
      );
      await expectLater(api.postJson('x', {}), throwsFailure<TimeoutFailure>());
    });

    test('SocketException (sem internet) vira ConnectionFailure', () async {
      final api = apiWith(MockClient((_) async => throw const SocketException('Network is unreachable')));
      await expectLater(api.postJson('x', {}), throwsFailure<ConnectionFailure>());
    });

    test('ClientException vira ConnectionFailure', () async {
      final api = apiWith(MockClient((_) async => throw http.ClientException('Connection refused')));
      await expectLater(api.postJson('x', {}), throwsFailure<ConnectionFailure>());
    });

    test('falha de TLS vira ServerUnavailableFailure', () async {
      final api = apiWith(MockClient((_) async => throw const HandshakeException('certificado inválido')));
      await expectLater(api.postJson('x', {}), throwsFailure<ServerUnavailableFailure>());
    });

    test('200 com corpo que não é JSON vira InvalidResponseFailure', () async {
      final api = apiWith(MockClient((_) async => http.Response('<html>ok</html>', 200)));
      await expectLater(api.postJson('x', {}), throwsFailure<InvalidResponseFailure>());
    });

    test('erro sem JSON (ex.: proxy) devolve corpo nulo para decisão pelo status', () async {
      final api = apiWith(MockClient((_) async => http.Response('<html>Bad Gateway</html>', 502)));
      final response = await api.postJson('x', {});
      expect(response.statusCode, 502);
      expect(response.body, isNull);
    });
  });

  group('BackendTranslationRepository', () {
    test('converte a resposta de sucesso do backend', () async {
      final repo = repoWith(MockClient((_) async => jsonResponse(200, successBody(translated: 'Bom dia, tudo bem?'))));

      final result = await repo.translate(request);
      expect(result.translatedText, 'Bom dia, tudo bem?');
      expect(result.sourceLanguage, 'en');
      expect(result.targetLanguage, 'pt-BR');
    });

    test('200 sem success=true vira InvalidResponseFailure', () async {
      final repo = repoWith(MockClient((_) async => jsonResponse(200, {...successBody(), 'success': false})));
      await expectLater(repo.translate(request), throwsFailure<InvalidResponseFailure>());
    });

    test('200 com campos faltando vira InvalidResponseFailure', () async {
      final repo = repoWith(MockClient((_) async => jsonResponse(200, {'success': true})));
      await expectLater(repo.translate(request), throwsFailure<InvalidResponseFailure>());
    });

    final byCode = <String, (int, Matcher)>{
      'TEXT_TOO_LONG': (413, throwsFailure<TextTooLongFailure>()),
      'UNSUPPORTED_LANGUAGE': (422, throwsFailure<UnsupportedLanguageFailure>()),
      'RATE_LIMITED': (429, throwsFailure<RateLimitedFailure>()),
      'PROVIDER_TIMEOUT': (504, throwsFailure<TimeoutFailure>()),
      'QUOTA_EXCEEDED': (503, throwsFailure<ServerUnavailableFailure>()),
      'PROVIDER_UNAVAILABLE': (502, throwsFailure<ServerUnavailableFailure>()),
      'INTERNAL_ERROR': (500, throwsFailure<ServerUnavailableFailure>()),
      'VALIDATION_ERROR': (400, throwsFailure<UnknownFailure>()),
    };
    byCode.forEach((code, expected) {
      test('erro $code do backend é mapeado', () async {
        final repo = repoWith(MockClient((_) async => jsonResponse(expected.$1, errorBody(code))));
        await expectLater(repo.translate(request), expected.$2);
      });
    });

    test('502 sem JSON (servidor fora / proxy) vira ServerUnavailableFailure', () async {
      final repo = repoWith(MockClient((_) async => http.Response('Bad Gateway', 502)));
      await expectLater(repo.translate(request), throwsFailure<ServerUnavailableFailure>());
    });

    test('404 (URL do backend errada) vira ServerUnavailableFailure', () async {
      final repo = repoWith(MockClient((_) async => http.Response('Not Found', 404)));
      await expectLater(repo.translate(request), throwsFailure<ServerUnavailableFailure>());
    });

    test('mensagem do servidor nunca é repassada ao usuário', () async {
      final repo = repoWith(MockClient((_) async => jsonResponse(502, errorBody('PROVIDER_UNAVAILABLE'))));
      try {
        await repo.translate(request);
        fail('deveria falhar');
      } on TranslationFailure catch (failure) {
        expect(failure.message, isNot(contains('mensagem do servidor')));
      }
    });
  });

  group('AppConfig.resolveApiBaseUrl', () {
    test('desenvolvimento sem URL usa o backend local por plataforma', () {
      expect(
        AppConfig.resolveApiBaseUrl(raw: '', isRelease: false, isAndroid: true).toString(),
        'http://10.0.2.2:8080/',
      );
      expect(
        AppConfig.resolveApiBaseUrl(raw: '', isRelease: false, isAndroid: false).toString(),
        'http://localhost:8080/',
      );
    });

    test('release exige URL definida e HTTPS', () {
      expect(() => AppConfig.resolveApiBaseUrl(raw: '', isRelease: true, isAndroid: true), throwsStateError);
      expect(
        () => AppConfig.resolveApiBaseUrl(raw: 'http://api.exemplo.com', isRelease: true, isAndroid: true),
        throwsStateError,
      );
      expect(
        AppConfig.resolveApiBaseUrl(raw: 'https://api.exemplo.com', isRelease: true, isAndroid: true).toString(),
        'https://api.exemplo.com/',
      );
    });

    test('recusa URL inválida e preserva prefixo de caminho', () {
      expect(() => AppConfig.resolveApiBaseUrl(raw: 'nao-e-url', isRelease: false, isAndroid: false), throwsStateError);
      expect(() => AppConfig.resolveApiBaseUrl(raw: 'ftp://x.com', isRelease: false, isAndroid: false), throwsStateError);

      final base = AppConfig.resolveApiBaseUrl(raw: 'https://x.com/tradutor', isRelease: true, isAndroid: false);
      expect(base.resolve(BackendTranslationRepository.translatePath).toString(), 'https://x.com/tradutor/api/v1/translate');
    });
  });

  test('generateRequestId gera UUID v4 distinto a cada chamada', () {
    final ids = List.generate(50, (_) => generateRequestId());
    expect(ids.every(_uuid.hasMatch), isTrue);
    expect(ids.toSet().length, 50);
  });
}
