/// As alternativas que o app oferece para o usuário escolher.
///
/// A ideia central do Routely: não existe "a rota ótima". O algoritmo não sabe
/// que o cliente da parada 7 só atende depois das 14h, nem que a rua da parada 3
/// alaga quando chove. Então o app calcula opções com trade-offs explícitos e
/// deixa a decisão com quem está na rua.
enum RouteStrategy {
  /// Menor tempo total de deslocamento.
  fastest,

  /// Menor quilometragem — nem sempre a mais rápida, mas gasta menos
  /// combustível. Para entregador autônomo isso é lucro direto.
  shortest,

  /// Sempre a parada mais próxima primeiro. Matematicamente pior no total,
  /// mas tira entregas da lista rápido — o que ajuda quando o dia está cheio
  /// e o usuário quer ver progresso.
  nearestFirst;

  String get label => switch (this) {
        RouteStrategy.fastest => 'Mais rápida',
        RouteStrategy.shortest => 'Mais econômica',
        RouteStrategy.nearestFirst => 'Mais próxima primeiro',
      };

  String get description => switch (this) {
        RouteStrategy.fastest => 'Menor tempo total no trânsito',
        RouteStrategy.shortest => 'Menor distância, economiza combustível',
        RouteStrategy.nearestFirst => 'Tira entregas da lista mais rápido',
      };
}
