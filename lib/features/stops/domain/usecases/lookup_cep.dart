import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/address_lookup.dart';
import '../repositories/address_repository.dart';

class LookupCep implements UseCase<AddressLookup, LookupCepParams> {
  final AddressRepository repository;

  LookupCep(this.repository);

  @override
  Future<Either<Failure, AddressLookup>> call(LookupCepParams params) {
    return repository.lookupCep(params.cep);
  }
}

class LookupCepParams extends Equatable {
  final String cep;

  const LookupCepParams(this.cep);

  @override
  List<Object> get props => [cep];
}
