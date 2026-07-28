import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../location/domain/usecases/get_current_location.dart';
import '../../domain/entities/route_option.dart';
import '../../domain/usecases/finish_route.dart';
import '../../domain/usecases/get_active_route.dart';
import '../../domain/usecases/recalculate_route.dart';
import '../../domain/usecases/start_route.dart';
import 'active_route_event.dart';
import 'active_route_state.dart';

class ActiveRouteBloc extends Bloc<ActiveRouteEvent, ActiveRouteState> {
  final GetActiveRoute getActiveRoute;
  final StartRoute startRoute;
  final FinishRoute finishRoute;
  final RecalculateRoute recalculateRoute;
  final GetCurrentLocation getCurrentLocation;

  ActiveRouteBloc({
    required this.getActiveRoute,
    required this.startRoute,
    required this.finishRoute,
    required this.recalculateRoute,
    required this.getCurrentLocation,
  }) : super(const ActiveRouteInitial()) {
    on<ActiveRouteLoadRequested>(_onLoad);
    on<ActiveRouteStartRequested>(_onStart);
    on<ActiveRouteRecalculateRequested>(_onRecalculate);
    on<ActiveRouteDriftCheckRequested>(_onDriftCheck);
    on<ActiveRouteFinishRequested>(_onFinish);
  }

  Future<void> _onLoad(
    ActiveRouteLoadRequested event,
    Emitter<ActiveRouteState> emit,
  ) async {
    final result = await getActiveRoute(const NoParams());

    result.fold(
      (failure) => emit(ActiveRouteFailure(_mapFailure(failure))),
      (route) => emit(
        route == null
            ? const ActiveRouteAbsent()
            // A sugestão anterior não sobrevive a um recarregamento: as
            // paradas mudaram e a conta precisa ser refeita.
            : ActiveRouteLoaded(route),
      ),
    );
  }

  Future<void> _onStart(
    ActiveRouteStartRequested event,
    Emitter<ActiveRouteState> emit,
  ) async {
    final result = await startRoute(StartRouteParams(
      option: event.option,
      origin: event.origin,
    ));

    result.fold(
      (failure) => emit(ActiveRouteFailure(_mapFailure(failure))),
      (route) => emit(ActiveRouteLoaded(route)),
    );
  }

  Future<void> _onRecalculate(
    ActiveRouteRecalculateRequested event,
    Emitter<ActiveRouteState> emit,
  ) async {
    final current = _currentLoaded();
    if (current == null) return;

    emit(current.copyWith(isRecalculating: true, clearActionError: true));

    final locationResult = await getCurrentLocation(const NoParams());
    final origin = locationResult.fold((_) => null, (point) => point);

    if (origin == null) {
      emit(current.copyWith(
        isRecalculating: false,
        actionError: 'Não consegui pegar sua localização para recalcular.',
      ));
      return;
    }

    final result = await recalculateRoute(RecalculateRouteParams(
      route: current.route,
      origin: origin,
    ));

    result.fold(
      (failure) => emit(current.copyWith(
        isRecalculating: false,
        actionError: _mapFailure(failure),
      )),
      // Recalculou: a sugestão perde o sentido, a ordem agora é a certa.
      (recalculation) => emit(ActiveRouteLoaded(
        recalculation.route,
        actionMessage: recalculation.hasMeaningfulGain
            ? 'Rota atualizada — '
                '${RouteOption.formatDistance(recalculation.savedDistanceMeters)} '
                'a menos do que seguindo a ordem anterior.'
            : 'Rota atualizada. A ordem anterior já era boa daqui.',
      )),
    );
  }

  /// Checagem silenciosa: nada de spinner nem de erro na tela. Se falhar,
  /// simplesmente não sugere — é uma dica, não uma função essencial.
  Future<void> _onDriftCheck(
    ActiveRouteDriftCheckRequested event,
    Emitter<ActiveRouteState> emit,
  ) async {
    final current = _currentLoaded();
    if (current == null || current.route.remainingLegs.length < 2) return;

    final locationResult = await getCurrentLocation(const NoParams());
    final origin = locationResult.fold((_) => null, (point) => point);
    if (origin == null) return;

    final shouldSuggest = current.route.wouldBenefitFromRecalculation(origin);
    if (!shouldSuggest) return;

    final latest = _currentLoaded();
    if (latest == null) return;

    emit(latest.copyWith(suggestRecalculation: true));
  }

  Future<void> _onFinish(
    ActiveRouteFinishRequested event,
    Emitter<ActiveRouteState> emit,
  ) async {
    final result = await finishRoute(const NoParams());

    result.fold(
      (failure) => emit(ActiveRouteFailure(_mapFailure(failure))),
      (_) => emit(const ActiveRouteAbsent()),
    );
  }

  ActiveRouteLoaded? _currentLoaded() {
    final s = state;
    return s is ActiveRouteLoaded ? s : null;
  }

  String _mapFailure(Failure failure) {
    if (failure is CacheFailure) {
      return 'Não foi possível acessar a rota salva no aparelho.';
    }
    if (failure is EmptyRouteFailure) {
      return 'Não sobrou nenhuma entrega com localização para recalcular.';
    }
    return 'Erro inesperado com a rota.';
  }
}
