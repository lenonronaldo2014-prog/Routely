/// Limites por plano.
///
/// O limite não é técnico — o otimizador aguenta 150 paradas. É de produto: o
/// plano gratuito entrega valor real (um roteiro de 8 paradas resolve o dia da
/// maioria dos entregadores autônomos) e o pago remove o teto.
///
/// Importante: o usuário **nunca** é impedido de cadastrar endereços. O limite
/// vale só para quantas entram numa rota por vez. Cadastrou 20? Cadastrou. O
/// app roteiriza as 8 mais próximas, e as outras esperam o próximo grupo.
/// Bloquear o cadastro faria o app parecer quebrado; adiar é honesto e ainda
/// resolve o problema.
enum PlanTier {
  free,
  pro;

  int get maxStopsPerRoute => switch (this) {
        PlanTier.free => 8,
        // Teto do refinamento 2-opt. Acima disso o cálculo sai da thread de UI.
        PlanTier.pro => 150,
      };

  String get label => switch (this) {
        PlanTier.free => 'Gratuito',
        PlanTier.pro => 'Pro',
      };
}
