/// Configuração que vem de fora do código.
///
/// A chave do Geoapify não pode ficar versionada. Ela entra na compilação por
/// `--dart-define-from-file=geoapify.json`, arquivo que está no `.gitignore`.
///
/// Vale ser honesto sobre o limite disso: qualquer chave embarcada num APK
/// pode ser extraída por quem descompactar o arquivo. O que o `.gitignore`
/// resolve é a chave não ficar pública no repositório — que é o vazamento
/// fácil e permanente. Contra extração do APK a defesa real é a cota e o
/// alerta de uso no painel do Geoapify, não o segredo.
class AppConfig {
  const AppConfig._();

  static const geoapifyKey = String.fromEnvironment('GEOAPIFY_KEY');

  /// Servidor próprio na frente do Geoapify. Vazio significa falar direto com
  /// o Geoapify, usando a chave embarcada.
  ///
  /// Existe para a mudança ser de configuração, e não de código, no dia em que
  /// fizer sentido esconder a chave. Hoje não faz: o plano gratuito do
  /// Geoapify não cobra excedente, ele só para de responder — então uma chave
  /// extraída do APK causa indisponibilidade, não conta a pagar. E o app cai
  /// no Nominatim quando isso acontece. Um servidor agora seria mais uma coisa
  /// para manter e pagar, contra a decisão de custo zero.
  ///
  /// Quando o proxy existir, ele guarda a chave e o app não manda nenhuma.
  static const geoapifyProxy = String.fromEnvironment('GEOAPIFY_PROXY');

  static bool get usesGeoapifyProxy => geoapifyProxy.isNotEmpty;

  /// Sem chave e sem proxy o app continua funcionando pelo Nominatim. Isso não
  /// é só conveniência de desenvolvimento: é o que garante que um build sem a
  /// chave (um clone do repositório, por exemplo) não vire um app quebrado.
  static bool get hasGeoapify => geoapifyKey.isNotEmpty || usesGeoapifyProxy;

  /// Teto de chamadas por dia. O plano gratuito do Geoapify dá 3000; o corte
  /// vem antes de propósito, para o app cair no plano B antes de o provedor
  /// começar a recusar — usuário não deveria descobrir o limite através de um
  /// erro.
  static const geoapifyDailyBudget = 2700;
}
