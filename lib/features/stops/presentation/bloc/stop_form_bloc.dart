import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/util/id_generator.dart';
import '../../domain/entities/delivery_stop.dart';
import '../../domain/usecases/lookup_cep.dart';
import '../../domain/usecases/save_stop.dart';
import 'stop_form_event.dart';
import 'stop_form_state.dart';

class StopFormBloc extends Bloc<StopFormEvent, StopFormState> {
  final LookupCep lookupCep;
  final SaveStop saveStop;

  StopFormBloc({
    required this.lookupCep,
    required this.saveStop,
  }) : super(const StopFormState()) {
    on<StopFormStarted>(_onStarted);
    on<CepLookupRequested>(_onCepLookup);
    on<StopLocationPicked>(_onLocationPicked);
    on<StopFormSubmitted>(_onSubmit);
  }

  void _onStarted(StopFormStarted event, Emitter<StopFormState> emit) {
    emit(StopFormState(existing: event.existing));
  }

  void _onLocationPicked(
    StopLocationPicked event,
    Emitter<StopFormState> emit,
  ) {
    emit(state.copyWith(pickedCoordinate: event.coordinate));
  }

  Future<void> _onCepLookup(
    CepLookupRequested event,
    Emitter<StopFormState> emit,
  ) async {
    emit(state.copyWith(
      isLookingUpCep: true,
      clearCepError: true,
      clearCepResult: true,
    ));

    final result = await lookupCep(LookupCepParams(event.cep));

    result.fold(
      (failure) => emit(state.copyWith(
        isLookingUpCep: false,
        cepError: _mapCepFailure(failure),
      )),
      (lookup) => emit(state.copyWith(
        isLookingUpCep: false,
        cepResult: lookup,
      )),
    );
  }

  Future<void> _onSubmit(
    StopFormSubmitted event,
    Emitter<StopFormState> emit,
  ) async {
    emit(state.copyWith(
      status: StopFormStatus.saving,
      clearSaveError: true,
    ));

    final existing = state.existing;

    final stop = DeliveryStop(
      id: existing?.id ?? IdGenerator.generate(),
      label: _nullIfBlank(event.label),
      street: event.street.trim(),
      number: _nullIfBlank(event.number),
      complement: _nullIfBlank(event.complement),
      neighborhood: _nullIfBlank(event.neighborhood),
      city: _nullIfBlank(event.city),
      state: _nullIfBlank(event.state),
      cep: _nullIfBlank(event.cep),
      // Ordem de precedência da coordenada:
      //
      // 1. o pino que o usuário marcou no mapa — ele estava olhando para a
      //    porta, nenhum serviço de geocoding tem essa informação;
      // 2. a que a parada já tinha, se o endereço não mudou;
      // 3. nenhuma — aí o repositório geocodifica na hora de salvar.
      coordinate: state.pickedCoordinate ??
          (_addressUnchanged(existing, event) ? existing?.coordinate : null),
      notes: _nullIfBlank(event.notes),
      status: existing?.status ?? StopStatus.pending,
      createdAt: existing?.createdAt ?? DateTime.now(),
      completedAt: existing?.completedAt,
    );

    final result = await saveStop(SaveStopParams(stop));

    result.fold(
      (failure) => emit(state.copyWith(
        status: StopFormStatus.editing,
        saveError: _mapSaveFailure(failure),
      )),
      (saved) => emit(state.copyWith(
        status: StopFormStatus.saved,
        savedWithoutCoordinate: !saved.isRoutable,
      )),
    );
  }

  bool _addressUnchanged(DeliveryStop? existing, StopFormSubmitted event) {
    if (existing == null) return false;
    return existing.street == event.street.trim() &&
        existing.number == _nullIfBlank(event.number) &&
        existing.city == _nullIfBlank(event.city) &&
        existing.cep == _nullIfBlank(event.cep);
  }

  String? _nullIfBlank(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String _mapCepFailure(Failure failure) {
    if (failure is GeocodingFailure) {
      return failure.message.isEmpty ? 'CEP não encontrado.' : failure.message;
    }
    if (failure is ConnectionFailure) {
      return 'Sem conexão. Preencha o endereço manualmente.';
    }
    return 'Não foi possível consultar o CEP.';
  }

  String _mapSaveFailure(Failure failure) {
    if (failure is CacheFailure) return 'Não foi possível salvar no aparelho.';
    return 'Erro ao salvar. Tente novamente.';
  }
}
