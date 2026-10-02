import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../core/config/app_config.dart';
import '../repositories/backend_translation_repository.dart';
import '../repositories/translation_repository.dart';
import '../services/api_client.dart';
import '../services/translation_service.dart';

final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(
    baseUrl: AppConfig.apiBaseUrl,
    client: ref.watch(httpClientProvider),
    timeout: AppConfig.requestTimeout,
  ),
);

/// Troca de implementação acontece somente aqui.
final translationRepositoryProvider = Provider<TranslationRepository>(
  (ref) => BackendTranslationRepository(ref.watch(apiClientProvider)),
);

final translationServiceProvider = Provider<TranslationService>(
  (ref) => DefaultTranslationService(ref.watch(translationRepositoryProvider)),
);
