import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../core/errors/voice_failure.dart';
import 'text_to_speech_service.dart';

/// Leitura em voz alta com o motor nativo (Android TextToSpeech / iOS AVSpeechSynthesizer),
/// via `flutter_tts`, sempre em português do Brasil.
class FlutterTtsTextToSpeechService implements TextToSpeechService {
  FlutterTtsTextToSpeechService({FlutterTts? tts}) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;

  static const language = 'pt-BR';

  /// O Android aceita no máximo 4.000 caracteres por leitura; textos maiores são lidos em trechos.
  static const maxChunkLength = 3900;

  bool _configured = false;
  Completer<void>? _utterance;
  bool _stopRequested = false;

  Future<void> _configure() async {
    if (_configured) return;

    // Acompanha o fim de cada trecho pelos eventos nativos, para que erro ou cancelamento
    // nunca deixem a leitura pendurada.
    _tts
      ..setCompletionHandler(_completeUtterance)
      ..setCancelHandler(_completeUtterance)
      ..setErrorHandler((_) => _failUtterance(const TextToSpeechPlaybackFailure()));

    final dynamic available;
    try {
      await _tts.awaitSpeakCompletion(false);
      available = await _tts.isLanguageAvailable(language);
    } on MissingPluginException {
      throw const TextToSpeechUnavailableFailure();
    } on PlatformException {
      throw const TextToSpeechUnavailableFailure();
    }
    if (available != true && available != 1) throw const TextToSpeechLanguageUnavailableFailure();

    await _tts.setLanguage(language);
    try {
      final voice = selectVoice(await _tts.getVoices);
      if (voice != null) await _tts.setVoice(voice);
    } on PlatformException {
      // Sem lista de vozes: o motor usa a voz padrão do idioma.
    }
    // iOS: toca mesmo no modo silencioso e abaixa o volume de outros apps durante a leitura.
    // O flutter_tts ignora esta chamada nas demais plataformas.
    await _tts.setIosAudioCategory(
      IosTextToSpeechAudioCategory.playback,
      [IosTextToSpeechAudioCategoryOptions.duckOthers],
      IosTextToSpeechAudioMode.voicePrompt,
    );
    _configured = true;
  }

  @override
  Future<void> speak(String text) async {
    final content = text.trim();
    if (content.isEmpty) return;

    try {
      await _configure();
    } on VoiceFailure {
      rethrow;
    } catch (_) {
      throw const TextToSpeechUnavailableFailure();
    }

    if (_utterance != null) await stop();
    _stopRequested = false;

    for (final chunk in splitIntoChunks(content, maxChunkLength)) {
      if (_stopRequested) return;
      final utterance = Completer<void>();
      _utterance = utterance;
      try {
        final result = await _tts.speak(chunk);
        if (result != 1) throw const TextToSpeechPlaybackFailure();
      } on VoiceFailure {
        _utterance = null;
        rethrow;
      } catch (_) {
        _utterance = null;
        throw const TextToSpeechPlaybackFailure();
      }
      await utterance.future;
    }
  }

  @override
  Future<void> stop() async {
    _stopRequested = true;
    try {
      await _tts.stop();
    } catch (_) {
      // Parar é melhor esforço: o importante é liberar quem aguarda a leitura.
    }
    _completeUtterance();
  }

  void _completeUtterance() {
    final utterance = _utterance;
    _utterance = null;
    if (utterance != null && !utterance.isCompleted) utterance.complete();
  }

  void _failUtterance(VoiceFailure failure) {
    final utterance = _utterance;
    _utterance = null;
    if (utterance != null && !utterance.isCompleted) utterance.completeError(failure);
  }

  /// Escolhe a melhor voz pt-BR disponível: prefere vozes que funcionam sem internet
  /// e, entre elas, a de maior qualidade. Devolve null se não houver voz pt-BR listada.
  @visibleForTesting
  static Map<String, String>? selectVoice(Object? voices) {
    if (voices is! List) return null;
    final candidates = [
      for (final voice in voices)
        if (voice is Map &&
            voice['name'] is String &&
            voice['locale'] is String &&
            (voice['locale'] as String).replaceAll('_', '-').toLowerCase() == 'pt-br')
          voice,
    ];
    if (candidates.isEmpty) return null;

    int score(Map<dynamic, dynamic> voice) {
      final offline = voice['network_required'] == '1' ? 0 : 100;
      final quality = switch (voice['quality']) {
        'premium' || 'very high' => 5,
        'enhanced' || 'high' => 4,
        'default' || 'normal' => 2,
        'low' => 1,
        _ => 1,
      };
      return offline + quality;
    }

    candidates.sort((a, b) => score(b).compareTo(score(a)));
    final best = candidates.first;
    return {
      'name': best['name'] as String,
      'locale': best['locale'] as String,
      if (best['identifier'] is String) 'identifier': best['identifier'] as String,
    };
  }

  /// Divide o texto em trechos de até [maxLength], preferindo quebrar no fim de frases e depois em espaços.
  @visibleForTesting
  static List<String> splitIntoChunks(String text, int maxLength) {
    final chunks = <String>[];
    var rest = text.trim();
    while (rest.length > maxLength) {
      final window = rest.substring(0, maxLength);
      var cut = [
        window.lastIndexOf('. '),
        window.lastIndexOf('! '),
        window.lastIndexOf('? '),
        window.lastIndexOf('\n'),
      ].reduce((a, b) => a > b ? a : b);
      if (cut <= 0) cut = window.lastIndexOf(' ');
      cut = cut <= 0 ? maxLength : cut + 1;
      chunks.add(rest.substring(0, cut).trim());
      rest = rest.substring(cut).trim();
    }
    if (rest.isNotEmpty) chunks.add(rest);
    return chunks;
  }
}
