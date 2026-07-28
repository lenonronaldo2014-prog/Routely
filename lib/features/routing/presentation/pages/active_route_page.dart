import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/services/navigation_launcher.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/responsive_body.dart';
import '../../../../injection_container.dart';
import '../../../stops/domain/entities/delivery_stop.dart';
import '../../../stops/presentation/bloc/stops_bloc.dart';
import '../../../stops/presentation/bloc/stops_event.dart';
import '../../../stops/presentation/bloc/stops_state.dart';
import '../../domain/entities/active_route.dart';
import '../bloc/active_route_bloc.dart';
import '../bloc/active_route_event.dart';
import '../bloc/active_route_state.dart';
import '../widgets/route_roadmap.dart';

/// A tela usada com o roteiro em curso.
///
/// Diferente da tela de preview, aqui o foco é o que **falta**: a próxima
/// parada em destaque, o resto embaixo, e a marcação de entregue à mão. O
/// progresso vai direto para o banco a cada toque — se o celular morrer no
/// meio, nada se perde.
class ActiveRoutePage extends StatefulWidget {
  const ActiveRoutePage({super.key});

  @override
  State<ActiveRoutePage> createState() => _ActiveRoutePageState();
}

class _ActiveRoutePageState extends State<ActiveRoutePage> {
  @override
  void initState() {
    super.initState();
    // Confere em silêncio se a ordem ainda faz sentido de onde o entregador
    // está agora. Se não fizer, a tela sugere recalcular.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ActiveRouteBloc>().add(
            const ActiveRouteDriftCheckRequested(),
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rota em andamento'),
        actions: [
          BlocBuilder<ActiveRouteBloc, ActiveRouteState>(
            builder: (context, state) {
              final canRecalculate = state is ActiveRouteLoaded &&
                  state.route.remainingLegs.length > 1;

              return IconButton(
                tooltip: 'Recalcular a partir daqui',
                icon: const Icon(Icons.refresh_rounded),
                onPressed: canRecalculate && !state.isRecalculating
                    ? () => context
                        .read<ActiveRouteBloc>()
                        .add(const ActiveRouteRecalculateRequested())
                    : null,
              );
            },
          ),
          IconButton(
            tooltip: 'Encerrar rota',
            icon: const Icon(Icons.stop_circle_outlined),
            onPressed: () => _confirmFinish(context),
          ),
        ],
      ),
      // Marcar entregue passa pelo StopsBloc; a rota precisa recarregar para
      // o progresso e o "próxima parada" acompanharem. E logo depois vale
      // reconferir se a ordem ainda faz sentido de onde o entregador está.
      body: MultiBlocListener(
        listeners: [
          BlocListener<StopsBloc, StopsState>(
            listener: (context, _) {
              context.read<ActiveRouteBloc>()
                ..add(const ActiveRouteLoadRequested())
                ..add(const ActiveRouteDriftCheckRequested());
            },
          ),
          BlocListener<ActiveRouteBloc, ActiveRouteState>(
            listenWhen: (previous, current) =>
                current is ActiveRouteLoaded &&
                (current.actionError != null || current.actionMessage != null),
            listener: (context, state) {
              final loaded = state as ActiveRouteLoaded;
              final text = loaded.actionError ?? loaded.actionMessage!;

              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(
                  duration: const Duration(seconds: 5),
                  content: Text(text),
                ));
            },
          ),
        ],
        child: BlocBuilder<ActiveRouteBloc, ActiveRouteState>(
          builder: (context, state) {
            if (state is ActiveRouteLoaded) {
              return _RouteBody(state: state);
            }
            if (state is ActiveRouteFailure) {
              return Center(
                child: ResponsiveBody(
                  child: Text(
                    state.message,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.colors.textSecondary),
                  ),
                ),
              );
            }
            return const Center(child: CircularProgressIndicator());
          },
        ),
      ),
    );
  }

  Future<void> _confirmFinish(BuildContext context) async {
    final activeRouteBloc = context.read<ActiveRouteBloc>();
    final navigator = Navigator.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Encerrar rota?'),
        content: const Text(
          'A rota sai da tela inicial. As entregas continuam na lista, com o '
          'que você já marcou como entregue.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Encerrar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      activeRouteBloc.add(const ActiveRouteFinishRequested());
      navigator.pop();
    }
  }
}

class _RouteBody extends StatelessWidget {
  final ActiveRouteLoaded state;

  const _RouteBody({required this.state});

  ActiveRoute get route => state.route;

  @override
  Widget build(BuildContext context) {
    final launcher = sl<NavigationLauncher>();
    final next = route.nextStop;

    return Column(
      children: [
        Expanded(
          child: ResponsiveBody(
            wide: true,
            child: ListView(
              padding: const EdgeInsets.only(
                top: AppSpacing.xs,
                bottom: AppSpacing.xl,
              ),
              children: [
                _ProgressHeader(route: route),
                if (state.suggestRecalculation && next != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  _RecalculateSuggestion(isBusy: state.isRecalculating),
                ],
                const SizedBox(height: AppSpacing.lg),
                if (next != null) ...[
                  const SectionHeader(title: 'Próxima parada'),
                  const SizedBox(height: AppSpacing.sm),
                  _NextStopCard(
                    stop: next,
                    onNavigate: () => launcher.launch(
                      launcher.buildGoogleMapsDestination(next.coordinate!),
                    ),
                    onWaze: () => launcher.launch(
                      launcher.buildWazeDestination(next.coordinate!),
                    ),
                    onDelivered: () => _markDelivered(context, next),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ] else ...[
                  const InfoBanner(
                    icon: Icons.check_circle_outline_rounded,
                    title: 'Roteiro concluído',
                    message: 'Encerre a rota pelo botão no topo para liberar a '
                        'tela inicial.',
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
                // O roteiro inteiro numa linha só: o que já caiu vem marcado,
                // a parada atual em destaque, o resto na sequência. É a
                // resposta visual para "onde eu estou no dia".
                const SectionHeader(title: 'Roteiro'),
                const SizedBox(height: AppSpacing.md),
                RouteRoadmap(
                  legs: route.legs,
                  currentIndex: route.deliveredCount,
                  onTapStop: (stop) => launcher.launch(
                    launcher.buildGoogleMapsDestination(stop.coordinate!),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _markDelivered(BuildContext context, DeliveryStop stop) {
    context.read<StopsBloc>().add(StopStatusChangeRequested(
          stop: stop,
          status: StopStatus.delivered,
        ));
  }

}

/// Sugestão de recálculo.
///
/// A rota foi montada de onde o dia começou. Depois de algumas entregas o
/// entregador está longe daquele ponto, e a ordem que era ótima deixou de ser.
///
/// É sugestão, não ação automática: reordenar as paradas sem avisar
/// desorientaria quem já decorou as próximas duas.
class _RecalculateSuggestion extends StatelessWidget {
  final bool isBusy;

  const _RecalculateSuggestion({required this.isBusy});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: c.brandSoft,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: c.brand.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.alt_route_rounded, size: 19, color: c.brand),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Tem uma entrega mais perto de você',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'A ordem foi montada de onde você começou o dia. '
                      'Recalcular pode economizar caminho.',
                      style: TextStyle(
                        fontSize: 12.8,
                        color: c.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ElevatedButton.icon(
            onPressed: isBusy
                ? null
                : () => context
                    .read<ActiveRouteBloc>()
                    .add(const ActiveRouteRecalculateRequested()),
            icon: isBusy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.refresh_rounded),
            label: Text(
              isBusy ? 'Recalculando…' : 'Recalcular daqui',
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressHeader extends StatelessWidget {
  final ActiveRoute route;

  const _ProgressHeader({required this.route});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${route.deliveredCount}',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  letterSpacing: -1,
                  color: c.success,
                ),
              ),
              Text(
                ' de ${route.totalStops} entregues',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: c.textSecondary,
                ),
              ),
              const Spacer(),
              Text(
                route.strategy.label,
                style: TextStyle(fontSize: 12.5, color: c.textTertiary),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: route.progress,
              minHeight: 7,
              backgroundColor: c.surfaceAlt,
              valueColor: AlwaysStoppedAnimation(c.success),
            ),
          ),
          if (!route.isComplete) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Faltam ${route.formattedRemainingDuration} · '
              '${route.formattedRemainingDistance}',
              style: TextStyle(fontSize: 13, color: c.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

/// A parada atual ganha um card próprio, maior, com as ações à mão. É a única
/// coisa que importa enquanto ela não for entregue.
class _NextStopCard extends StatelessWidget {
  final DeliveryStop stop;
  final VoidCallback onNavigate;
  final VoidCallback onWaze;
  final VoidCallback onDelivered;

  const _NextStopCard({
    required this.stop,
    required this.onNavigate,
    required this.onWaze,
    required this.onDelivered,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return AppCard(
      borderColor: c.brand,
      borderWidth: 2,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (stop.label != null) ...[
            AppChip(label: stop.label!, color: c.accent),
            const SizedBox(height: AppSpacing.xs),
          ],
          Text(
            stop.shortAddress,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              height: 1.2,
              color: c.textPrimary,
            ),
          ),
          if (stop.locality.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              stop.locality,
              style: TextStyle(fontSize: 14, color: c.textSecondary),
            ),
          ],
          if (stop.complement != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Icon(Icons.meeting_room_outlined, size: 15, color: c.textTertiary),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    stop.complement!,
                    style: TextStyle(fontSize: 13.5, color: c.textSecondary),
                  ),
                ),
              ],
            ),
          ],
          if (stop.notes != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: c.surfaceAlt,
                borderRadius: AppRadius.smAll,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.sticky_note_2_outlined,
                      size: 15, color: c.textTertiary),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      stop.notes!,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: c.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onNavigate,
                  icon: const Icon(Icons.navigation_rounded, size: 20),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Navegar'),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              _SquareAction(
                icon: Icons.near_me_rounded,
                tooltip: 'Abrir no Waze',
                onTap: onWaze,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          OutlinedButton.icon(
            onPressed: onDelivered,
            icon: Icon(Icons.check_rounded, size: 20, color: c.success),
            label: const Text('Marcar como entregue'),
          ),
        ],
      ),
    );
  }
}

class _SquareAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _SquareAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: c.surfaceAlt,
        borderRadius: AppRadius.mdAll,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.mdAll,
          child: SizedBox(
            width: 56,
            height: 56,
            child: Icon(icon, color: c.textSecondary, size: 22),
          ),
        ),
      ),
    );
  }
}
