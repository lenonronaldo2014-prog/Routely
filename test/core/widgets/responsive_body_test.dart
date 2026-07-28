import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routely/core/theme/app_breakpoints.dart';
import 'package:routely/core/widgets/responsive_body.dart';

/// Chave própria porque `ColoredBox` sozinho casa com widgets internos do
/// Material e o finder fica ambíguo.
const contentKey = Key('conteudo');

Widget _host({required Widget child, required Size size}) {
  return MediaQuery(
    data: MediaQueryData(size: size),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: MaterialApp(home: Scaffold(body: child)),
    ),
  );
}

Widget _content() =>
    const SizedBox.expand(child: ColoredBox(key: contentKey, color: Colors.red));

void main() {
  group('ResponsiveBody', () {
    // Regressão: a primeira versão usava Align + ConstrainedBox, que afrouxa as
    // constraints e fazia o ListView embaixo perder a altura — a tela do
    // formulário aparecia completamente em branco no aparelho.
    testWidgets('não colapsa a altura de um ListView filho', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_host(
        size: const Size(400, 800),
        child: ResponsiveBody(
          child: ListView(
            children: const [
              SizedBox(height: 80, child: Text('primeiro')),
              SizedBox(height: 80, child: Text('segundo')),
            ],
          ),
        ),
      ));

      expect(find.text('primeiro'), findsOneWidget);
      expect(find.text('segundo'), findsOneWidget);

      final listSize = tester.getSize(find.byType(ListView));
      expect(
        listSize.height,
        greaterThan(0),
        reason: 'o ListView precisa herdar a altura da tela',
      );
    });

    testWidgets('ocupa a largura toda num celular estreito', (tester) async {
      const screenWidth = 380.0;
      await tester.binding.setSurfaceSize(const Size(screenWidth, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_host(
        size: const Size(screenWidth, 800),
        child: ResponsiveBody(child: _content()),
      ));

      final width = tester.getSize(find.byKey(contentKey)).width;

      // Só a margem lateral normal é descontada — nada de clamp aqui, porque a
      // tela é mais estreita que a largura máxima de leitura.
      expect(width, lessThan(screenWidth));
      expect(width, greaterThan(screenWidth - 80));
    });

    testWidgets('limita a largura do conteúdo num tablet', (tester) async {
      const screenWidth = 1200.0;
      await tester.binding.setSurfaceSize(const Size(screenWidth, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_host(
        size: const Size(screenWidth, 900),
        child: ResponsiveBody(child: _content()),
      ));

      final width = tester.getSize(find.byKey(contentKey)).width;

      expect(
        width,
        lessThanOrEqualTo(AppBreakpoints.maxContentWidth),
        reason: 'sem clamp, cada linha de texto atravessaria 1200px',
      );
    });

    testWidgets('centraliza o conteúdo na tela larga', (tester) async {
      const screenWidth = 1200.0;
      await tester.binding.setSurfaceSize(const Size(screenWidth, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_host(
        size: const Size(screenWidth, 900),
        child: ResponsiveBody(child: _content()),
      ));

      final rect = tester.getRect(find.byKey(contentKey));
      final leftGap = rect.left;
      final rightGap = screenWidth - rect.right;

      expect(leftGap, closeTo(rightGap, 0.5));
    });

    testWidgets('modo wide permite conteúdo mais largo', (tester) async {
      const screenWidth = 1200.0;
      await tester.binding.setSurfaceSize(const Size(screenWidth, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_host(
        size: const Size(screenWidth, 900),
        child: ResponsiveBody(wide: true, child: _content()),
      ));

      final width = tester.getSize(find.byKey(contentKey)).width;

      expect(width, greaterThan(AppBreakpoints.maxContentWidth));
      expect(width, lessThanOrEqualTo(AppBreakpoints.maxWideContentWidth));
    });
  });
}
