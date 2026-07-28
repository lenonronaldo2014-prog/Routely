import 'package:equatable/equatable.dart';

import '../../domain/entities/active_route.dart';

abstract class ActiveRouteState extends Equatable {
  const ActiveRouteState();

  @override
  List<Object?> get props => [];
}

class ActiveRouteInitial extends ActiveRouteState {
  const ActiveRouteInitial();
}

/// Não há rota em andamento.
class ActiveRouteAbsent extends ActiveRouteState {
  const ActiveRouteAbsent();
}

class ActiveRouteLoaded extends ActiveRouteState {
  final ActiveRoute route;

  /// A ordem atual deixou de fazer sentido de onde o entregador está. A tela
  /// sugere recalcular em vez de recalcular sozinha — mudar a ordem das
  /// paradas sem avisar seria desorientador para quem já decorou as próximas.
  final bool suggestRecalculation;

  /// Recálculo em andamento.
  final bool isRecalculating;

  /// Erro de uma ação pontual (recalcular, por exemplo). Fica aqui e não num
  /// estado próprio de falha porque a rota continua válida — trocar a tela
  /// inteira por uma mensagem faria o entregador perder o roteiro de vista.
  final String? actionError;

  /// Confirmação de uma ação bem-sucedida. Existe porque o total da rota
  /// **sobe** depois de recalcular — o número antigo era medido de onde o dia
  /// começou. Sem explicar a economia real, o usuário acha que piorou.
  final String? actionMessage;

  const ActiveRouteLoaded(
    this.route, {
    this.suggestRecalculation = false,
    this.isRecalculating = false,
    this.actionError,
    this.actionMessage,
  });

  ActiveRouteLoaded copyWith({
    ActiveRoute? route,
    bool? suggestRecalculation,
    bool? isRecalculating,
    String? actionError,
    String? actionMessage,
    bool clearActionError = false,
  }) {
    return ActiveRouteLoaded(
      route ?? this.route,
      suggestRecalculation: suggestRecalculation ?? this.suggestRecalculation,
      isRecalculating: isRecalculating ?? this.isRecalculating,
      actionError: clearActionError ? null : (actionError ?? this.actionError),
      actionMessage: actionMessage,
    );
  }

  @override
  List<Object?> get props => [
        route,
        suggestRecalculation,
        isRecalculating,
        actionError,
        actionMessage,
      ];
}

class ActiveRouteFailure extends ActiveRouteState {
  final String message;

  const ActiveRouteFailure(this.message);

  @override
  List<Object?> get props => [message];
}
