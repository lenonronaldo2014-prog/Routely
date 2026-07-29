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
import '../../domain/entities/address_query.dart';
import '../../domain/repositories/address_repository.dart';

/// De onde veio o ponto onde o mapa abriu. A tela avisa o usuário, porque
/// "achei o seu endereço" e "não achei, te mostrei onde você está" pedem
/// atenção bem diferente.
enum _StartOrigin { pin, address, saved, gps, country }

/// Ajuste manual da localização de uma entrega.
///
/// Existe porque geocoding erra — e erra **com internet**. Como o fluxo do app
/// é "cadastra de manhã com sinal, roda o dia sem", um endereço que falha vira
/// buraco no roteiro inteiro. Aqui o usuário resolve em dois toques.
class LocationPickerPage extends StatefulWidget {
  /// Ponto que o usuário já marcou à mão. Tem prioridade sobre tudo: ele
  /// escolheu isso de propósito.
  final GeoPoint? initial;

  /// Coordenada que a parada já tinha, vinda de geocoding. Só entra se não der
  /// para localizar o endereço digitado agora.
  final GeoPoint? fallback;

  /// Endereço digitado no formulário, em campos separados, para o mapa abrir
  /// o mais perto possível dele.
  ///
  /// Separado e não colado numa frase porque a busca vai afrouxando: quando o
  /// número não existe no mapa, ainda dá para achar a rua; depois o CEP, o
  /// bairro, a cidade.
  final AddressQuery? query;

  final String addressLabel;

  const LocationPickerPage({
    super.key,
    this.initial,
    this.fallback,
    this.query,
    required this.addressLabel,
  });

  @override
  State<LocationPickerPage> createState() => _LocationPickerPageState();
}

class _LocationPickerPageState extends State<LocationPickerPage> {
  /// Enquadramento do Brasil inteiro — só entra em cena quando nada mais
  /// resolveu.
  static const _brazilFallback = LatLng(-14.24, -51.93);
  static const _countryZoom = 3.5;
  static const _addressZoom = 17.0;

  /// Quanto o pino sobe em relação ao dedo enquanto é arrastado. Sem isso o
  /// dedo tapa exatamente a ponta, que é o ponto que se quer enxergar.
  static const _dragLift = 56.0;

  final _mapController = MapController();
  final _mapKey = GlobalKey();

  LatLng? _pin;
  double _initialZoom = _countryZoom;
  _StartOrigin _origin = _StartOrigin.country;

  /// Quanto do endereço a busca conseguiu casar. Só existe quando o ponto veio
  /// do endereço digitado — e é o que permite a tela dizer se falta ajustar o
  /// número ou o bairro inteiro.
  LocationPrecision? _precision;

  bool _isLocating = false;
  bool _isResolving = true;
  bool _isDraggingPin = false;

  @override
  void initState() {
    super.initState();
    _resolveStartingPoint();
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  /// Onde o mapa abre, do mais confiável para o menos:
  ///
  /// 1. o pino que o usuário já marcou — decisão dele, vale mais que tudo;
  /// 2. o endereço digitado agora, resolvido pela base de CEP ou geocoding;
  /// 3. a coordenada que a parada já tinha;
  /// 4. onde o usuário está;
  /// 5. o Brasil inteiro.
  ///
  /// O passo 2 é o que faltava: antes o mapa abria no ponto antigo mesmo
  /// quando o endereço tinha mudado, e o usuário precisava procurar o lugar na
  /// mão.
  ///
  /// O passo 2 também não é tudo-ou-nada. Se o número não for encontrado, a
  /// busca afrouxa até a rua, o CEP, o bairro. Cair no passo 4 — a localização
  /// do próprio usuário — significaria abrir o mapa possivelmente a
  /// quilômetros do destino, e é o que se tenta evitar até o fim.
  Future<void> _resolveStartingPoint() async {
    final manual = widget.initial;
    if (manual != null && manual.isValid) {
      _start(manual, _StartOrigin.pin, zoom: _addressZoom);
      return;
    }

    final fromAddress = await _locateTypedAddress();
    if (!mounted) return;

    if (fromAddress != null) {
      _start(
        fromAddress.point,
        _StartOrigin.address,
        zoom: fromAddress.precision.zoom,
        precision: fromAddress.precision,
      );
      return;
    }

    final saved = widget.fallback;
    if (saved != null && saved.isValid) {
      _start(saved, _StartOrigin.saved, zoom: _addressZoom);
      return;
    }

    final current = await _currentLocation();
    if (!mounted) return;

    if (current != null) {
      _start(current, _StartOrigin.gps, zoom: _addressZoom);
      return;
    }

    setState(() {
      _pin = _brazilFallback;
      _initialZoom = _countryZoom;
      _origin = _StartOrigin.country;
      _isResolving = false;
    });
  }

  void _start(
    GeoPoint point,
    _StartOrigin origin, {
    required double zoom,
    LocationPrecision? precision,
  }) {
    setState(() {
      _pin = LatLng(point.latitude, point.longitude);
      _initialZoom = zoom;
      _origin = origin;
      _precision = precision;
      _isResolving = false;
    });
  }

  /// Delega a cascata ao repositório: base de CEP, endereço com número, rua,
  /// CEP, bairro, cidade — o primeiro que responder.
  Future<ApproximateLocation?> _locateTypedAddress() async {
    final query = widget.query;
    if (query == null || query.isEmpty) return null;

    return sl<AddressRepository>().locateApproximate(query);
  }

  Future<GeoPoint?> _currentLocation() async {
    final result = await sl<GetCurrentLocation>()(const NoParams());
    return result.fold((_) => null, (point) => point);
  }

  Future<void> _goToCurrent() async {
    if (_isLocating) return;
    setState(() => _isLocating = true);

    final point = await _currentLocation();
    if (!mounted) return;

    setState(() => _isLocating = false);

    if (point == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('Não consegui pegar sua localização agora.'),
        ));
      return;
    }

    final target = LatLng(point.latitude, point.longitude);
    setState(() => _pin = target);
    _mapController.move(target, _addressZoom);
  }

  void _handleMapTap(TapPosition _, LatLng point) {
    setState(() => _pin = point);
  }

  /// Converte a posição do dedo em coordenada, com o pino levantado para a
  /// ponta ficar visível acima da mão.
  void _dragPin(Offset globalPosition) {
    final box = _mapKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;

    final local = box.globalToLocal(globalPosition);
    final lifted = Offset(local.dx, local.dy - _dragLift);

    setState(() => _pin = _mapController.camera.screenOffsetToLatLng(lifted));
  }

  void _confirm() {
    final pin = _pin;
    if (pin == null) return;

    Navigator.of(context).pop(
      GeoPoint(latitude: pin.latitude, longitude: pin.longitude),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    if (_isResolving) return _resolvingScaffold(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Ajustar localização')),
      body: Stack(
        children: [
          FlutterMap(
            key: _mapKey,
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _pin ?? _brazilFallback,
              initialZoom: _initialZoom,
              minZoom: 3,
              maxZoom: 19,
              // Tocar no mapa põe o pino ali. É o caminho mais preciso: o
              // usuário mira na porta certa e toca, sem arrastar nada.
              //
              // Referência de método, não closure inline: closure nova a cada
              // build faz o flutter_map enxergar opções diferentes e refazer
              // trabalho à toa.
              //
              // Repare que não há `onPositionChanged` aqui. Uma versão
              // anterior chamava setState nele para atualizar a coordenada do
              // rodapé, e isso reconstruía a página inteira a cada quadro do
              // movimento do mapa — o app travava com ANR. Como o pino agora
              // é um marcador com posição própria, a coordenada não depende
              // mais da câmera e o callback deixou de ser necessário.
              onTap: _handleMapTap,
              interactionOptions: InteractionOptions(
                // Enquanto o pino está sendo arrastado, o mapa não pode andar
                // junto — senão os dois se movem e a mira foge.
                flags: _isDraggingPin
                    ? InteractiveFlag.none
                    // Rotação desligada: mapa torto atrapalha quem só quer
                    // marcar um ponto, e é fácil de disparar sem querer.
                    : InteractiveFlag.pinchZoom |
                        InteractiveFlag.drag |
                        InteractiveFlag.doubleTapZoom |
                        InteractiveFlag.flingAnimation,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.routely.routely',
                maxNativeZoom: 19,
              ),
              if (_pin != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _pin!,
                      width: 64,
                      height: 76,
                      // O marcador fica acima do ponto, então a ponta do pino
                      // é que encosta na coordenada.
                      alignment: Alignment.topCenter,
                      child: _DraggablePin(
                        isDragging: _isDraggingPin,
                        onDragStart: () =>
                            setState(() => _isDraggingPin = true),
                        onDragUpdate: _dragPin,
                        onDragEnd: () =>
                            setState(() => _isDraggingPin = false),
                      ),
                    ),
                  ],
                ),
              // Atribuição ao OpenStreetMap é exigência da licença.
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

          _Header(
            label: widget.addressLabel,
            origin: _origin,
            precision: _precision,
          ),

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
              _CoordinateReadout(pin: _pin),
              const SizedBox(height: AppSpacing.xs),
              ElevatedButton.icon(
                onPressed: _pin == null ? null : _confirm,
                icon: const Icon(Icons.check_rounded),
                label: const Text('Confirmar este ponto'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _resolvingScaffold(BuildContext context) {
    final c = context.colors;

    return Scaffold(
      appBar: AppBar(title: const Text('Ajustar localização')),
      body: Center(
        child: ResponsiveBody(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Procurando o endereço no mapa…',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                'Se o número não existir no mapa, abre na rua ou no bairro',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: c.textTertiary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pino arrastável.
///
/// O usuário pode tocar em qualquer lugar do mapa para posicionar, ou arrastar
/// o próprio pino. Tocar é mais preciso; arrastar é o gesto que a maioria
/// espera. Ter os dois evita a frustração de descobrir qual é o "certo".
///
/// A área de toque é maior que o desenho: pino pequeno é difícil de pegar com
/// o dedo, ainda mais em movimento.
class _DraggablePin extends StatelessWidget {
  final bool isDragging;
  final VoidCallback onDragStart;
  final void Function(Offset globalPosition) onDragUpdate;
  final VoidCallback onDragEnd;

  const _DraggablePin({
    required this.isDragging,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    // `Listener` e não `GestureDetector`: o mapa disputa o gesto de arraste e
    // ganha, então um GestureDetector aqui só via o mapa deslizar embaixo do
    // pino. O Listener recebe os eventos de ponteiro direto, sem entrar na
    // disputa — e o `onPointerDown` desliga a interação do mapa antes de ele
    // começar a reconhecer o arraste.
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => onDragStart(),
      onPointerMove: (event) => onDragUpdate(event.position),
      onPointerUp: (_) => onDragEnd(),
      onPointerCancel: (_) => onDragEnd(),
      child: AnimatedScale(
        // Cresce um pouco ao ser pego — confirma que o gesto pegou o pino, e
        // não o mapa.
        scale: isDragging ? 1.25 : 1.0,
        duration: const Duration(milliseconds: 140),
        alignment: Alignment.bottomCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.location_on,
              size: 54,
              color: c.accent,
              shadows: const [
                Shadow(color: Colors.black45, blurRadius: 6, offset: Offset(0, 2)),
              ],
            ),
            // Ponto de mira: mostra exatamente onde a ponta encosta, que é a
            // coordenada que vai ser gravada.
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: c.accent,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String label;
  final _StartOrigin origin;

  /// Só vem preenchida quando o ponto saiu do endereço digitado.
  final LocationPrecision? precision;

  const _Header({
    required this.label,
    required this.origin,
    this.precision,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    final (icon, hint, tone) = switch (origin) {
      _StartOrigin.pin => (
          Icons.push_pin_rounded,
          'Este é o ponto que você marcou antes',
          c.textTertiary,
        ),
      // Dizer só "achei este endereço" depois de casar apenas a cidade seria
      // mentira, e o usuário confirmaria um ponto errado achando que estava
      // certo. Cada precisão pede um aviso do tamanho do erro que ela carrega.
      _StartOrigin.address => switch (precision ?? LocationPrecision.exact) {
          LocationPrecision.exact => (
              Icons.place_rounded,
              'Achei este endereço. Toque na porta certa para ajustar',
              c.textTertiary,
            ),
          LocationPrecision.street => (
              Icons.signpost_rounded,
              'Achei a rua, mas não o número. Toque na porta certa',
              c.warning,
            ),
          LocationPrecision.postalCode => (
              Icons.markunread_mailbox_rounded,
              'Este é o ponto do CEP. Toque na porta certa para ajustar',
              c.warning,
            ),
          LocationPrecision.neighborhood => (
              Icons.holiday_village_rounded,
              'Achei só o bairro. Aproxime e toque na porta certa',
              c.warning,
            ),
          LocationPrecision.city => (
              Icons.location_city_rounded,
              'Achei só a cidade. Aproxime e toque no local da entrega',
              c.warning,
            ),
        },
      _StartOrigin.saved => (
          Icons.history_rounded,
          'Ponto salvo antes. Toque no mapa para corrigir',
          c.warning,
        ),
      _StartOrigin.gps => (
          Icons.my_location_rounded,
          'Não achei o endereço — este é o seu local. Toque no destino',
          c.warning,
        ),
      _StartOrigin.country => (
          Icons.public_rounded,
          'Não achei o endereço. Aproxime e toque no local da entrega',
          c.warning,
        ),
    };

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
            Icon(icon, size: 18, color: tone),
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
                    hint,
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

/// Mostra a coordenada sob o pino. É o único feedback possível quando os tiles
/// ainda não carregaram por falta de sinal.
class _CoordinateReadout extends StatelessWidget {
  final LatLng? pin;

  const _CoordinateReadout({required this.pin});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Text(
      pin == null
          ? 'Posicione o pino'
          : '${pin!.latitude.toStringAsFixed(5)}, '
              '${pin!.longitude.toStringAsFixed(5)}',
      style: TextStyle(
        fontSize: 12.5,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: c.textTertiary,
      ),
    );
  }
}
