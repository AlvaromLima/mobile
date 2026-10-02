// Gera os ícones do app (Android e iOS) e imprime as cores de splash derivadas do tema.
// Uso (a partir de app/): flutter test tool/generate_icons_test.dart
// Não roda na suíte normal (fica fora de test/). Ícone provisório até a arte oficial.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradutor/core/theme/app_theme.dart';

const _brand = Color(0xFF1E5AA8);

/// Fonte dos ícones Material distribuída com o SDK do Flutter.
String get _materialIconsFont {
  // O executável de teste fica em <flutter>/bin/cache/artifacts/engine/<plataforma>/.
  final exe = Platform.resolvedExecutable.replaceAll(r'\', '/');
  final cache = exe.substring(0, exe.indexOf('/bin/cache/') + '/bin/cache'.length);
  return '$cache/artifacts/material_fonts/materialicons-regular.otf';
}

Future<Uint8List> _render(WidgetTester tester, double size, Widget child) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: RepaintBoundary(key: key, child: SizedBox.square(dimension: size, child: child))),
    ),
  );
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return _encodePng(image.width, image.height, data!.buffer.asUint8List(), opaque: false);
  }))!;
}

Future<Uint8List> _renderOpaque(WidgetTester tester, double size, Widget child) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: RepaintBoundary(key: key, child: SizedBox.square(dimension: size, child: child))),
    ),
  );
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    // App Store rejeita ícone com canal alfa: grava RGB.
    return _encodePng(image.width, image.height, data!.buffer.asUint8List(), opaque: true);
  }))!;
}

/// Codificador PNG mínimo (8 bits, RGB ou RGBA), para gerar ícones sem canal alfa.
Uint8List _encodePng(int width, int height, Uint8List rgba, {required bool opaque}) {
  final channels = opaque ? 3 : 4;
  final raw = BytesBuilder();
  for (var y = 0; y < height; y++) {
    raw.addByte(0); // filtro "None"
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      raw.add(rgba.sublist(i, i + channels));
    }
  }

  final crcTable = List<int>.generate(256, (n) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
    }
    return c;
  });
  int crc(List<int> bytes) {
    var c = 0xFFFFFFFF;
    for (final b in bytes) {
      c = crcTable[(c ^ b) & 0xFF] ^ (c >>> 8);
    }
    return c ^ 0xFFFFFFFF;
  }

  final out = BytesBuilder()..add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  void chunk(String type, List<int> data) {
    final typed = [...type.codeUnits, ...data];
    out
      ..add((ByteData(4)..setUint32(0, data.length)).buffer.asUint8List())
      ..add(typed)
      ..add((ByteData(4)..setUint32(0, crc(typed))).buffer.asUint8List());
  }

  final header = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8)
    ..setUint8(9, opaque ? 2 : 6);
  chunk('IHDR', header.buffer.asUint8List());
  chunk('IDAT', ZLibCodec(level: 9).encode(raw.toBytes()));
  chunk('IEND', const []);
  return out.toBytes();
}

/// Ícone completo: símbolo de tradução branco sobre o azul do tema.
Widget _fullIcon(double size) => ColoredBox(
      color: _brand,
      child: Center(child: Icon(Icons.translate, size: size * 0.62, color: Colors.white)),
    );

/// Primeiro plano do ícone adaptativo do Android: só o símbolo, dentro da zona segura (66 de 108).
Widget _foreground(double size) => Center(child: Icon(Icons.translate, size: size * 0.42, color: Colors.white));

void main() {
  setUpAll(() async {
    final loader = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(File(_materialIconsFont).readAsBytesSync())));
    await loader.load();
  });

  testWidgets('gera ícones', (tester) async {
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const res = 'android/app/src/main/res';
    const densities = {'mdpi': 1.0, 'hdpi': 1.5, 'xhdpi': 2.0, 'xxhdpi': 3.0, 'xxxhdpi': 4.0};
    for (final MapEntry(key: density, value: factor) in densities.entries) {
      File('$res/mipmap-$density/ic_launcher.png').writeAsBytesSync(await _render(tester, 48 * factor, _fullIcon(48 * factor)));
      File('$res/mipmap-$density/ic_launcher_foreground.png')
          .writeAsBytesSync(await _render(tester, 108 * factor, _foreground(108 * factor)));
    }

    const ios = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
    final sizes = RegExp(r'"size" : "([\d.]+)x[\d.]+",\s*"idiom" : "[a-z-]+",\s*"filename" : "([^"]+)",\s*"scale" : "(\d)x"');
    final contents = File('$ios/Contents.json').readAsStringSync();
    final generated = <String>{};
    for (final m in sizes.allMatches(contents)) {
      final file = m.group(2)!;
      if (!generated.add(file)) continue;
      final pixels = double.parse(m.group(1)!) * int.parse(m.group(3)!);
      File('$ios/$file').writeAsBytesSync(await _renderOpaque(tester, pixels, _fullIcon(pixels)));
    }
    expect(generated, isNotEmpty, reason: 'Contents.json do iOS lido');

    // Cores de fundo da abertura (splash), iguais à superfície do tema claro e escuro.
    String hex(Color c) => '#${c.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
    debugPrint('splash claro: ${hex(AppTheme.light.colorScheme.surface)}');
    debugPrint('splash escuro: ${hex(AppTheme.dark.colorScheme.surface)}');
    debugPrint('ícones iOS gerados: ${generated.length}');
  });
}
