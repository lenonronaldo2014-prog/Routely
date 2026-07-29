import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:routely/core/error/exceptions.dart';
import 'package:routely/core/services/update_checker.dart';

class _CannedClient extends http.BaseClient {
  final String body;
  final int statusCode;

  _CannedClient(this.body, {this.statusCode = 200});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(Stream.value(utf8.encode(body)), statusCode);
}

void main() {
  group('AppVersion.compare', () {
    // O motivo de existir: em ordem alfabética "1.0.10" vem antes de "1.0.9",
    // e o usuário deixaria de ver uma atualização real.
    test('compara por número, não por texto', () {
      expect(AppVersion.compare('1.0.10', '1.0.9'), greaterThan(0));
      expect(AppVersion.compare('1.10.0', '1.9.0'), greaterThan(0));
      expect(AppVersion.compare('2.0.0', '10.0.0'), lessThan(0));
    });

    test('versões iguais dão zero', () {
      expect(AppVersion.compare('1.0.4', '1.0.4'), 0);
    });

    test('ignora o v das tags do Git', () {
      expect(AppVersion.compare('v1.0.4', '1.0.4'), 0);
      expect(AppVersion.compare('V1.0.5', 'v1.0.4'), greaterThan(0));
    });

    // "1.1" e "1.1.0" são a mesma versão.
    test('o que falta conta como zero', () {
      expect(AppVersion.compare('1.1', '1.1.0'), 0);
      expect(AppVersion.compare('1.1', '1.1.1'), lessThan(0));
    });

    test('ignora build e sufixo', () {
      expect(AppVersion.compare('1.0.4+5', '1.0.4'), 0);
      expect(AppVersion.compare('1.0.4-beta', '1.0.4'), 0);
    });

    test('lixo no meio não quebra a comparação', () {
      expect(AppVersion.compare('1.x.4', '1.0.4'), 0);
      expect(AppVersion.compare('', '1.0.0'), lessThan(0));
    });
  });

  group('GitHubUpdateChecker', () {
    const releaseBody = '''
{"tag_name":"v1.0.5",
 "html_url":"https://github.com/lenonronaldo2014-prog/Routely/releases/tag/v1.0.5"}
''';

    test('versão nova é anunciada com a página de download', () async {
      final result = await GitHubUpdateChecker(client: _CannedClient(releaseBody))
          .check('1.0.4');

      expect(result.hasUpdate, isTrue);
      expect(result.latest, '1.0.5');
      expect(result.pageUrl, endsWith('/releases/tag/v1.0.5'));
    });

    test('mesma versão não anuncia nada', () async {
      final result = await GitHubUpdateChecker(client: _CannedClient(releaseBody))
          .check('1.0.5');

      expect(result.hasUpdate, isFalse);
    });

    // Quem compila do repositório pode estar à frente da última release.
    // Anunciar "atualize" nesse caso seria mandar o usuário voltar no tempo.
    test('versão instalada mais nova não anuncia atualização', () async {
      final result = await GitHubUpdateChecker(client: _CannedClient(releaseBody))
          .check('1.1.0');

      expect(result.hasUpdate, isFalse);
    });

    test('sem release publicada vira erro, não falso positivo', () async {
      final checker = GitHubUpdateChecker(client: _CannedClient('{}'));

      expect(() => checker.check('1.0.4'), throwsA(isA<ServerException>()));
    });

    test('resposta de erro do GitHub vira exceção', () async {
      final checker = GitHubUpdateChecker(
        client: _CannedClient('{"message":"rate limit"}', statusCode: 403),
      );

      expect(() => checker.check('1.0.4'), throwsA(isA<ServerException>()));
    });
  });
}
