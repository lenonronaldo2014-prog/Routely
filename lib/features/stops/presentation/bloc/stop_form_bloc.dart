import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/util/id_generator.dart';
import '../../domain/entities/delivery_stop.dart';
import '../../domain/repositories/address_repository.dart';
import '../../domain/usecases/lookup_cep.dart';
import '../../domain/usecases/save_stop.dart';
import 'stop_form_event.dart';
import 'stop_form_state.dart';

class StopFormBloc extends Bloc<StopFormEvent, StopFormState> {
  final LookupCep lookupCep;
  final SaveStop saveStop;
  final AddressRepository addressRepository;

  /// Quanto tempo parado antes de consultar.
  ///
  /// Uma consulta por tecla gastaria uma dúzia de chamadas num endereço só.
  /// 400ms é o intervalo em que a digitação normal não gera pausa, mas o
  /// usuário ainda não percebe espera.
  final Duration suggestionDebounce;

  Timer? _debounce;

  StopFormBloc({
    required this.lookupCep,
    required this.saveStop,
    required this.addressRepository,
    this.suggestionDebounce = const Duration(milliseconds: 400),
  }) : super(const StopFormState()) {
    on<StopFormStarted>(_onStarted);
    on<CepLookupRequested>(_onCepLookup);
    on<StopLocationPicked>(_onLocationPicked);
    on<AddressTextChanged>(_onAddressTextChanged);
    on<AddressSuggestionsRequested>(_onSuggestionsRequested);
    on<AddressSuggestionSelected>(_onSuggestionSelected);
    on<AddressSuggestionsDismissed>(_onSuggestionsDismissed);
    on<StopFormSubmitted>(_onSubmit);
  }

  @override
  Future<void> close() {
    _debounce?.cancel();
    return super.close();
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

  /// Reinicia a contagem a cada tecla. Só a última pausa vira consulta.
  void _onAddressTextChanged(
    AddressTextChanged event,
    Emitter<StopFormState> emit,
  ) {
    _debounce?.cancel();

    // O texto mudou, então a coordenada da sugestão anterior não descreve mais
    // o que está escrito. Mantê-la salvaria a parada no lugar antigo.
    emit(state.copyWith(clearSuggestedCoordinate: true));

    _debounce = Timer(
      suggestionDebounce,
      () {
        if (!isClosed) add(AddressSuggestionsRequested(event.text));
      },
    );
  }

  Future<void> _onSuggestionsRequested(
    AddressSuggestionsRequested event,
    Emitter<StopFormState> emit,
  ) async {
    emit(state.copyWith(isSuggesting: true));

    final suggestions = await addressRepository.suggest(event.text);
    if (isClosed) return;

    emit(state.copyWith(isSuggesting: false, suggestions: suggestions));
  }

  Future<void> _onSuggestionSelected(
    AddressSuggestionSelected event,
    Emitter<StopFormState> emit,
  ) async {
    // Guarda o endereço com a coordenada que já veio. Salvar a parada depois
    // encontra isso no cache em vez de consultar de novo.
    await addressRepository.rememberSuggestion(event.suggestion);
    if (isClosed) return;

    // A escolha encerra a busca: a lista some e a contagem pendente é
    // cancelada, senão ela dispararia uma consulta pelo texto já resolvido.
    _debounce?.cancel();

    emit(state.copyWith(
      suggestions: const [],
      isSuggesting: false,
      suggestedCoordinate: event.suggestion.point,
    ));
  }

  void _onSuggestionsDismissed(
    AddressSuggestionsDismissed event,
    Emitter<StopFormState> emit,
  ) {
    _debounce?.cancel();
    emit(state.copyWith(suggestions: const [], isSuggesting: false));
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
      // 2. a que veio na sugestão escolhida — já foi paga, seria desperdício
      //    consultar de novo o mesmo endereço;
      // 3. a que a parada já tinha, se o endereço não mudou;
      // 4. nenhuma — aí o repositório geocodifica na hora de salvar.
      coordinate: state.pickedCoordinate ??
          state.suggestedCoordinate ??
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
