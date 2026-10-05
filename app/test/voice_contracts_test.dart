import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tradutor/core/errors/voice_failure.dart';
import 'package:tradutor/models/source_language.dart';
import 'package:tradutor/services/speech_recognition_service.dart';
import 'package:tradutor/services/text_to_speech_service.dart';

/// Implementações falsas: comprovam que os contratos são implementáveis sem pacote nativo
/// e servirão de base para os testes das etapas de voz.
class FakeSpeechRecognitionService implements SpeechRecognitionService {
  FakeSpeechRecognitionService(this.script);

  final List<SpeechRecognitionResult> script;
  VoicePermission permission = VoicePermission.granted;
  SourceLanguage? lastLanguage;

  @override
  Future<VoicePermission> permissionStatus() async => permission;

  @override
  Future<VoicePermission> requestPermission() async => permission;

  @override
  Future<void> openPermissionSettings() async {}

  @override
  Stream<SpeechRecognitionResult> listen(SourceLanguage language) {
    if (language == SourceLanguage.auto) throw ArgumentError.value(language, 'language');
    lastLanguage = language;
    return Stream.fromIterable(script);
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> cancel() async {}
}

class FakeTextToSpeechService implements TextToSpeechService {
  final spoken = <String>[];

  @override
  Future<void> speak(String text) async => spoken.add(text);

  @override
  Future<void> stop() async {}
}

void main() {
  test('reconhecimento emite parciais e termina com o resultado final', () async {
    final service = FakeSpeechRecognitionService(const [
      SpeechRecognitionResult(text: 'Good', isFinal: false),
      SpeechRecognitionResult(text: 'Good morning', isFinal: true),
    ]);

    final results = await service.listen(SourceLanguage.en).toList();

    expect(results.map((r) => r.text), ['Good', 'Good morning']);
    expect(results.last.isFinal, isTrue);
    expect(service.lastLanguage, SourceLanguage.en);
  });

  test('reconhecimento não aceita o modo automático', () {
    final service = FakeSpeechRecognitionService(const []);
    expect(() => service.listen(SourceLanguage.auto), throwsArgumentError);
  });

  test('leitura em voz alta recebe o texto traduzido', () async {
    final tts = FakeTextToSpeechService();
    await tts.speak('Bom dia');
    expect(tts.spoken, ['Bom dia']);
  });

  test('todas as falhas de voz têm mensagem própria em português', () {
    const failures = <VoiceFailure>[
      MicrophonePermissionDeniedFailure(),
      MicrophonePermissionPermanentlyDeniedFailure(),
      SpeechUnavailableFailure(),
      SpeechLanguageUnavailableFailure('espanhol'),
      NoSpeechDetectedFailure(),
      SpeechNotRecognizedFailure(),
      SpeechInterruptedFailure(),
      SpeechNetworkFailure(),
      SpeechBusyFailure(),
      SpeechServiceFailure(),
      TextToSpeechUnavailableFailure(),
      TextToSpeechLanguageUnavailableFailure(),
      TextToSpeechPlaybackFailure(),
    ];

    expect(failures.every((f) => f.message.trim().isNotEmpty), isTrue);
    expect(failures.map((f) => f.message).toSet().length, failures.length, reason: 'mensagens não podem se repetir');
    expect(const SpeechLanguageUnavailableFailure('espanhol').message, contains('espanhol'));
  });
}
