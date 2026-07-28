import 'package:dartz/dartz.dart';

import '../../../../core/error/failures.dart';
import '../entities/delivery_stop.dart';

abstract class StopsRepository {
  Future<Either<Failure, List<DeliveryStop>>> getStops();

  /// Salva a parada. Se ela ainda não tem coordenada e há rede, tenta
  /// geocodificar — mas o salvamento nunca falha por causa disso.
  Future<Either<Failure, DeliveryStop>> saveStop(DeliveryStop stop);

  Future<Either<Failure, void>> deleteStop(String id);

  Future<Either<Failure, DeliveryStop>> setStatus(
    DeliveryStop stop,
    StopStatus status,
  );

  /// Remove entregues e não entregues, mantendo só as pendentes.
  Future<Either<Failure, int>> clearCompleted();

  /// Tenta geocodificar todas as paradas que ainda estão sem coordenada.
  /// Chamado quando a rede volta.
  Future<Either<Failure, List<DeliveryStop>>> resolvePendingCoordinates();
}
