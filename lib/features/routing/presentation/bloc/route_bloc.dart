import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/usecases/usecase.dart';
import '../../../location/domain/usecases/get_current_location.dart';
import '../../domain/usecases/calculate_route_options.dart';
import 'route_event.dart';
import 'route_state.dart';

class RouteBloc extends Bloc<RouteEvent, RouteState> {
  final GetCurrentLocation getCurrentLocation;
  final CalculateRouteOptions calculateRouteOptions;

  RouteBloc({
    required this.getCurrentLocation,
    required this.calculateRouteOptions,
  }) : super(const RouteInitial()) {
    on<RouteCalculationRequested>(_onCalculate);
    on<RouteCleared>((_, emit) => emit(const RouteInitial()));
  }

  Future<void> _onCalculate(
    RouteCalculationRequested event,
    Emitter<RouteState> emit,
  ) async {
    emit(const RouteCalculating(RouteCalculationStage.locating));

    final locationResult = await getCurrentLocation(const NoParams());

    final origin = locationResult.fold(
      (failure) {
        emit(RouteFailureState.fromFailure(failure));
        return null;
      },
      (point) => point,
    );

    if (origin == null) return;

    emit(const RouteCalculating(RouteCalculationStage.calculating));

    final result = await calculateRouteOptions(CalculateRouteOptionsParams(
      origin: origin,
      stops: event.stops,
    ));

    result.fold(
      (failure) => emit(RouteFailureState.fromFailure(failure)),
      (plan) => emit(RouteOptionsReady(plan: plan, origin: origin)),
    );
  }
}
