import 'package:equatable/equatable.dart';

/// Matriz N×N de custos entre pontos. O índice 0 é sempre a origem
/// (localização atual do usuário); 1..N-1 são as paradas, na mesma ordem em
/// que foram passadas.
class TravelMatrix extends Equatable {
  /// `durations[i][j]` = segundos para ir de i até j.
  final List<List<double>> durations;

  /// `distances[i][j]` = metros para ir de i até j.
  final List<List<double>> distances;

  /// `true` quando os valores vieram de estimativa local (haversine), e não de
  /// um serviço de rotas real. A UI precisa disso para avisar o usuário.
  final bool isEstimate;

  const TravelMatrix({
    required this.durations,
    required this.distances,
    required this.isEstimate,
  });

  int get size => durations.length;

  double durationBetween(int from, int to) => durations[from][to];

  double distanceBetween(int from, int to) => distances[from][to];

  @override
  List<Object> get props => [durations, distances, isEstimate];
}
