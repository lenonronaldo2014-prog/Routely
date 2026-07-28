import 'dart:io';

import 'package:image/image.dart';

/// Prepara a cor de fundo do ícone adaptativo a partir da arte.
///
/// Todo o redimensionamento é do `flutter_launcher_icons` — ele gera as
/// densidades do Android e os tamanhos do iOS a partir de um único PNG, e
/// aplica o recuo da camada adaptativa via XML. Não faz sentido duplicar isso
/// aqui.
///
/// O que a biblioteca **não** resolve é o casamento do fundo: no ícone
/// adaptativo a arte entra recuada, e o que aparece em volta é a cor de fundo.
/// Se ela não for exatamente o verde da arte, dá para ver o quadrado da
/// ilustração flutuando dentro do círculo. Este script tira a cor da própria
/// arte e grava um fundo sólido igual — se um dia a arte mudar, o fundo
/// acompanha sozinho.
///
/// Rodar:
///   dart run tool/generate_icon.dart
///   dart run flutter_launcher_icons
/// Recorte aplicado sobre a arte, em fração do lado.
///
/// A arte original é de divulgação: tem o nome do app, slogan e tarja. Isso
/// funciona num banner, mas na gaveta o ícone aparece com ~48px — nesse
/// tamanho o texto vira mancha e some junto com o resto.
///
/// O recorte fica com a ilustração (mapa, estrada, pins e a van), que é o que
/// ainda se lê pequeno. Ajuste aqui se quiser reenquadrar.
/// Enquadramento: para na altura em que o texto começa e alinha à direita o
/// suficiente para a van caber inteira. O pin da esquerda entra cortado de
/// propósito — no tamanho real a van é a silhueta que mais se lê, e ela tem
/// prioridade.
const _cropSize = 0.65;
const _cropLeft = 0.21;
const _cropTop = 0.03;

void main() {
  const sourcePath = 'assets/icon/source.png';
  const framedPath = 'assets/icon/icon.png';
  const backgroundPath = 'assets/icon/background.png';
  // Versão reduzida para a marca dentro do app. Carregar o PNG de 1024 num
  // widget de 44dp desperdiçaria memória à toa.
  const appMarkPath = 'assets/icon/app_mark.png';

  final file = File(sourcePath);
  if (!file.existsSync()) {
    stderr.writeln('Não achei $sourcePath.');
    stderr.writeln('Coloque a arte do ícone lá (PNG quadrado, 1024×1024).');
    exitCode = 1;
    return;
  }

  final source = decodeImage(file.readAsBytesSync());
  if (source == null) {
    stderr.writeln('Não consegui ler $sourcePath — é PNG mesmo?');
    exitCode = 1;
    return;
  }

  if (source.width != source.height) {
    stderr.writeln(
      'Aviso: a arte não é quadrada (${source.width}×${source.height}). '
      'O ícone vai sair distorcido.',
    );
  }

  final framed = _crop(source);
  File(framedPath).writeAsBytesSync(encodePng(framed, level: 6));
  stdout.writeln('Ícone enquadrado em $framedPath');

  // 256px cobre 44dp até em tela de densidade 4x, com folga.
  final appMark = copyResize(
    framed,
    width: 256,
    height: 256,
    interpolation: Interpolation.average,
  );
  File(appMarkPath).writeAsBytesSync(encodePng(appMark, level: 6));
  stdout.writeln('Marca do app em $appMarkPath');

  final color = _edgeColor(framed);

  final background = Image(width: 1024, height: 1024, numChannels: 4);
  fill(background, color: color);
  File(backgroundPath).writeAsBytesSync(encodePng(background, level: 6));

  stdout.writeln('Fundo gerado em $backgroundPath');
  stdout.writeln('  cor: ${_hex(color)}');
  stdout.writeln('Agora rode: dart run flutter_launcher_icons');
}

/// Recorta a região útil da arte e normaliza para 1024×1024.
Image _crop(Image source) {
  final side = (source.width * _cropSize).round();

  final cropped = copyCrop(
    source,
    x: (source.width * _cropLeft).round(),
    y: (source.height * _cropTop).round(),
    width: side,
    height: side,
  );

  return copyResize(
    cropped,
    width: 1024,
    height: 1024,
    interpolation: Interpolation.cubic,
  );
}

/// Cor predominante da borda da arte.
///
/// Amostra pontos ao longo das quatro bordas e tira a mediana. Média puxaria
/// a cor na direção de algum detalhe isolado; mediana pega o que realmente
/// domina o contorno.
Color _edgeColor(Image source) {
  final reds = <int>[];
  final greens = <int>[];
  final blues = <int>[];

  // Um pouco para dentro: a borda exata costuma ser canto arredondado
  // transparente, que não representa a cor da arte.
  final inset = (source.width * 0.12).round();

  for (var i = inset; i < source.width - inset; i += 4) {
    for (final point in [
      (i, inset),
      (i, source.height - inset - 1),
      (inset, i),
      (source.width - inset - 1, i),
    ]) {
      final pixel = source.getPixel(point.$1, point.$2);
      if (pixel.a < 200) continue;
      reds.add(pixel.r.toInt());
      greens.add(pixel.g.toInt());
      blues.add(pixel.b.toInt());
    }
  }

  if (reds.isEmpty) {
    stderr.writeln('Aviso: a borda da arte é toda transparente. '
        'Usando o verde da marca.');
    return ColorRgb8(0x14, 0x60, 0x3F);
  }

  return ColorRgb8(_median(reds), _median(greens), _median(blues));
}

int _median(List<int> values) {
  values.sort();
  return values[values.length ~/ 2];
}

String _hex(Color color) {
  String two(num value) =>
      value.toInt().toRadixString(16).padLeft(2, '0').toUpperCase();
  return '#${two(color.r)}${two(color.g)}${two(color.b)}';
}
