import 'package:dartz/dartz.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/geo/geo_point.dart';
import '../entities/travel_matrix.dart';

/// Fonte dos tempos e distâncias entre pontos.
///
/// Existe como interface porque a fonte muda conforme o contexto: offline usa
/// estimativa local, online pode usar OSRM próprio ou uma API paga. Trocar o
/// provider é uma linha no `injection_container` — nada no domínio muda.
abstract class TravelMatrixProvider {
  /// [points] tem a origem no índice 0 e as paradas em 1..N.
  Future<Either<Failure, TravelMatrix>> buildMatrix(List<GeoPoint> points);
}
