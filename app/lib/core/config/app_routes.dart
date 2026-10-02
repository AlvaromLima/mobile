import 'package:flutter/widgets.dart';

import '../../screens/home_screen.dart';

/// Rotas nomeadas do app. Navegação nativa do Flutter (Navigator), sem pacote extra.
abstract final class AppRoutes {
  static const home = '/';

  static final Map<String, WidgetBuilder> routes = {
    home: (_) => const HomeScreen(),
  };
}
