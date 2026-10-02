import 'dart:async';

import 'package:tradutor/services/text_to_speech_service.dart';

/// TextToSpeechService controlado pelo teste: a leitura só termina quando o teste manda.
class ControlledTtsService implements TextToSpeechService {
  final spoken = <String>[];
  int stops = 0;
  Object? speakThrows;
  Completer<void>? _current;

  bool get isSpeaking => _current != null && !_current!.isCompleted;

  void finish() => _current?.complete();

  @override
  Future<void> speak(String text) {
    final error = speakThrows;
    if (error != null) return Future.error(error);
    spoken.add(text);
    _current = Completer<void>();
    return _current!.future;
  }

  @override
  Future<void> stop() async {
    stops++;
    final current = _current;
    if (current != null && !current.isCompleted) current.complete();
  }
}
