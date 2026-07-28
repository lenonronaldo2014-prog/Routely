import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../../../core/error/exceptions.dart';

abstract class LabelScannerDataSource {
  /// Lê o texto de uma imagem salva em disco.
  Future<String> recognizeText(String imagePath);

  Future<void> dispose();
}

class LabelScannerDataSourceImpl implements LabelScannerDataSource {
  /// Reconhecimento no próprio aparelho: sem chave de API, sem custo por
  /// leitura, sem enviar foto de etiqueta (que tem nome e endereço de cliente)
  /// para servidor nenhum. Também funciona sem sinal, que é onde o entregador
  /// costuma estar.
  final TextRecognizer _recognizer =
      TextRecognizer(script: TextRecognitionScript.latin);

  @override
  Future<String> recognizeText(String imagePath) async {
    try {
      final input = InputImage.fromFilePath(imagePath);
      final result = await _recognizer.processImage(input);

      // Uma linha por linha reconhecida. O parser trabalha em cima disso, e
      // manter a quebra é o que permite ancorar nos rótulos da etiqueta.
      return result.blocks
          .expand((block) => block.lines)
          .map((line) => line.text)
          .join('\n');
    } catch (e) {
      throw ScanException(e.toString());
    }
  }

  @override
  Future<void> dispose() => _recognizer.close();
}
