import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/geo/geo_point.dart';
import '../../../../core/services/navigation_launcher.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/responsive_body.dart';
import '../../../../injection_container.dart';
import '../../domain/entities/route_option.dart';
import '../bloc/active_route_bloc.dart';
import '../bloc/active_route_event.dart';
import '../widgets/route_roadmap.dart';
import 'active_route_page.dart';

class RouteDetailPage extends StatelessWidget {
  final RouteOption option;
  final GeoPoint origin;

  const RouteDetailPage({
    super.key,
    required this.option,
    required this.origin,
  });

  @override
  Widget build(BuildContext context) {
    final launcher = sl<NavigationLauncher>();
    final stops = option.orderedStops;

    final legUrls = launcher.buildGoogleMapsRoute(
      origin: origin,
      stops: stops.map((s) => s.coordinate!).toList(),
    );

    return Scaffold(
      appBar: AppBar(title: Text(option.strategy.label)),
      body: ResponsiveBody(
        wide: true,
        child: ListView(
          padding: const EdgeInsets.only(
            top: AppSpacing.xs,
            bottom: AppSpacing.bottomActionInset + AppSpacing.xl,
          ),
          children: [
            _SummaryCard(option: option),
            const SizedBox(height: AppSpacing.lg),
            if (legUrls.length > 1) ...[
              InfoBanner(
                icon: Icons.call_split_rounded,
                title: 'Rota dividida em ${legUrls.length} trechos',
                message: 'O Google Maps aceita no máximo 10 paradas por vez. '
                    'Ao terminar o primeiro trecho, volte aqui para abrir o '
                    'próximo.',
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            const SectionHeader(title: 'Ordem das entregas'),
            const SizedBox(height: AppSpacing.md),
            RouteRoadmap(
              legs: option.legs,
              onTapStop: (stop) => launcher.launch(
                launcher.buildGoogleMapsDestination(stop.coordinate!),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: ResponsiveActionBar(
        wide: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Iniciar grava a rota no banco. A partir daqui ela sobrevive ao
            // app fechar, ser morto pelo sistema ou a bateria acabar.
            ElevatedButton.icon(
              onPressed: stops.isEmpty ? null : () => _start(context),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Iniciar esta rota'),
            ),
            const SizedBox(height: AppSpacing.xs),
            OutlinedButton.icon(
              onPressed:
                  legUrls.isEmpty ? null : () => launcher.launch(legUrls.first),
              icon: const Icon(Icons.navigation_rounded, size: 19),
              label: Text(
                legUrls.length > 1
                    ? 'Só abrir no mapa · trecho 1 de ${legUrls.length}'
                    : 'Só abrir no mapa',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension on RouteDetailPage {
  /// Persiste a rota e volta para a tela inicial já dentro do roteiro. Voltar
  /// à raiz é de propósito: iniciada a rota, o histórico de comparação de
  /// alternativas não interessa mais.
  void _start(BuildContext context) {
    context.read<ActiveRouteBloc>().add(ActiveRouteStartRequested(
          option: option,
          origin: origin,
        ));

    Navigator.of(context).popUntil((route) => route.isFirst);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ActiveRoutePage()),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final RouteOption option;

  const _SummaryCard({required this.option});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final serviceMinutes = (option.serviceDurationSeconds / 60).round();

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c.brand, Color.lerp(c.brand, Colors.black, 0.22)!],
        ),
        borderRadius: AppRadius.lgAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                option.formattedDuration,
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.8,
                  height: 1,
                  color: c.onBrand,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  'no total',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: c.onBrand.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              _SummaryItem(
                icon: Icons.straighten_rounded,
                value: option.formattedDistance,
                caption: 'distância',
              ),
              _SummaryItem(
                icon: Icons.inventory_2_outlined,
                value: '${option.stopCount}',
                caption: option.stopCount == 1 ? 'parada' : 'paradas',
              ),
              _SummaryItem(
                icon: Icons.timer_outlined,
                value: '${serviceMinutes}min',
                caption: 'entregando',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  final IconData icon;
  final String value;
  final String caption;

  const _SummaryItem({
    required this.icon,
    required this.value,
    required this.caption,
  });

  @override
  Widget build(BuildContext context) {
    final onBrand = context.colors.onBrand;

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: onBrand.withValues(alpha: 0.65)),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: onBrand,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 1),
          Text(
            caption,
            style: TextStyle(
              fontSize: 11.5,
              color: onBrand.withValues(alpha: 0.65),
            ),
          ),
        ],
      ),
    );
  }
}

