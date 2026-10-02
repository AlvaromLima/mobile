import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradutor/core/errors/voice_failure.dart';
import 'package:tradutor/services/flutter_tts_text_to_speech_service.dart';

const _channel = MethodChannel('flutter_tts');

/// Simula o lado nativo do flutter_tts: responde às chamadas e emite os eventos de leitura.
class FakeTtsPlatform {
  final calls = <MethodCall>[];
  dynamic languageAvailable = true;
  dynamic speakResult = 1;
  bool autoComplete = true;
  dynamic voices = [
    {'name': 'pt-br-x-rede', 'locale': 'pt-BR', 'quality': 'very high', 'network_required': '1'},
    {'name': 'pt-br-x-padrao', 'locale': 'pt-BR', 'quality': 'normal', 'network_required': '0'},
    {'name': 'pt-br-x-alta', 'locale': 'pt-BR', 'quality': 'high', 'network_required': '0'},
    {'name': 'pt-pt-x-alta', 'locale': 'pt-PT', 'quality': 'very high', 'network_required': '0'},
  ];

  TestDefaultBinaryMessenger get _messenger => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void install() {
    _messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'isLanguageAvailable':
          return languageAvailable;
        case 'getVoices':
          return voices;
        case 'speak':
          if (autoComplete && speakResult == 1) Timer.run(() => emit('speak.onComplete'));
          return speakResult;
      }
      return 1;
    });
  }

  void uninstall() => _messenger.setMockMethodCallHandler(_channel, null);

  /// Evento enviado pelo lado nativo (fim, cancelamento ou erro da leitura).
  Future<void> emit(String method, [Object? arguments]) => _messenger.handlePlatformMessage(
        _channel.name,
        const StandardMethodCodec().encodeMethodCall(MethodCall(method, arguments)),
        (_) {},
      );

  List<MethodCall> named(String method) => calls.where((c) => c.method == method).toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeTtsPlatform platform;

  setUp(() {
    platform = FakeTtsPlatform()..install();
  });
  tearDown(() => platform.uninstall());

  group('leitura em voz alta', () {
    test('lê em pt-BR com a melhor voz offline disponível', () async {
      await FlutterTtsTextToSpeechService().speak('Bom dia');

      expect(platform.named('setLanguage').single.arguments, 'pt-BR');
      expect(platform.named('setVoice').single.arguments, {'name': 'pt-br-x-alta', 'locale': 'pt-BR'});
      expect(platform.named('speak').single.arguments, 'Bom dia');
    });

    test('configura uma única vez', () async {
      final service = FlutterTtsTextToSpeechService();
      await service.speak('Bom dia');
      await service.speak('Boa noite');

      expect(platform.named('isLanguageAvailable'), hasLength(1));
      expect(platform.named('speak').map((c) => c.arguments), ['Bom dia', 'Boa noite']);
    });

    test('texto longo é lido em trechos, na ordem', () async {
      final sentence = '${'palavra ' * 60}fim. ';
      final text = sentence * 20; // cerca de 9.700 caracteres
      await FlutterTtsTextToSpeechService().speak(text);

      final spoken = platform.named('speak').map((c) => c.arguments as String).toList();
      expect(spoken.length, greaterThan(1));
      expect(spoken.every((chunk) => chunk.length <= FlutterTtsTextToSpeechService.maxChunkLength), isTrue);
      expect(spoken.join(' ').split(RegExp(r'\s+')), text.trim().split(RegExp(r'\s+')));
    });

    test('texto vazio não aciona o motor', () async {
      await FlutterTtsTextToSpeechService().speak('   ');
      expect(platform.calls, isEmpty);
    });

    test('sem voz pt-BR instalada: TextToSpeechLanguageUnavailableFailure', () async {
      platform.languageAvailable = false;
      await expectLater(
        FlutterTtsTextToSpeechService().speak('Bom dia'),
        throwsA(isA<TextToSpeechLanguageUnavailableFailure>()),
      );
      expect(platform.named('speak'), isEmpty);
    });

    test('sem motor de TTS no aparelho: TextToSpeechUnavailableFailure', () async {
      platform.uninstall(); // canal sem implementação: MissingPluginException
      await expectLater(
        FlutterTtsTextToSpeechService().speak('Bom dia'),
        throwsA(isA<TextToSpeechUnavailableFailure>()),
      );
    });

    test('motor recusa a leitura: TextToSpeechPlaybackFailure', () async {
      platform.speakResult = 0;
      await expectLater(
        FlutterTtsTextToSpeechService().speak('Bom dia'),
        throwsA(isA<TextToSpeechPlaybackFailure>()),
      );
    });

    test('erro durante a reprodução: TextToSpeechPlaybackFailure', () async {
      platform.autoComplete = false;
      final speaking = FlutterTtsTextToSpeechService().speak('Bom dia');
      final expectation = expectLater(speaking, throwsA(isA<TextToSpeechPlaybackFailure>()));
      await pumpEventQueue();
      await platform.emit('speak.onError', 'synthesis error');
      await expectation;
    });

    test('interrupção pelo sistema (cancelamento) encerra a leitura sem erro', () async {
      platform.autoComplete = false;
      final speaking = FlutterTtsTextToSpeechService().speak('Bom dia');
      await pumpEventQueue();
      await platform.emit('speak.onCancel');
      await expectLater(speaking, completes);
    });

    test('parar encerra a leitura e não lê os trechos seguintes', () async {
      platform.autoComplete = false;
      final service = FlutterTtsTextToSpeechService();
      final text = '${'palavra ' * 500}. ${'outra ' * 500}';
      final speaking = service.speak(text);
      await pumpEventQueue();

      await service.stop();
      await expectLater(speaking, completes);
      expect(platform.named('stop'), hasLength(1));
      expect(platform.named('speak'), hasLength(1));
    });
  });

  group('escolha da voz', () {
    test('prefere voz offline, depois a de maior qualidade', () {
      expect(FlutterTtsTextToSpeechService.selectVoice(FakeTtsPlatform().voices), {
        'name': 'pt-br-x-alta',
        'locale': 'pt-BR',
      });
    });

    test('iOS: prefere premium e inclui o identificador', () {
      final voice = FlutterTtsTextToSpeechService.selectVoice([
        {'name': 'Luciana', 'locale': 'pt-BR', 'quality': 'default', 'identifier': 'com.apple.luciana'},
        {'name': 'Luciana (Premium)', 'locale': 'pt-BR', 'quality': 'premium', 'identifier': 'com.apple.luciana.premium'},
      ]);
      expect(voice, {'name': 'Luciana (Premium)', 'locale': 'pt-BR', 'identifier': 'com.apple.luciana.premium'});
    });

    test('aceita locale com sublinhado e ignora outros idiomas', () {
      expect(FlutterTtsTextToSpeechService.selectVoice([{'name': 'a', 'locale': 'pt_BR'}])?['name'], 'a');
      expect(FlutterTtsTextToSpeechService.selectVoice([{'name': 'b', 'locale': 'pt-PT'}]), isNull);
      expect(FlutterTtsTextToSpeechService.selectVoice(null), isNull);
    });
  });

  group('divisão em trechos', () {
    test('texto curto fica inteiro', () {
      expect(FlutterTtsTextToSpeechService.splitIntoChunks('Bom dia.', 100), ['Bom dia.']);
    });

    test('quebra no fim da frase quando possível', () {
      expect(FlutterTtsTextToSpeechService.splitIntoChunks('Primeira frase. Segunda frase.', 20), [
        'Primeira frase.',
        'Segunda frase.',
      ]);
    });

    test('sem pontuação, quebra em espaço; sem espaço, no limite', () {
      expect(FlutterTtsTextToSpeechService.splitIntoChunks('aaaa bbbb cccc', 10), ['aaaa bbbb', 'cccc']);
      expect(FlutterTtsTextToSpeechService.splitIntoChunks('a' * 25, 10), ['a' * 10, 'a' * 10, 'a' * 5]);
    });
  });
}
