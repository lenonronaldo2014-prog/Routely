import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../../domain/usecases/clear_completed_stops.dart';
import '../../domain/usecases/delete_stop.dart';
import '../../domain/usecases/get_stops.dart';
import '../../domain/usecases/resolve_pending_coordinates.dart';
import '../../domain/usecases/save_stop.dart';
import '../../domain/usecases/set_stop_status.dart';
import 'stops_event.dart';
import 'stops_state.dart';

class StopsBloc extends Bloc<StopsEvent, StopsState> {
  final GetStops getStops;
  final DeleteStop deleteStop;
  final SetStopStatus setStopStatus;
  final ClearCompletedStops clearCompletedStops;
  final ResolvePendingCoordinates resolvePendingCoordinates;
  final SaveStop saveStop;

  StopsBloc({
    required this.getStops,
    required this.deleteStop,
    required this.setStopStatus,
    required this.clearCompletedStops,
    required this.resolvePendingCoordinates,
    required this.saveStop,
  }) : super(const StopsInitial()) {
    on<StopsLoadRequested>(_onLoad);
    on<StopSaveRequested>(_onSaved);
    on<StopDeleteRequested>(_onDelete);
    on<StopStatusChangeRequested>(_onStatusChange);
    on<StopLocationUpdateRequested>(_onLocationUpdate);
    on<CompletedStopsClearRequested>(_onClearCompleted);
    on<PendingCoordinatesResolveRequested>(_onResolveCoordinates);
  }

  Future<void> _onLoad(
    StopsLoadRequested event,
    Emitter<StopsState> emit,
  ) async {
    emit(const StopsLoading());

    final result = await getStops(const NoParams());
    result.fold(
      (failure) => emit(StopsFailure(_mapFailureToMessage(failure))),
      (stops) => emit(StopsLoaded(stops)),
    );
  }

  /// A parada já foi persistida pelo formulário; aqui só recarregamos a lista.
  Future<void> _onSaved(
    StopSaveRequested event,
    Emitter<StopsState> emit,
  ) async {
    await _reload(emit);
  }

  Future<void> _onDelete(
    StopDeleteRequested event,
    Emitter<StopsState> emit,
  ) async {
    final current = _currentLoaded();
    if (current == null) return;

    // Remove da lista na hora: apagar é local e instantâneo, esperar o disco
    // só faria a UI parecer travada.
    emit(StopsLoaded(
      current.stops.where((s) => s.id != event.id).toList(),
    ));

    final result = await deleteStop(DeleteStopParams(event.id));
    if (result.isLeft()) {
      emit(current);
      emit(StopsFailure(_mapFailureToMessage(
        result.fold((f) => f, (_) => CacheFailure()),
      )));
    }
  }

  Future<void> _onStatusChange(
    StopStatusChangeRequested event,
    Emitter<StopsState> emit,
  ) async {
    final current = _currentLoaded();
    if (current == null) return;

    final result = await setStopStatus(SetStopStatusParams(
      stop: event.stop,
      status: event.status,
    ));

    result.fold(
      (failure) => emit(StopsFailure(_mapFailureToMessage(failure))),
      (updated) => emit(StopsLoaded(
        current.stops.map((s) => s.id == updated.id ? updated : s).toList(),
      )),
    );
  }

  Future<void> _onLocationUpdate(
    StopLocationUpdateRequested event,
    Emitter<StopsState> emit,
  ) async {
    final current = _currentLoaded();
    if (current == null) return;

    final updated = event.stop.copyWith(coordinate: event.coordinate);

    final result = await saveStop(SaveStopParams(updated));

    result.fold(
      (failure) => emit(StopsFailure(_mapFailureToMessage(failure))),
      (saved) => emit(StopsLoaded(
        current.stops.map((s) => s.id == saved.id ? saved : s).toList(),
      )),
    );
  }

  Future<void> _onClearCompleted(
    CompletedStopsClearRequested event,
    Emitter<StopsState> emit,
  ) async {
    final current = _currentLoaded();
    if (current == null) return;

    emit(current.copyWith(isBusy: true));

    final result = await clearCompletedStops(const NoParams());
    await result.fold(
      (failure) async => emit(StopsFailure(_mapFailureToMessage(failure))),
      (_) async => _reload(emit),
    );
  }

  Future<void> _onResolveCoordinates(
    PendingCoordinatesResolveRequested event,
    Emitter<StopsState> emit,
  ) async {
    final current = _currentLoaded();
    if (current == null) return;

    if (current.unresolved.isEmpty) {
      await _reload(emit);
      return;
    }

    emit(current.copyWith(isBusy: true));

    final result = await resolvePendingCoordinates(const NoParams());
    result.fold(
      (failure) => emit(StopsFailure(_mapFailureToMessage(failure))),
      (stops) => emit(StopsLoaded(stops)),
    );
  }

  Future<void> _reload(Emitter<StopsState> emit) async {
    final result = await getStops(const NoParams());
    result.fold(
      (failure) => emit(StopsFailure(_mapFailureToMessage(failure))),
      (stops) => emit(StopsLoaded(stops)),
    );
  }

  StopsLoaded? _currentLoaded() {
    final s = state;
    return s is StopsLoaded ? s : null;
  }

  String _mapFailureToMessage(Failure failure) {
    if (failure is CacheFailure) {
      return 'Não foi possível acessar os dados salvos no aparelho.';
    }
    if (failure is ConnectionFailure) return 'Sem conexão.';
    return 'Erro inesperado. Tente novamente.';
  }
}
