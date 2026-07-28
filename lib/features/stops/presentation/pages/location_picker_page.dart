import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/geo/geo_point.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../../core/widgets/responsive_body.dart';
import '../../../../injection_container.dart';
import '../../../location/domain/usecases/get_current_location.dart';

/// Ajuste manual da localização de uma entrega.
///
/// Existe porque geocoding erra — e erra **com internet**. Num teste com 4
/// endereços reais de São Paulo, um não foi encontrado. Como o fluxo do app é
/// "cadastra de manhã com sinal, roda o dia sem", um endereço que falha vira
/// buraco no roteiro inteiro. Aqui o usuário resolve em dois toques, de graça e
/// sem depender de serviço nenhum.
class LocationPickerPage extends StatefulWidget {
  /// Coordenada atual da parada, se já tiver uma.
  final GeoPoint? initial;

  /// Endereço mostrado no topo, para o usuário saber o que está posicionando.
  final String addressLabel;

  const LocationPickerPage({
    super.key,
    this.initial,
    required this.addressLabel,
  });

  @override
  State<LocationPickerPage> createState() => _LocationPickerPageState();
}

class _LocationPickerPageState extends State<LocationPickerPage> {
  /// Enquadramento do Brasil inteiro — só entra em cena quando não há nem
  /// coordenada anterior nem GPS.
  static const _brazilFallback = LatLng(-14.24, -51.93);
  static const _countryZoom = 3.5;
  static const _addressZoom = 17.0;

  final _mapController = MapController();

  late LatLng _center;
  late double _initialZoom;
  bool _isLocating = false;

  @override
  void initState() {
    super.initState();

    final initial = widget.initial;
    if (initial != null && initial.isValid) {
      _center = LatLng(initial.latitude, initial.longitude);
      _initialZoom = _addressZoom;
    } else {
      _center = _brazilFallback;
      _initialZoom = _countryZoom;
      // Sem coordenada anterior: começa buscando o GPS, que quase sempre é
      // perto do destino — o entregador costuma estar na região.
      WidgetsBinding.instance.addPostFrameCallback((_) => _goToCurrent());
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _goToCurrent() async {
    if (_isLocating) return;
    setState(() => _isLocating = true);

    final result = await sl<GetCurrentLocation>()(const NoParams());
    if (!mounted) return;

    result.fold(
      (_) {
        setState(() => _isLocating = false);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(
            content: Text('Não consegui pegar sua localização agora.'),
          ));
      },
      (point) {
        setState(() => _isLocating = false);
        _mapController.move(
          LatLng(point.latitude, point.longitude),
          _addressZoom,
        );
      },
    );
  }

  void _confirm() {
    final center = _mapController.camera.center;
    Navigator.of(context).pop(
      GeoPoint(latitude: center.latitude, longitude: center.longitude),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Scaffold(
      appBar: AppBar(title: const Text('Ajustar localização')),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: _initialZoom,
              minZoom: 3,
              maxZoom: 19,
              // Redesenha o rodapé com a coordenada a cada arraste.
              onPositionChanged: (_, _) => setState(() {}),
              interactionOptions: const InteractionOptions(
                // Rotação desligada: mapa torto atrapalha mais do que ajuda
                // para quem só quer marcar um ponto, e é fácil de disparar sem
                // querer com dois dedos.
                flags: InteractiveFlag.pinchZoom |
                    InteractiveFlag.drag |
                    InteractiveFlag.doubleTapZoom |
                    InteractiveFlag.flingAnimation,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.routely.routely',
                maxNativeZoom: 19,
              ),
              // Atribuição ao OpenStreetMap é exigência da licença, não enfeite.
              RichAttributionWidget(
                alignment: AttributionAlignment.bottomLeft,
                attributions: [
                  TextSourceAttribution(
                    'OpenStreetMap',
                    onTap: () => launchUrl(
                      Uri.parse('https://openstreetmap.org/copyright'),
                      mode: LaunchMode.externalApplication,
                    ),
                  ),
                ],
              ),
            ],
          ),

          // O pino fica travado no centro da tela e quem se move é o mapa.
          // Arrastar um alfinete pequeno com o dedo em cima dele é impreciso —
          // o dedo tapa justamente o ponto que se quer enxergar.
          const IgnorePointer(child: Center(child: _CenterPin())),

          _AddressBanner(label: widget.addressLabel),

          Positioned(
            right: AppSpacing.md,
            bottom: 190,
            child: _CurrentLocationButton(
              isLoading: _isLocating,
              onTap: _goToCurrent,
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: c.surface,
          border: Border(top: BorderSide(color: c.border)),
        ),
        child: ResponsiveActionBar(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _CoordinateReadout(controller: _mapController),
              const SizedBox(height: AppSpacing.xs),
              ElevatedButton.icon(
                onPressed: _confirm,
                icon: const Icon(Icons.check_rounded),
                label: const Text('Confirmar este ponto'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CenterPin extends StatelessWidget {
  const _CenterPin();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.location_on, size: 46, color: c.accent),
        // Compensa a altura do ícone para a ponta do pino cair exatamente no
        // centro do mapa — que é a coordenada que será gravada.
        const SizedBox(height: 46),
      ],
    );
  }
}

class _AddressBanner extends StatelessWidget {
  final String label;

  const _AddressBanner({required this.label});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Positioned(
      top: AppSpacing.sm,
      left: AppSpacing.md,
      right: AppSpacing.md,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: AppRadius.mdAll,
          border: Border.all(color: c.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(Icons.push_pin_outlined, size: 18, color: c.textSecondary),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label.isEmpty ? 'Nova entrega' : label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'Arraste o mapa até a porta certa',
                    style: TextStyle(fontSize: 12.5, color: c.textTertiary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CurrentLocationButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onTap;

  const _CurrentLocationButton({required this.isLoading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Material(
      color: c.surface,
      borderRadius: AppRadius.mdAll,
      elevation: 3,
      child: InkWell(
        onTap: isLoading ? null : onTap,
        borderRadius: AppRadius.mdAll,
        child: SizedBox(
          width: 52,
          height: 52,
          child: isLoading
              ? const Padding(
                  padding: EdgeInsets.all(15),
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : Icon(Icons.my_location_rounded, color: c.brand),
        ),
      ),
    );
  }
}

/// Mostra a coordenada sob o pino. Serve de confirmação de que o mapa
/// realmente mexeu — e é o único feedback possível quando os tiles ainda não
/// carregaram por falta de sinal.
class _CoordinateReadout extends StatelessWidget {
  final MapController controller;

  const _CoordinateReadout({required this.controller});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    LatLng? center;
    try {
      center = controller.camera.center;
    } catch (_) {
      // A câmera só existe depois do primeiro layout do mapa.
      center = null;
    }

    return Text(
      center == null
          ? 'Posicione o pino'
          : '${center.latitude.toStringAsFixed(5)}, '
              '${center.longitude.toStringAsFixed(5)}',
      style: TextStyle(
        fontSize: 12.5,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: c.textTertiary,
      ),
    );
  }
}
