import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/delivery_stop.dart';
import '../repositories/stops_repository.dart';

class SetStopStatus implements UseCase<DeliveryStop, SetStopStatusParams> {
  final StopsRepository repository;

  SetStopStatus(this.repository);

  @override
  Future<Either<Failure, DeliveryStop>> call(SetStopStatusParams params) {
    return repository.setStatus(params.stop, params.status);
  }
}

class SetStopStatusParams extends Equatable {
  final DeliveryStop stop;
  final StopStatus status;

  const SetStopStatusParams({required this.stop, required this.status});

  @override
  List<Object> get props => [stop, status];
}
