import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repositories/fake_translation_repository.dart';
import '../repositories/translation_repository.dart';
import '../services/translation_service.dart';

/// Troca de implementação (simulada ou backend) acontece somente aqui.
final translationRepositoryProvider = Provider<TranslationRepository>(
  (ref) => const FakeTranslationRepository(),
);

final translationServiceProvider = Provider<TranslationService>(
  (ref) => DefaultTranslationService(ref.watch(translationRepositoryProvider)),
);
