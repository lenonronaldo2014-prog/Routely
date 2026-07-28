import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routely/core/geo/geo_point.dart';
import 'package:routely/core/theme/app_theme.dart';
import 'package:routely/features/routing/domain/entities/route_option.dart';
import 'package:routely/features/routing/domain/entities/route_strategy.dart';
import 'package:routely/features/routing/presentation/widgets/route_option_card.dart';
import 'package:routely/features/stops/domain/entities/delivery_stop.dart';

DeliveryStop _stop(String id) => DeliveryStop(
      id: id,
      street: 'Rua $id',
      number: '100',
      coordinate: const GeoPoint(latitude: -23.55, longitude: -46.63),
      createdAt: DateTime(2026, 1, 1),
    );

RouteOption _option(
  RouteStrategy strategy, {
  required double travelSeconds,
  required double meters,
  int stops = 3,
}) {
  final legs = List.generate(
    stops,
    (i) => RouteLeg(
      from: i == 0 ? null : _stop('p$i'),
      to: _stop('p${i + 1}'),
      distanceMeters: meters / stops,
      durationSeconds: travelSeconds / stops,
    ),
  );

  return RouteOption(
    strategy: strategy,
    legs: legs,
    travelDurationSeconds: travelSeconds,
    serviceDurationSeconds: stops * 180,
    totalDistanceMeters: meters,
    isEstimate: true,
  );
}

Widget _host(Widget child, {Size size = const Size(400, 900)}) {
  return MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: MediaQuery(
        data: MediaQueryData(size: size),
        child: SingleChildScrollView(child: child),
      ),
    ),
  );
}

void main() {
  group('RouteOptionCard', () {
    testWidgets('mostra rótulo, tempo, distância e paradas', (tester) async {
      await tester.pumpWidget(_host(RouteOptionCard(
        option: _option(
          RouteStrategy.fastest,
          travelSeconds: 2700,
          meters: 12400,
        ),
        onTap: () {},
      )));

      expect(find.text('Mais rápida'), findsOneWidget);
      expect(find.text('Menor tempo total no trânsito'), findsOneWidget);
      // 2700s de viagem + 3×180s de parada = 3240s = 54min
      expect(find.text('54min'), findsOneWidget);
      expect(find.text('12,4 km'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('deixa explícito o tempo parado nas entregas', (tester) async {
      await tester.pumpWidget(_host(RouteOptionCard(
        option: _option(
          RouteStrategy.shortest,
          travelSeconds: 3600,
          meters: 9000,
        ),
        onTap: () {},
      )));

      expect(
        find.text('1h dirigindo · 9min nas entregas'),
        findsOneWidget,
        reason: 'omitir o tempo de parada é o que deixa a estimativa otimista',
      );
    });

    testWidgets('marca só a opção sugerida', (tester) async {
      await tester.pumpWidget(_host(Column(
        children: [
          RouteOptionCard(
            option: _option(
              RouteStrategy.fastest,
              travelSeconds: 2400,
              meters: 14000,
            ),
            isRecommended: true,
            onTap: () {},
          ),
          RouteOptionCard(
            option: _option(
              RouteStrategy.shortest,
              travelSeconds: 3000,
              meters: 9000,
            ),
            onTap: () {},
          ),
        ],
      )));

      expect(find.text('SUGERIDA'), findsOneWidget);
    });

    testWidgets('as três estratégias renderizam juntas e distintas',
        (tester) async {
      await tester.pumpWidget(_host(
        Column(
          children: [
            for (final strategy in RouteStrategy.values)
              RouteOptionCard(
                option: _option(
                  strategy,
                  travelSeconds: 2400,
                  meters: 10000,
                ),
                onTap: () {},
              ),
          ],
        ),
        size: const Size(400, 1400),
      ));

      for (final strategy in RouteStrategy.values) {
        expect(find.text(strategy.label), findsOneWidget);
        expect(find.text(strategy.description), findsOneWidget);
      }
    });

    testWidgets('cabe numa tela estreita sem estourar', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_host(
        RouteOptionCard(
          option: _option(
            RouteStrategy.nearestFirst,
            travelSeconds: 7200,
            meters: 48000,
          ),
          onTap: () {},
        ),
        size: const Size(320, 700),
      ));

      expect(tester.takeException(), isNull);
      expect(find.text('Mais próxima primeiro'), findsOneWidget);
    });

    testWidgets('dispara onTap ao ser tocado', (tester) async {
      var tapped = false;

      await tester.pumpWidget(_host(RouteOptionCard(
        option: _option(
          RouteStrategy.fastest,
          travelSeconds: 1800,
          meters: 5000,
        ),
        onTap: () => tapped = true,
      )));

      await tester.tap(find.text('Mais rápida'));
      await tester.pump();

      expect(tapped, isTrue);
    });
  });
}
