import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// Configuração central do app. A URL do backend vem de `--dart-define=API_BASE_URL=...`
/// e não deve ser espalhada pelas telas.
abstract final class AppConfig {
  static const _rawApiBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// Tempo máximo de espera pela resposta do backend
  /// (o backend limita o provider a 10 s; a margem cobre rede móvel).
  static const requestTimeout = Duration(seconds: 15);

  static final Uri apiBaseUrl = resolveApiBaseUrl(
    raw: _rawApiBaseUrl,
    isRelease: kReleaseMode,
    isAndroid: !kIsWeb && Platform.isAndroid,
  );

  /// Em desenvolvimento, sem URL definida, aponta para o backend local
  /// (10.0.2.2 é o host da máquina visto pelo emulador Android).
  /// Em release, a URL é obrigatória e deve usar HTTPS.
  @visibleForTesting
  static Uri resolveApiBaseUrl({required String raw, required bool isRelease, required bool isAndroid}) {
    if (raw.isEmpty) {
      if (isRelease) throw StateError('API_BASE_URL não definida para o build de release.');
      return Uri.parse(isAndroid ? 'http://10.0.2.2:8080/' : 'http://localhost:8080/');
    }

    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasAuthority || (uri.scheme != 'https' && uri.scheme != 'http')) {
      throw StateError('API_BASE_URL inválida.');
    }
    if (isRelease && uri.scheme != 'https') throw StateError('API_BASE_URL deve usar HTTPS em release.');
    // Barra final garante que caminhos relativos sejam resolvidos abaixo de um eventual prefixo.
    return uri.path.endsWith('/') ? uri : uri.replace(path: '${uri.path}/');
  }
}
