import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/responsive_body.dart';
import '../../../../injection_container.dart';
import '../../domain/entities/scanned_address.dart';
import '../../domain/repositories/label_scanner_repository.dart';

/// Captura a etiqueta da encomenda e devolve o que foi lido.
///
/// Devolve um [ScannedAddress] pelo `pop` — nunca salva sozinha. O resultado
/// vai para o formulário, onde o usuário confere antes de gravar: OCR errado
/// que vira entrega errada destrói a confiança no app, e conferir custa um
/// segundo.
class ScanLabelPage extends StatefulWidget {
  const ScanLabelPage({super.key});

  @override
  State<ScanLabelPage> createState() => _ScanLabelPageState();
}

class _ScanLabelPageState extends State<ScanLabelPage>
    with WidgetsBindingObserver {
  CameraController? _controller;
  bool _isProcessing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setUpCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    // Sem isso a câmera fica segurando o hardware em background e volta preta.
    if (state == AppLifecycleState.inactive) {
      controller.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed) {
      _setUpCamera();
    }
  }

  Future<void> _setUpCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _error = 'Nenhuma câmera disponível.');
        return;
      }

      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        back,
        // Alta o suficiente para texto pequeno de etiqueta ficar legível, sem
        // gerar um arquivo enorme que atrasa o reconhecimento.
        ResolutionPreset.high,
        enableAudio: false,
      );

      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Não consegui abrir a câmera. '
            'Confira a permissão nas configurações do app.');
      }
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (_isProcessing) return;

    setState(() => _isProcessing = true);

    try {
      final photo = await controller.takePicture();
      final result = await sl<LabelScannerRepository>().scanLabel(photo.path);
      if (!mounted) return;

      result.fold(
        (failure) {
          setState(() => _isProcessing = false);
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(
              duration: const Duration(seconds: 4),
              content: Text(
                failure is ScanFailure && failure.message.isNotEmpty
                    ? failure.message
                    : 'Não consegui ler a etiqueta.',
              ),
            ));
        },
        (scanned) => Navigator.of(context).pop(scanned),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('Não consegui tirar a foto. Tente de novo.'),
        ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        // O `titleTextStyle` do tema traz a cor do texto do tema ativo, e
        // `foregroundColor` não sobrescreve isso. Sem esta linha, no modo
        // claro o título fica escuro sobre a barra preta e some.
        titleTextStyle: Theme.of(context)
            .appBarTheme
            .titleTextStyle
            ?.copyWith(color: Colors.white),
        title: const Text('Escanear etiqueta'),
      ),
      body: _error != null
          ? _ErrorView(message: _error!)
          : _controller == null
              ? const Center(child: CircularProgressIndicator())
              : _CameraView(
                  controller: _controller!,
                  isProcessing: _isProcessing,
                ),
      bottomNavigationBar: _error != null
          ? null
          : Container(
              color: Colors.black,
              child: ResponsiveActionBar(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _isProcessing
                          ? 'Lendo a etiqueta…'
                          : 'Enquadre só a etiqueta, sem sombra em cima',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    ElevatedButton.icon(
                      onPressed: _isProcessing ? null : _capture,
                      icon: _isProcessing
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.document_scanner_rounded),
                      label: Text(_isProcessing ? 'Lendo…' : 'Ler etiqueta'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _CameraView extends StatelessWidget {
  final CameraController controller;
  final bool isProcessing;

  const _CameraView({required this.controller, required this.isProcessing});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(child: CameraPreview(controller)),

        // Moldura de enquadramento. Ajuda o usuário a chegar perto o
        // suficiente — foto de longe é a causa mais comum de leitura ruim.
        const IgnorePointer(child: _FramingGuide()),

        if (isProcessing)
          ColoredBox(color: Colors.black.withValues(alpha: 0.45)),
      ],
    );
  }
}

class _FramingGuide extends StatelessWidget {
  const _FramingGuide();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FractionallySizedBox(
        widthFactor: 0.88,
        heightFactor: 0.55,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white70, width: 2),
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;

  const _ErrorView({required this.message});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Center(
      child: ResponsiveBody(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.no_photography_outlined, size: 52, color: c.warning),
            const SizedBox(height: AppSpacing.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                height: 1.4,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
              child: const Text('Voltar'),
            ),
          ],
        ),
      ),
    );
  }
}
