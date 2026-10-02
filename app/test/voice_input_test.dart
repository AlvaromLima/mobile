import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradutor/core/errors/voice_failure.dart';
import 'package:tradutor/models/source_language.dart';
import 'package:tradutor/providers/voice_input_provider.dart';
import 'package:tradutor/services/speech_recognition_service.dart';

import 'support/fake_speech_service.dart';

void main() {
  late ControlledSpeechService service;
  late ProviderContainer container;

  VoiceInputState state() => container.read(voiceInputProvider);
  VoiceInputNotifier notifier() => container.read(voiceInputProvider.notifier);
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  setUp(() {
    service = ControlledSpeechService();
    container = ProviderContainer(overrides: [speechRecognitionServiceProvider.overrideWithValue(service)]);
    container.listen(voiceInputProvider, (_, _) {});
  });
  tearDown(() => container.dispose());

  test('estado inicial é parado', () {
    expect(state().status, VoiceStatus.idle);
  });

  test('permissão concedida: ouve, mostra parciais e conclui com o texto final', () async {
    await notifier().start(SourceLanguage.en);
    expect(state().status, VoiceStatus.listening);
    expect(service.language, SourceLanguage.en);

    service.emitPartial('Good');
    await settle();
    expect(state().text, 'Good');
    expect(state().status, VoiceStatus.listening);

    await service.emitFinal('Good morning');
    await settle();
    expect(state().status, VoiceStatus.completed);
    expect(state().text, 'Good morning');
  });

  test('passa por "solicitando permissão" antes de ouvir', () async {
    final statuses = <VoiceStatus>[];
    container.listen(voiceInputProvider, (_, next) => statuses.add(next.status));

    await notifier().start(SourceLanguage.es);
    expect(statuses.take(2), [VoiceStatus.requestingPermission, VoiceStatus.listening]);
  });

  test('permissão pendente é solicitada e, se concedida, começa a ouvir', () async {
    service
      ..status = VoicePermission.denied
      ..afterRequest = VoicePermission.granted;

    await notifier().start(SourceLanguage.es);
    expect(service.requests, 1);
    expect(state().status, VoiceStatus.listening);
  });

  test('permissão recusada mostra mensagem e não ouve', () async {
    service
      ..status = VoicePermission.denied
      ..afterRequest = VoicePermission.denied;

    await notifier().start(SourceLanguage.en);
    expect(state().status, VoiceStatus.failure);
    expect(state().errorMessage, const MicrophonePermissionDeniedFailure().message);
    expect(state().canOpenSettings, isFalse);
    expect(service.isListening, isFalse);
  });

  test('permissão recusada permanentemente oferece abrir as configurações', () async {
    service.status = VoicePermission.permanentlyDenied;

    await notifier().start(SourceLanguage.en);
    expect(service.requests, 0, reason: 'não adianta pedir de novo');
    expect(state().errorMessage, const MicrophonePermissionPermanentlyDeniedFailure().message);
    expect(state().canOpenSettings, isTrue);

    await notifier().openSettings();
    expect(service.settingsOpened, 1);
  });

  final streamFailures = <VoiceFailure>[
    const MicrophoneUnavailableFailure(),
    const NoSpeechDetectedFailure(),
    const SpeechNotRecognizedFailure(),
    const SpeechServiceFailure(),
    const SpeechLanguageUnavailableFailure('espanhol'),
  ];
  for (final failure in streamFailures) {
    test('falha durante a escuta (${failure.runtimeType}) vira estado de erro', () async {
      await notifier().start(SourceLanguage.en);
      await service.emitError(failure);
      await settle();

      expect(state().status, VoiceStatus.failure);
      expect(state().errorMessage, failure.message);
    });
  }

  test('erro desconhecido na escuta vira falha do serviço, sem exceção', () async {
    await notifier().start(SourceLanguage.en);
    await service.emitError(StateError('detalhe interno'));
    await settle();

    expect(state().errorMessage, const SpeechServiceFailure().message);
  });

  test('exceção ao iniciar a escuta não escapa do controller', () async {
    service.listenThrows = Exception('plugin quebrou');

    await notifier().start(SourceLanguage.en);
    expect(state().status, VoiceStatus.failure);
    expect(state().errorMessage, const SpeechServiceFailure().message);
  });

  test('escuta encerrada sem fala vira "nenhuma fala detectada"', () async {
    await notifier().start(SourceLanguage.en);
    await service.endWithoutFinal();
    await settle();

    expect(state().errorMessage, const NoSpeechDetectedFailure().message);
  });

  test('escuta encerrada com texto parcial conclui com esse texto', () async {
    await notifier().start(SourceLanguage.en);
    service.emitPartial('Good morning');
    await settle();
    await service.endWithoutFinal();
    await settle();

    expect(state().status, VoiceStatus.completed);
    expect(state().text, 'Good morning');
  });

  test('parar passa para "processando" e pede o resultado final', () async {
    await notifier().start(SourceLanguage.en);
    await notifier().stop();

    expect(state().status, VoiceStatus.processing);
    expect(service.stops, 1);

    await service.emitFinal('Hello');
    await settle();
    expect(state().status, VoiceStatus.completed);
  });

  test('interrupção encerra a escuta e informa o usuário', () async {
    await notifier().start(SourceLanguage.en);
    await notifier().interrupt();

    expect(service.cancels, 1);
    expect(state().status, VoiceStatus.failure);
    expect(state().errorMessage, const SpeechInterruptedFailure().message);
  });

  test('cancelar volta ao estado parado e ignora eventos atrasados', () async {
    await notifier().start(SourceLanguage.en);
    await notifier().cancel();
    expect(state().status, VoiceStatus.idle);
    expect(service.cancels, 1);
  });

  test('novo início durante a escuta é ignorado', () async {
    await notifier().start(SourceLanguage.en);
    await notifier().start(SourceLanguage.es);
    expect(service.language, SourceLanguage.en);
  });
}
