import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/delivery_record.dart';
import '../../domain/repositories/history_repository.dart';

class HistoryCubit extends Cubit<HistoryState> {
  final HistoryRepository repository;

  HistoryCubit(this.repository) : super(const HistoryState());

  Future<void> load() async {
    emit(state.copyWith(isLoading: true, clearError: true));

    final result = await repository.getHistory();
    result.fold(
      (_) => emit(state.copyWith(
        isLoading: false,
        error: 'Não foi possível carregar o histórico.',
      )),
      (days) => emit(state.copyWith(isLoading: false, days: days)),
    );
  }

  Future<void> clear() async {
    final result = await repository.clearHistory();
    await result.fold(
      (_) async => emit(state.copyWith(
        error: 'Não foi possível limpar o histórico.',
      )),
      (_) async => load(),
    );
  }
}

class HistoryState extends Equatable {
  final List<DeliveryDay> days;
  final bool isLoading;
  final String? error;

  const HistoryState({
    this.days = const [],
    this.isLoading = false,
    this.error,
  });

  bool get isEmpty => days.isEmpty;

  int get totalDelivered =>
      days.fold(0, (sum, day) => sum + day.delivered);

  double get totalDistanceMeters =>
      days.fold(0.0, (sum, day) => sum + day.distanceMeters);

  HistoryState copyWith({
    List<DeliveryDay>? days,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return HistoryState(
      days: days ?? this.days,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }

  @override
  List<Object?> get props => [days, isLoading, error];
}
