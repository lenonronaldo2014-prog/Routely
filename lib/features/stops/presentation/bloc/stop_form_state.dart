import 'package:equatable/equatable.dart';

import '../../../../core/geo/geo_point.dart';
import '../../domain/entities/address_lookup.dart';
import '../../domain/entities/address_suggestion.dart';
import '../../domain/entities/delivery_stop.dart';

enum StopFormStatus { editing, saving, saved }

/// Estado único com flags, em vez de várias classes de estado. Formulário tem
/// muitos pedaços independentes acontecendo ao mesmo tempo (busca de CEP
/// rodando enquanto o usuário digita outro campo), e classes separadas
/// obrigariam a recriar o estado inteiro a cada mudancinha.
class StopFormState extends Equatable {
  final StopFormStatus status;

  /// Preenchido quando o formulário abre em modo de edição.
  final DeliveryStop? existing;

  final bool isLookingUpCep;

  /// Resultado do CEP, para a UI preencher rua/bairro/cidade/UF.
  final AddressLookup? cepResult;

  final String? cepError;
  final String? saveError;

  /// A parada foi salva sem coordenada — normalmente por falta de rede.
  /// A UI avisa que ela não entra na rota até ser resolvida.
  final bool savedWithoutCoordinate;

  /// Ponto marcado à mão no mapa. Quando existe, substitui o geocoding.
  final GeoPoint? pickedCoordinate;

  /// Opções do autocomplete para o que está digitado no campo de rua.
  final List<AddressSuggestion> suggestions;

  final bool isSuggesting;

  /// Coordenada que veio junto da sugestão escolhida.
  ///
  /// Guardada separada do pino manual porque tem validade diferente: assim que
  /// o usuário edita a rua de novo, ela deixa de valer — o texto não descreve
  /// mais o lugar que o serviço devolveu. O pino manual não se invalida assim,
  /// porque foi o usuário olhando para a porta.
  final GeoPoint? suggestedCoordinate;

  const StopFormState({
    this.status = StopFormStatus.editing,
    this.existing,
    this.isLookingUpCep = false,
    this.cepResult,
    this.cepError,
    this.saveError,
    this.savedWithoutCoordinate = false,
    this.pickedCoordinate,
    this.suggestions = const [],
    this.isSuggesting = false,
    this.suggestedCoordinate,
  });

  /// Coordenada que a tela deve mostrar, do mais confiável para o menos: o pino
  /// marcado à mão, a sugestão escolhida, e por fim a que a parada já tinha.
  GeoPoint? get effectiveCoordinate =>
      pickedCoordinate ?? suggestedCoordinate ?? existing?.coordinate;

  bool get hasCoordinate => effectiveCoordinate?.isValid ?? false;

  StopFormState copyWith({
    StopFormStatus? status,
    DeliveryStop? existing,
    bool? isLookingUpCep,
    AddressLookup? cepResult,
    String? cepError,
    String? saveError,
    bool? savedWithoutCoordinate,
    GeoPoint? pickedCoordinate,
    List<AddressSuggestion>? suggestions,
    bool? isSuggesting,
    GeoPoint? suggestedCoordinate,
    bool clearCepError = false,
    bool clearSaveError = false,
    bool clearCepResult = false,
    bool clearSuggestedCoordinate = false,
  }) {
    return StopFormState(
      status: status ?? this.status,
      existing: existing ?? this.existing,
      isLookingUpCep: isLookingUpCep ?? this.isLookingUpCep,
      cepResult: clearCepResult ? null : (cepResult ?? this.cepResult),
      cepError: clearCepError ? null : (cepError ?? this.cepError),
      saveError: clearSaveError ? null : (saveError ?? this.saveError),
      savedWithoutCoordinate:
          savedWithoutCoordinate ?? this.savedWithoutCoordinate,
      pickedCoordinate: pickedCoordinate ?? this.pickedCoordinate,
      suggestions: suggestions ?? this.suggestions,
      isSuggesting: isSuggesting ?? this.isSuggesting,
      suggestedCoordinate: clearSuggestedCoordinate
          ? null
          : (suggestedCoordinate ?? this.suggestedCoordinate),
    );
  }

  @override
  List<Object?> get props => [
        status,
        existing,
        isLookingUpCep,
        cepResult,
        cepError,
        saveError,
        savedWithoutCoordinate,
        pickedCoordinate,
        suggestions,
        isSuggesting,
        suggestedCoordinate,
      ];
}
