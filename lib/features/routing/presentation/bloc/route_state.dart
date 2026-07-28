import 'package:equatable/equatable.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/geo/geo_point.dart';
import '../../domain/entities/route_option.dart';
import '../../domain/entities/route_plan.dart';

abstract class RouteState extends Equatable {
  const RouteState();

  @override
  List<Object?> get props => [];
}

class RouteInitial extends RouteState {
  const RouteInitial();
}

/// Duas etapas visíveis para o usuário: primeiro o GPS, depois o cálculo.
/// Separar deixa claro onde está demorando quando o GPS custa a fixar.
enum RouteCalculationStage { locating, calculating }

class RouteCalculating extends RouteState {
  final RouteCalculationStage stage;

  const RouteCalculating(this.stage);

  @override
  List<Object?> get props => [stage];
}

class RouteOptionsReady extends RouteState {
  final RoutePlan plan;
  final GeoPoint origin;

  const RouteOptionsReady({required this.plan, required this.origin});

  List<RouteOption> get options => plan.options;

  bool get isEstimate => options.isNotEmpty && options.first.isEstimate;

  @override
  List<Object?> get props => [plan, origin];
}

class RouteFailureState extends RouteState {
  final String message;

  /// Permissão negada de vez precisa levar o usuário às configurações do
  /// sistema — não adianta oferecer "tentar de novo".
  final bool needsSettings;

  const RouteFailureState(this.message, {this.needsSettings = false});

  factory RouteFailureState.fromFailure(Failure failure) {
    if (failure is LocationFailure) {
      return switch (failure.reason) {
        LocationFailureReason.serviceDisabled => const RouteFailureState(
            'Ative o GPS do aparelho para calcular a rota.',
          ),
        LocationFailureReason.permissionDenied => const RouteFailureState(
            'O Routely precisa da sua localização para saber de onde você está saindo.',
          ),
        LocationFailureReason.permissionDeniedForever => const RouteFailureState(
            'A permissão de localização foi negada. Libere nas configurações do app.',
            needsSettings: true,
          ),
        LocationFailureReason.timeout => const RouteFailureState(
            'Não consegui pegar sua localização. Vá para um lugar mais aberto e tente de novo.',
          ),
        LocationFailureReason.unknown => const RouteFailureState(
            'Erro ao obter sua localização.',
          ),
      };
    }

    if (failure is EmptyRouteFailure) {
      return const RouteFailureState(
        'Nenhuma entrega com endereço localizado no mapa.',
      );
    }

    return const RouteFailureState('Não foi possível calcular a rota.');
  }

  @override
  List<Object?> get props => [message, needsSettings];
}
