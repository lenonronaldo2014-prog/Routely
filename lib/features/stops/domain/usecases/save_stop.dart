import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/delivery_stop.dart';
import '../repositories/stops_repository.dart';

class SaveStop implements UseCase<DeliveryStop, SaveStopParams> {
  final StopsRepository repository;

  SaveStop(this.repository);

  @override
  Future<Either<Failure, DeliveryStop>> call(SaveStopParams params) {
    return repository.saveStop(params.stop);
  }
}

class SaveStopParams extends Equatable {
  final DeliveryStop stop;

  const SaveStopParams(this.stop);

  @override
  List<Object> get props => [stop];
}
