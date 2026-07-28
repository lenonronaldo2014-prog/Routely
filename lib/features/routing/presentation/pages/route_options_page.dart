import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/responsive_body.dart';
import '../../../../injection_container.dart';
import '../../../location/domain/repositories/location_repository.dart';
import '../../../stops/domain/entities/delivery_stop.dart';
import '../bloc/route_bloc.dart';
import '../bloc/route_event.dart';
import '../bloc/route_state.dart';
import '../widgets/batch_notice.dart';
import '../widgets/route_option_card.dart';
import 'route_detail_page.dart';

class RouteOptionsPage extends StatelessWidget {
  final List<DeliveryStop> stops;

  const RouteOptionsPage({super.key, required this.stops});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<RouteBloc>()..add(RouteCalculationRequested(stops)),
      child: const _RouteOptionsView(),
    );
  }
}

class _RouteOptionsView extends StatelessWidget {
  const _RouteOptionsView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Escolha sua rota')),
      body: BlocBuilder<RouteBloc, RouteState>(
        builder: (context, state) {
          return switch (state) {
            RouteCalculating() => _LoadingView(stage: state.stage),
            RouteOptionsReady() => _OptionsList(state: state),
            RouteFailureState() => _FailureView(state: state),
            _ => const SizedBox.shrink(),
          };
        },
      ),
    );
  }
}

class _OptionsList extends StatelessWidget {
  final RouteOptionsReady state;

  const _OptionsList({required this.state});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final options = state.options;

    // A sugerida é sempre a de menor tempo total, independentemente da
    // estratégia que a produziu.
    final recommended = options.reduce(
      (a, b) => a.totalDurationSeconds <= b.totalDurationSeconds ? a : b,
    );

    return ResponsiveBody(
      wide: true,
      child: ListView(
        padding: const EdgeInsets.only(
          top: AppSpacing.xs,
          bottom: AppSpacing.xxl,
        ),
        children: [
          Text(
            options.length == 1
                ? 'Com essas paradas só existe uma ordem que faz sentido.'
                : 'Compare e escolha. Você conhece detalhes que o cálculo não '
                    'conhece.',
            style: TextStyle(
              fontSize: 14.5,
              color: c.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (state.plan.hasDeferred) ...[
            BatchNotice(plan: state.plan),
            const SizedBox(height: AppSpacing.md),
          ],
          if (state.isEstimate) ...[
            const InfoBanner(
              icon: Icons.info_outline_rounded,
              title: 'Tempos estimados',
              message: 'Calculados por distância em linha reta. A ordem das '
                  'paradas é confiável; os minutos são aproximados.',
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          ...options.map((option) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: RouteOptionCard(
                  option: option,
                  isRecommended: options.length > 1 && option == recommended,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => RouteDetailPage(
                        option: option,
                        origin: state.origin,
                      ),
                    ),
                  ),
                ),
              )),
        ],
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  final RouteCalculationStage stage;

  const _LoadingView({required this.stage});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    final (icon, message, hint) = switch (stage) {
      RouteCalculationStage.locating => (
          Icons.my_location_rounded,
          'Localizando você…',
          'Pode levar alguns segundos com o GPS frio',
        ),
      RouteCalculationStage.calculating => (
          Icons.alt_route_rounded,
          'Montando as rotas…',
          'Comparando as ordens possíveis',
        ),
    };

    return Center(
      child: ResponsiveBody(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 84,
              height: 84,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 84,
                    height: 84,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: c.brand,
                      backgroundColor: c.surfaceAlt,
                    ),
                  ),
                  Icon(icon, size: 30, color: c.brand),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: c.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}

class _FailureView extends StatelessWidget {
  final RouteFailureState state;

  const _FailureView({required this.state});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Center(
      child: ResponsiveBody(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: c.warning.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.location_disabled_rounded,
                size: 40,
                color: c.warning,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              state.message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15.5,
                height: 1.45,
                color: c.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            if (state.needsSettings)
              ElevatedButton.icon(
                onPressed: () => sl<LocationRepository>().openAppSettings(),
                icon: const Icon(Icons.settings_rounded),
                label: const Text('Abrir configurações'),
              )
            else
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Voltar'),
              ),
          ],
        ),
      ),
    );
  }
}
