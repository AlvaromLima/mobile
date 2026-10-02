import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/app_config.dart';

void main() {
  // Falha imediata se a URL do backend estiver ausente ou insegura no build de release.
  AppConfig.apiBaseUrl;
  runApp(const ProviderScope(child: TradutorApp()));
}
