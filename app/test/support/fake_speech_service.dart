import 'dart:async';

import 'package:tradutor/models/source_language.dart';
import 'package:tradutor/services/speech_recognition_service.dart';

/// SpeechRecognitionService controlado pelo teste: permissões configuráveis e
/// resultados emitidos manualmente.
class ControlledSpeechService implements SpeechRecognitionService {
  VoicePermission status = VoicePermission.granted;
  VoicePermission afterRequest = VoicePermission.granted;
  Object? listenThrows;

  int requests = 0;
  int stops = 0;
  int cancels = 0;
  int settingsOpened = 0;
  SourceLanguage? language;
  StreamController<SpeechRecognitionResult>? _controller;

  bool get isListening => _controller != null && !_controller!.isClosed;

  void emitPartial(String text) => _controller!.add(SpeechRecognitionResult(text: text, isFinal: false));

  Future<void> emitFinal(String text) async {
    _controller!.add(SpeechRecognitionResult(text: text, isFinal: true));
    await _controller!.close();
  }

  Future<void> emitError(Object error) async {
    _controller!.addError(error);
    await _controller!.close();
  }

  Future<void> endWithoutFinal() => _controller!.close();

  @override
  Future<VoicePermission> permissionStatus() async => status;

  @override
  Future<VoicePermission> requestPermission() async {
    requests++;
    status = afterRequest;
    return afterRequest;
  }

  @override
  Future<void> openPermissionSettings() async => settingsOpened++;

  @override
  Stream<SpeechRecognitionResult> listen(SourceLanguage language) {
    final error = listenThrows;
    if (error != null) throw error;
    this.language = language;
    _controller = StreamController<SpeechRecognitionResult>();
    return _controller!.stream;
  }

  @override
  Future<void> stop() async => stops++;

  @override
  Future<void> cancel() async {
    cancels++;
    final controller = _controller;
    if (controller != null && !controller.isClosed) await controller.close();
  }
}
