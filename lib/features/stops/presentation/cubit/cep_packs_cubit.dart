import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/error/failures.dart';
import '../../domain/entities/cep_pack.dart';
import '../../domain/repositories/cep_directory_repository.dart';

/// Cubit em vez de Bloc porque esta tela não tem coordenação entre eventos —
/// são quatro ações diretas sobre uma lista. O resto do app usa Bloc onde há
/// fluxo de eventos de verdade.
class CepPacksCubit extends Cubit<CepPacksState> {
  final CepDirectoryRepository repository;

  CepPacksCubit(this.repository) : super(const CepPacksState());

  Future<void> load() async {
    emit(state.copyWith(isLoading: true, clearError: true));

    final result = await repository.installedPacks();
    result.fold(
      (failure) => emit(state.copyWith(
        isLoading: false,
        error: _mapFailure(failure),
      )),
      (packs) => emit(state.copyWith(isLoading: false, packs: packs)),
    );
  }

  Future<void> import({required String state_, required File file}) async {
    emit(state.copyWith(
      importingState: state_,
      importedCount: 0,
      clearError: true,
    ));

    final result = await repository.importFromFile(
      state: state_,
      file: file,
      onProgress: (progress) {
        if (isClosed) return;
        emit(state.copyWith(importedCount: progress.processed));
      },
    );

    if (isClosed) return;

    await result.fold(
      (failure) async => emit(state.copyWith(
        clearImporting: true,
        error: _mapFailure(failure),
      )),
      (count) async {
        emit(state.copyWith(clearImporting: true, lastImported: count));
        await load();
      },
    );
  }

  Future<void> remove(String uf) async {
    final result = await repository.removePack(uf);
    await result.fold(
      (failure) async => emit(state.copyWith(error: _mapFailure(failure))),
      (_) async => load(),
    );
  }

  String _mapFailure(Failure failure) {
    if (failure is GeocodingFailure) return failure.message;
    if (failure is CacheFailure) return 'Erro ao acessar os dados do aparelho.';
    return 'Não foi possível concluir. Tente novamente.';
  }
}

class CepPacksState extends Equatable {
  final List<CepPack> packs;
  final bool isLoading;

  /// UF sendo importada agora, ou null.
  final String? importingState;

  /// Linhas já gravadas na importação em curso.
  final int importedCount;

  /// Total da última importação concluída, para o aviso de sucesso.
  final int? lastImported;

  final String? error;

  const CepPacksState({
    this.packs = const [],
    this.isLoading = false,
    this.importingState,
    this.importedCount = 0,
    this.lastImported,
    this.error,
  });

  bool get isImporting => importingState != null;

  CepPacksState copyWith({
    List<CepPack>? packs,
    bool? isLoading,
    String? importingState,
    int? importedCount,
    int? lastImported,
    String? error,
    bool clearImporting = false,
    bool clearError = false,
  }) {
    return CepPacksState(
      packs: packs ?? this.packs,
      isLoading: isLoading ?? this.isLoading,
      importingState:
          clearImporting ? null : (importingState ?? this.importingState),
      importedCount: importedCount ?? this.importedCount,
      lastImported: lastImported ?? this.lastImported,
      error: clearError ? null : (error ?? this.error),
    );
  }

  @override
  List<Object?> get props => [
        packs,
        isLoading,
        importingState,
        importedCount,
        lastImported,
        error,
      ];
}
