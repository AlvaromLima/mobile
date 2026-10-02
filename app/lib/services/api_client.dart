import 'dart:async';
import 'dart:convert';
import 'dart:io' show HandshakeException, SocketException, TlsException;

import 'package:http/http.dart' as http;

import '../core/errors/translation_failure.dart';
import '../utils/request_id.dart';

/// Resposta HTTP já decodificada. `body` é o JSON (ou null se o corpo não for JSON).
class ApiResponse {
  const ApiResponse({required this.statusCode, required this.body});

  final int statusCode;
  final Object? body;

  bool get isSuccess => statusCode >= 200 && statusCode < 300;
}

/// Cliente HTTP do backend. Converte falhas de transporte em [TranslationFailure]
/// (conexão, timeout, servidor indisponível, resposta inválida) e não conhece regras de tradução.
class ApiClient {
  ApiClient({required this.baseUrl, required this._client, required this.timeout});

  final Uri baseUrl;
  final Duration timeout;
  final http.Client _client;

  Future<ApiResponse> postJson(String path, Map<String, dynamic> payload) async {
    final http.Response response;
    try {
      response = await _client
          .post(
            baseUrl.resolve(path),
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
              'Accept': 'application/json',
              'X-Request-Id': generateRequestId(),
            },
            body: jsonEncode(payload),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const TimeoutFailure();
    } on HandshakeException {
      throw const ServerUnavailableFailure();
    } on TlsException {
      throw const ServerUnavailableFailure();
    } on SocketException {
      throw const ConnectionFailure();
    } on http.ClientException {
      throw const ConnectionFailure();
    }

    return ApiResponse(statusCode: response.statusCode, body: _decode(response));
  }

  static Object? _decode(http.Response response) {
    if (response.bodyBytes.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      // Sucesso sem JSON válido é resposta inválida; erro sem JSON (ex.: proxy) é tratado pelo status.
      if (response.statusCode >= 200 && response.statusCode < 300) throw const InvalidResponseFailure();
      return null;
    }
  }
}
