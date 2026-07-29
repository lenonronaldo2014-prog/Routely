import 'dart:convert';

import 'package:http/http.dart' as http;

import '../error/exceptions.dart';

/// O que a checagem descobriu.
class UpdateCheck {
  /// Versão instalada, como está no `pubspec.yaml`.
  final String current;

  /// Última versão publicada no GitHub.
  final String latest;

  /// Página da release, para o usuário baixar.
  final String pageUrl;

  const UpdateCheck({
    required this.current,
    required this.latest,
    required this.pageUrl,
  });

  bool get hasUpdate => AppVersion.compare(latest, current) > 0;
}

/// Compara versões no formato `1.2.3`.
///
/// Existe porque comparar como texto erra feio: `"1.0.10" < "1.0.9"` é
/// verdadeiro na ordem alfabética, e o usuário deixaria de ver uma
/// atualização real.
class AppVersion {
  const AppVersion._();

  /// Negativo se [a] é anterior a [b], zero se iguais, positivo se posterior.
  ///
  /// Tolera o `v` do começo das tags do Git e sufixos como `1.0.4+5` ou
  /// `1.0.4-beta`, que não participam da comparação.
  static int compare(String a, String b) {
    final left = _parts(a);
    final right = _parts(b);
    final length = left.length > right.length ? left.length : right.length;

    for (var i = 0; i < length; i++) {
      // "1.1" e "1.1.0" são a mesma versão: o que falta conta como zero.
      final l = i < left.length ? left[i] : 0;
      final r = i < right.length ? right[i] : 0;
      if (l != r) return l - r;
    }
    return 0;
  }

  static List<int> _parts(String version) {
    final core = version.trim().replaceFirst(RegExp(r'^[vV]'), '').split(
      RegExp(r'[+\-]'),
    ).first;

    return core
        .split('.')
        .map((part) => int.tryParse(part) ?? 0)
        .toList(growable: false);
  }
}

/// Pergunta ao GitHub qual é a última release publicada.
///
/// O app é distribuído por lá, não pela Play Store, então esta é a única forma
/// de o usuário saber que existe versão nova. Um entregador não fica olhando
/// repositório — sem isso ele rodaria meses com uma versão com bug já
/// corrigido.
///
/// A verificação é **manual**, por botão. Checar sozinho ao abrir gastaria
/// rede de quem trabalha com dados limitados para responder algo que quase
/// sempre é "está atualizado".
abstract class UpdateChecker {
  Future<UpdateCheck> check(String currentVersion);
}

class GitHubUpdateChecker implements UpdateChecker {
  /// A API pública do GitHub, sem autenticação: 60 consultas por hora por IP.
  /// Sobra para um botão que o usuário aperta de vez em quando.
  static const _endpoint =
      'https://api.github.com/repos/lenonronaldo2014-prog/Routely/releases/latest';

  static const _timeout = Duration(seconds: 12);

  final http.Client client;

  GitHubUpdateChecker({required this.client});

  @override
  Future<UpdateCheck> check(String currentVersion) async {
    final response = await client.get(
      Uri.parse(_endpoint),
      headers: const {'Accept': 'application/vnd.github+json'},
    ).timeout(_timeout);

    if (response.statusCode != 200) {
      throw ServerException(statusCode: response.statusCode);
    }

    final body = json.decode(utf8.decode(response.bodyBytes));
    if (body is! Map<String, dynamic>) {
      throw ServerException(statusCode: response.statusCode);
    }

    final tag = body['tag_name'] as String?;
    if (tag == null || tag.trim().isEmpty) {
      throw ServerException(statusCode: response.statusCode);
    }

    return UpdateCheck(
      current: currentVersion,
      latest: tag.replaceFirst(RegExp(r'^[vV]'), ''),
      pageUrl: (body['html_url'] as String?) ??
          'https://github.com/lenonronaldo2014-prog/Routely/releases/latest',
    );
  }
}
