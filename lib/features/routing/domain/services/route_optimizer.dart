import '../../../stops/domain/entities/delivery_stop.dart';
import '../entities/route_option.dart';
import '../entities/route_strategy.dart';
import '../entities/travel_matrix.dart';

/// Monta a ordem das paradas a partir de uma matriz de custos.
///
/// O problema é um TSP de caminho aberto com origem fixa (a localização atual)
/// — aberto porque o entregador não precisa voltar ao ponto de partida.
/// Resolver TSP exato é inviável acima de ~12 paradas, então usamos
/// vizinho-mais-próximo para uma solução inicial e 2-opt para melhorá-la.
/// Na prática isso fica dentro de ~5% do ótimo, o que é bem mais preciso do
/// que a estimativa de tempo que alimenta o cálculo.
class RouteOptimizer {
  const RouteOptimizer();

  /// Acima disso o 2-opt fica caro demais para rodar na thread de UI.
  /// Nenhum entregador autônomo faz 150 paradas num roteiro, então o limite
  /// nunca deve ser atingido na prática — é só uma trava de segurança.
  static const int _maxStopsForRefinement = 150;

  /// Limite de passadas do 2-opt. Ele normalmente converge em 3-5.
  static const int _maxRefinementPasses = 40;

  /// [stops] deve conter apenas paradas roteáveis, na mesma ordem usada para
  /// montar [matrix] — cujo índice 0 é a origem e 1..N são as paradas.
  RouteOption optimize({
    required RouteStrategy strategy,
    required List<DeliveryStop> stops,
    required TravelMatrix matrix,
    required Duration serviceTimePerStop,
  }) {
    assert(
      matrix.size == stops.length + 1,
      'A matriz precisa ter origem + ${stops.length} paradas, '
      'mas tem ${matrix.size} pontos.',
    );

    // A métrica que guia a ordenação muda conforme a estratégia. É isso que
    // faz "mais rápida" e "mais econômica" darem ordens realmente diferentes.
    double cost(int from, int to) => switch (strategy) {
          RouteStrategy.shortest => matrix.distanceBetween(from, to),
          RouteStrategy.fastest ||
          RouteStrategy.nearestFirst =>
            matrix.durationBetween(from, to),
        };

    var order = _nearestNeighbour(matrix.size, cost);

    // "Mais próxima primeiro" é literalmente o resultado cru do guloso — se
    // refinássemos, ela deixaria de cumprir o que promete ao usuário.
    if (strategy != RouteStrategy.nearestFirst &&
        stops.length <= _maxStopsForRefinement) {
      order = _refineWithTwoOpt(order, cost);
    }

    return _buildOption(
      strategy: strategy,
      order: order,
      stops: stops,
      matrix: matrix,
      serviceTimePerStop: serviceTimePerStop,
    );
  }

  /// Solução inicial: a partir do ponto atual, vai sempre para o mais barato
  /// ainda não visitado.
  List<int> _nearestNeighbour(int size, double Function(int, int) cost) {
    final visited = List<bool>.filled(size, false);
    final order = <int>[0];
    visited[0] = true;
    var current = 0;

    for (var step = 1; step < size; step++) {
      var best = -1;
      var bestCost = double.infinity;

      for (var candidate = 1; candidate < size; candidate++) {
        if (visited[candidate]) continue;
        final c = cost(current, candidate);
        if (c < bestCost) {
          bestCost = c;
          best = candidate;
        }
      }

      if (best == -1) break;
      visited[best] = true;
      order.add(best);
      current = best;
    }

    return order;
  }

  /// 2-opt: procura pares de trechos que se cruzam e desfaz o cruzamento
  /// invertendo o segmento entre eles. Repete até não achar mais melhoria.
  ///
  /// Assume matriz simétrica — inverter um segmento não muda o custo interno
  /// dele. Isso vale para a estimativa haversine e é aproximadamente verdade
  /// em malha viária real. Se um dia entrar um provider fortemente assimétrico
  /// (muitas mãos únicas), o ganho continua válido mas o delta calculado aqui
  /// passa a ser aproximado.
  List<int> _refineWithTwoOpt(
    List<int> initialOrder,
    double Function(int, int) cost,
  ) {
    final route = List<int>.from(initialOrder);
    var improved = true;
    var passes = 0;

    while (improved && passes < _maxRefinementPasses) {
      improved = false;
      passes++;

      // i começa em 1: a origem está fixa na posição 0.
      for (var i = 1; i < route.length - 1; i++) {
        for (var j = i + 1; j < route.length; j++) {
          if (_twoOptDelta(route, i, j, cost) < -1e-9) {
            _reverseSegment(route, i, j);
            improved = true;
          }
        }
      }
    }

    return route;
  }

  /// Quanto o custo total muda ao inverter o segmento `[i..j]`.
  /// Negativo = melhoria.
  double _twoOptDelta(
    List<int> route,
    int i,
    int j,
    double Function(int, int) cost,
  ) {
    final before = route[i - 1];
    final segmentStart = route[i];
    final segmentEnd = route[j];

    // Última posição: a rota é aberta, então só a aresta de entrada muda.
    if (j == route.length - 1) {
      return cost(before, segmentEnd) - cost(before, segmentStart);
    }

    final after = route[j + 1];
    final removed = cost(before, segmentStart) + cost(segmentEnd, after);
    final added = cost(before, segmentEnd) + cost(segmentStart, after);
    return added - removed;
  }

  void _reverseSegment(List<int> route, int i, int j) {
    var left = i;
    var right = j;
    while (left < right) {
      final tmp = route[left];
      route[left] = route[right];
      route[right] = tmp;
      left++;
      right--;
    }
  }

  RouteOption _buildOption({
    required RouteStrategy strategy,
    required List<int> order,
    required List<DeliveryStop> stops,
    required TravelMatrix matrix,
    required Duration serviceTimePerStop,
  }) {
    final legs = <RouteLeg>[];
    var travelSeconds = 0.0;
    var distanceMeters = 0.0;

    for (var position = 1; position < order.length; position++) {
      final fromIndex = order[position - 1];
      final toIndex = order[position];

      final duration = matrix.durationBetween(fromIndex, toIndex);
      final distance = matrix.distanceBetween(fromIndex, toIndex);

      travelSeconds += duration;
      distanceMeters += distance;

      legs.add(RouteLeg(
        // Índice 0 é a origem, que não é uma parada.
        from: fromIndex == 0 ? null : stops[fromIndex - 1],
        to: stops[toIndex - 1],
        distanceMeters: distance,
        durationSeconds: duration,
      ));
    }

    return RouteOption(
      strategy: strategy,
      legs: legs,
      travelDurationSeconds: travelSeconds,
      serviceDurationSeconds:
          legs.length * serviceTimePerStop.inSeconds.toDouble(),
      totalDistanceMeters: distanceMeters,
      isEstimate: matrix.isEstimate,
    );
  }
}
