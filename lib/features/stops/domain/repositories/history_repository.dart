import 'package:dartz/dartz.dart';

import '../../../../core/error/failures.dart';
import '../entities/delivery_record.dart';

abstract class HistoryRepository {
  /// Entregas concluídas, agrupadas por dia, do mais recente para o mais
  /// antigo.
  Future<Either<Failure, List<DeliveryDay>>> getHistory();

  Future<Either<Failure, void>> clearHistory();
}
