import 'package:dartz/dartz.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/geo/geo_point.dart';
import '../../../../core/settings/app_settings.dart';
import '../../domain/entities/travel_matrix.dart';
import '../../domain/repositories/travel_matrix_provider.dart';

/// Estimativa local de tempo e distância. Não usa rede, não usa API key,
/// funciona no meio do nada.
///
/// A conta é: distância em linha reta × fator de sinuosidade ÷ velocidade
/// média. É grosseira em valor absoluto, mas o que importa para escolher a
/// ordem das paradas é o custo *relativo* entre elas — e nisso ela acerta bem.
/// A UI sempre marca o resultado como estimativa para não vender precisão que
/// não existe.
class HaversineMatrixProvider implements TravelMatrixProvider {
  /// Rua não é linha reta. 1.35 é uma média razoável para malha urbana
  /// brasileira — quarteirões em grade ficam perto de 1.27, bairros com muito
  /// contorno e rio/ferrovia no meio passam de 1.5.
  final double sinuosityFactor;

  /// Velocidade média porta a porta em km/h, usada quando não há [settings].
  /// 28 km/h é típico de moto em cidade média; carro em capital fica mais perto
  /// de 20.
  final double fallbackSpeedKmh;

  /// Quando presente, a velocidade é lida daqui **a cada cálculo** — não na
  /// construção. Sem isso, ajustar a velocidade nas preferências só teria
  /// efeito depois de reiniciar o app, já que o provider é singleton.
  final AppSettings? settings;

  const HaversineMatrixProvider({
    this.sinuosityFactor = 1.35,
    this.fallbackSpeedKmh = 28.0,
    this.settings,
  });

  double get _speedKmh => settings?.averageSpeedKmh ?? fallbackSpeedKmh;

  @override
  Future<Either<Failure, TravelMatrix>> buildMatrix(
    List<GeoPoint> points,
  ) async {
    if (points.length < 2) return Left(EmptyRouteFailure());

    final metersPerSecond = _speedKmh * 1000 / 3600;
    final size = points.length;

    final distances = List.generate(
      size,
      (_) => List<double>.filled(size, 0.0),
      growable: false,
    );
    final durations = List.generate(
      size,
      (_) => List<double>.filled(size, 0.0),
      growable: false,
    );

    // Matriz simétrica: calcula metade e espelha.
    for (var i = 0; i < size; i++) {
      for (var j = i + 1; j < size; j++) {
        final meters = points[i].haversineDistanceTo(points[j]) * sinuosityFactor;
        final seconds = meters / metersPerSecond;

        distances[i][j] = meters;
        distances[j][i] = meters;
        durations[i][j] = seconds;
        durations[j][i] = seconds;
      }
    }

    return Right(TravelMatrix(
      durations: durations,
      distances: distances,
      isEstimate: true,
    ));
  }
}
