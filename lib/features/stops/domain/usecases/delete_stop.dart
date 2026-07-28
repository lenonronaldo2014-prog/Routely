import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../repositories/stops_repository.dart';

class DeleteStop implements UseCase<void, DeleteStopParams> {
  final StopsRepository repository;

  DeleteStop(this.repository);

  @override
  Future<Either<Failure, void>> call(DeleteStopParams params) {
    return repository.deleteStop(params.id);
  }
}

class DeleteStopParams extends Equatable {
  final String id;

  const DeleteStopParams(this.id);

  @override
  List<Object> get props => [id];
}
