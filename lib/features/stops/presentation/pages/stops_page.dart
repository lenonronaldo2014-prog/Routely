import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/geo/geo_point.dart';
import '../../../../core/theme/app_breakpoints.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/responsive_body.dart';
import '../../../routing/presentation/bloc/active_route_bloc.dart';
import '../../../routing/presentation/bloc/active_route_event.dart';
import '../../../routing/presentation/bloc/active_route_state.dart';
import '../../../routing/presentation/pages/active_route_page.dart';
import '../../../routing/presentation/pages/route_options_page.dart';
import '../../../routing/presentation/widgets/active_route_card.dart';
import '../../../settings/presentation/pages/settings_page.dart';
import '../../domain/entities/address_query.dart';
import '../../domain/entities/delivery_stop.dart';
import '../../domain/entities/scanned_address.dart';
import '../bloc/stops_bloc.dart';
import '../bloc/stops_event.dart';
import '../bloc/stops_state.dart';
import '../widgets/stop_tile.dart';
import 'location_picker_page.dart';
import 'scan_label_page.dart';
import 'stop_form_page.dart';

class StopsPage extends StatelessWidget {
  const StopsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: BlocConsumer<StopsBloc, StopsState>(
          listener: (context, state) {
            if (state is StopsFailure) {
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(content: Text(state.message)));
              return;
            }

            // Marcar entregue ou apagar uma parada muda o progresso da rota
            // gravada — o card de retomada precisa acompanhar.
            context.read<ActiveRouteBloc>().add(
                  const ActiveRouteLoadRequested(),
                );
          },
          builder: (context, state) {
            if (state is StopsLoading || state is StopsInitial) {
              return const Center(child: CircularProgressIndicator());
            }

            if (state is StopsFailure) {
              return _ErrorView(
                message: state.message,
                onRetry: () =>
                    context.read<StopsBloc>().add(const StopsLoadRequested()),
              );
            }

            final loaded = state as StopsLoaded;

            return Column(
              children: [
                _Header(state: loaded),
                Expanded(
                  child: loaded.stops.isEmpty
                      ? const _EmptyView()
                      : _StopsList(state: loaded),
                ),
              ],
            );
          },
        ),
      ),
      // Sem FloatingActionButton de propósito: flutuando sobre a lista ele
      // cobria o primeiro card em paisagem, onde sobra pouca altura. As duas
      // ações moram na mesma barra inferior — nunca colidem com o conteúdo e
      // ficam ambas no alcance do polegar.
      bottomNavigationBar: _ActionBar(
        onAdd: () => _openForm(context),
        onScan: () => _scanLabel(context),
      ),
    );
  }

  Future<void> _openForm(
    BuildContext context, {
    DeliveryStop? stop,
    ScannedAddress? scanned,
  }) async {
    final bloc = context.read<StopsBloc>();

    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => StopFormPage(existing: stop, scanned: scanned),
      ),
    );

    if (saved == true) bloc.add(const StopsLoadRequested());
  }

  /// Fotografar a etiqueta e cair no formulário já preenchido. É o caminho
  /// rápido para quem tem uma pilha de pacotes na frente.
  Future<void> _scanLabel(BuildContext context) async {
    final scanned = await Navigator.of(context).push<ScannedAddress>(
      MaterialPageRoute(builder: (_) => const ScanLabelPage()),
    );

    if (scanned == null || !context.mounted) return;
    await _openForm(context, scanned: scanned);
  }
}

/// Cabeçalho com o título grande e um resumo do dia. O resumo responde de
/// relance a pergunta que o entregador faz o tempo todo: quanto falta?
class _Header extends StatelessWidget {
  final StopsLoaded state;

  const _Header({required this.state});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final pending = state.pending.length;
    final done = state.completed.length;

    return ResponsiveBody(
      wide: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              const _BrandMark(),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Routely',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.6,
                        color: c.textTertiary,
                      ),
                    ),
                    Text(
                      'Minhas entregas',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ],
                ),
              ),
              if (done > 0) ...[
                _HeaderAction(
                  icon: Icons.cleaning_services_outlined,
                  tooltip: 'Limpar concluídas',
                  onTap: () => _confirmClear(context),
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
              _HeaderAction(
                icon: Icons.tune_rounded,
                tooltip: 'Configurações',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsPage()),
                ),
              ),
              // A entrada para [CepPacksPage] fica fora da UI de propósito.
              //
              // O fluxo real do app é: o usuário cadastra os endereços com
              // internet e roda o dia inteiro sem — e isso já funciona, porque
              // a coordenada fica salva no banco. Instalar base de CEP só
              // ajudaria para cadastrar endereço novo no meio da rua sem
              // sinal, que é caso de borda.
              //
              // Expor a tela obrigaria o usuário a decidir sobre algo que ele
              // não precisa. O código continua inteiro e testado; para
              // reativar, basta um _HeaderAction abrindo a CepPacksPage.
              //
              // A cadeia de consulta (base → cache → rede → faixa numérica)
              // segue ativa: sem base instalada ela simplesmente pula o
              // primeiro degrau.
            ],
          ),
          if (state.stops.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              _summaryLine(pending, done),
              style: TextStyle(fontSize: 14.5, color: c.textSecondary),
            ),
            if (done > 0) ...[
              const SizedBox(height: AppSpacing.sm),
              _ProgressBar(done: done, total: state.stops.length),
            ],
          ],
          const SizedBox(height: AppSpacing.md),
        ],
      ),
    );
  }

  String _summaryLine(int pending, int done) {
    if (pending == 0) return 'Tudo entregue. Bom trabalho.';
    final falta = pending == 1 ? '1 entrega pendente' : '$pending entregas pendentes';
    if (done == 0) return falta;
    return '$falta · $done concluída${done == 1 ? "" : "s"}';
  }

  Future<void> _confirmClear(BuildContext context) async {
    final bloc = context.read<StopsBloc>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Limpar concluídas?'),
        content: const Text(
          'As entregas finalizadas saem da lista e vão para o histórico. '
          'As pendentes continuam aqui.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Limpar'),
          ),
        ],
      ),
    );

    if (confirmed == true) bloc.add(const CompletedStopsClearRequested());
  }
}

/// Marca do app no cabeçalho — o mesmo ícone que aparece na gaveta do
/// Android, para o usuário reconhecer que está no lugar certo.
///
/// Pequena e discreta: quem abriu o app já sabe qual é. O espaço pertence às
/// entregas, não ao logo.
class _BrandMark extends StatelessWidget {
  const _BrandMark();

  static const _side = 44.0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return ClipRRect(
      borderRadius: AppRadius.mdAll,
      child: Image.asset(
        'assets/icon/app_mark.png',
        width: _side,
        height: _side,
        fit: BoxFit.cover,
        // O arquivo tem 256px; decodificar no tamanho de exibição evita
        // segurar um bitmap grande na memória à toa.
        cacheWidth: (_side * MediaQuery.devicePixelRatioOf(context)).round(),
        // Se o asset faltar, o app não pode quebrar por causa de um logo.
        errorBuilder: (context, _, _) => Container(
          width: _side,
          height: _side,
          alignment: Alignment.center,
          color: c.brand,
          child: Icon(Icons.route_rounded, size: 24, color: c.onBrand),
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final int done;
  final int total;

  const _ProgressBar({required this.done, required this.total});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: total == 0 ? 0 : done / total),
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 7,
                backgroundColor: c.surfaceAlt,
                valueColor: AlwaysStoppedAnimation(c.success),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          '$done/$total',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: c.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _HeaderAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _HeaderAction({
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
        color: c.surface,
        borderRadius: AppRadius.smAll,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.smAll,
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: AppRadius.smAll,
              border: Border.all(color: c.border),
            ),
            child: Icon(icon, size: 20, color: c.textSecondary),
          ),
        ),
      ),
    );
  }
}

class _StopsList extends StatelessWidget {
  final StopsLoaded state;

  const _StopsList({required this.state});

  @override
  Widget build(BuildContext context) {
    final pending = state.pending;
    final completed = state.completed;

    return RefreshIndicator(
      onRefresh: () async {
        context
            .read<StopsBloc>()
            .add(const PendingCoordinatesResolveRequested());
      },
      child: ResponsiveBody(
        wide: true,
        child: ListView(
          padding: const EdgeInsets.only(
            bottom: AppSpacing.bottomActionInset + AppSpacing.xxl,
          ),
          children: [
            const _ActiveRouteBanner(),
            if (state.unresolved.isNotEmpty) ...[
              InfoBanner(
                icon: Icons.location_off_outlined,
                tone: BannerTone.warning,
                title: state.unresolved.length == 1
                    ? '1 entrega sem localização'
                    : '${state.unresolved.length} entregas sem localização',
                message: 'Elas ficam de fora da rota. Toque em "Marcar no '
                    'mapa" na entrega, ou puxe a lista para baixo com internet '
                    'para tentar de novo.',
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            if (pending.isNotEmpty) ...[
              const SectionHeader(title: 'A entregar'),
              const SizedBox(height: AppSpacing.sm),
              ...pending.map((stop) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm - 2),
                    child: _buildTile(context, stop),
                  )),
            ],
            if (completed.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              SectionHeader(title: 'Concluídas', count: completed.length),
              const SizedBox(height: AppSpacing.sm),
              ...completed.map((stop) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm - 2),
                    child: _buildTile(context, stop),
                  )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTile(BuildContext context, DeliveryStop stop) {
    final bloc = context.read<StopsBloc>();

    return StopTile(
      stop: stop,
      onToggleDelivered: () => bloc.add(StopStatusChangeRequested(
        stop: stop,
        status: stop.status == StopStatus.delivered
            ? StopStatus.pending
            : StopStatus.delivered,
      )),
      onDelete: () => bloc.add(StopDeleteRequested(stop.id)),
      onFixLocation:
          stop.isRoutable ? null : () => _fixLocation(context, stop),
      onTap: () async {
        final saved = await Navigator.of(context).push<bool>(
          MaterialPageRoute(builder: (_) => StopFormPage(existing: stop)),
        );
        if (saved == true) bloc.add(const StopsLoadRequested());
      },
    );
  }

  Future<void> _fixLocation(BuildContext context, DeliveryStop stop) async {
    final bloc = context.read<StopsBloc>();

    final picked = await Navigator.of(context).push<GeoPoint>(
      MaterialPageRoute(
        builder: (_) => LocationPickerPage(
          fallback: stop.coordinate,
          // Estas paradas chegam aqui justamente porque o geocoding falhou no
          // salvamento. Mandar o endereço de novo dá uma segunda chance — e a
          // base de CEP local costuma resolver sem rede.
          query: AddressQuery(
            cep: stop.cep,
            street: stop.street,
            number: stop.number,
            neighborhood: stop.neighborhood,
            city: stop.city,
            state: stop.state,
          ),
          addressLabel: stop.shortAddress,
        ),
      ),
    );

    if (picked != null) {
      bloc.add(StopLocationUpdateRequested(stop: stop, coordinate: picked));
    }
  }
}

/// Retomada do roteiro. Aparece no topo da lista sempre que existe rota
/// gravada — inclusive depois do app ter sido morto no meio do dia.
class _ActiveRouteBanner extends StatelessWidget {
  const _ActiveRouteBanner();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ActiveRouteBloc, ActiveRouteState>(
      builder: (context, state) {
        if (state is! ActiveRouteLoaded) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: ActiveRouteCard(
            route: state.route,
            onContinue: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ActiveRoutePage()),
            ),
          ),
        );
      },
    );
  }
}

/// Barra fixa com as ações da tela.
///
/// Enquanto não há rota possível, "Nova entrega" ocupa a largura toda — é a
/// única coisa que faz sentido fazer. Assim que existe o que rotear, ela encolhe
/// para um botão de ícone e cede o espaço ao "Calcular rota", que passa a ser a
/// ação principal.
class _ActionBar extends StatelessWidget {
  final VoidCallback onAdd;
  final VoidCallback onScan;

  const _ActionBar({required this.onAdd, required this.onScan});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<StopsBloc, StopsState>(
      builder: (context, state) {
        final canCalculate = state is StopsLoaded && state.canCalculateRoute;

        // Ainda não há rota possível: escanear é a ação promovida, porque é o
        // caminho rápido para quem tem uma pilha de pacotes na frente.
        if (!canCalculate) {
          return ResponsiveActionBar(
            wide: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton.icon(
                  onPressed: onScan,
                  icon: const Icon(Icons.document_scanner_rounded),
                  label: const Text('Escanear etiqueta'),
                ),
                TextButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('ou digitar endereço'),
                ),
              ],
            ),
          );
        }

        final count = state.routable.length;

        return ResponsiveActionBar(
          wide: true,
          child: Row(
            children: [
              _SquareAction(
                icon: Icons.document_scanner_rounded,
                label: 'Escanear etiqueta',
                onTap: onScan,
                filled: true,
              ),
              const SizedBox(width: AppSpacing.xs),
              _SquareAction(
                icon: Icons.add_rounded,
                label: 'Digitar endereço',
                onTap: onAdd,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => RouteOptionsPage(stops: state.routable),
                      ),
                    );
                  },
                  icon: const Icon(Icons.alt_route_rounded),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'Calcular · $count '
                      '${count == 1 ? "entrega" : "entregas"}',
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SquareAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;

  const _SquareAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Semantics(
      label: label,
      button: true,
      child: Tooltip(
        message: label,
        child: Material(
          color: filled ? c.accent : c.surfaceAlt,
          borderRadius: AppRadius.mdAll,
          child: InkWell(
            onTap: onTap,
            borderRadius: AppRadius.mdAll,
            child: SizedBox(
              width: AppTheme.minTouchTarget,
              height: AppTheme.minTouchTarget,
              child: Icon(
                icon,
                color: filled ? Colors.white : c.textPrimary,
                size: 24,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final compact = AppBreakpoints.isCompact(context);

    return ResponsiveBody(
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: compact ? 92 : 108,
                height: compact ? 92 : 108,
                decoration: BoxDecoration(
                  color: c.brandSoft,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.local_shipping_rounded,
                  size: compact ? 44 : 52,
                  color: c.brand,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                'Nenhuma entrega ainda',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Adicione os endereços do dia e o Routely monta as melhores '
                'rotas a partir de onde você está.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14.5,
                  color: c.textSecondary,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
              _EmptyHints(),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyHints extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    const hints = [
      (Icons.bolt_rounded, 'Mais rápida', 'menor tempo total'),
      (Icons.local_gas_station_rounded, 'Mais econômica', 'menos combustível'),
      (Icons.my_location_rounded, 'Mais próxima', 'tira entregas rápido'),
    ];

    return Column(
      children: [
        Text(
          'VOCÊ ESCOLHE A ROTA',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            color: c.textTertiary,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            for (final (icon, title, subtitle) in hints)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Column(
                    children: [
                      Icon(icon, size: 20, color: c.textSecondary),
                      const SizedBox(height: 6),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: c.textPrimary,
                        ),
                      ),
                      Text(
                        subtitle,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11.5, color: c.textTertiary),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return ResponsiveBody(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 52, color: c.danger),
            const SizedBox(height: AppSpacing.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15.5, color: c.textSecondary),
            ),
            const SizedBox(height: AppSpacing.xl),
            OutlinedButton(
              onPressed: onRetry,
              child: const Text('Tentar de novo'),
            ),
          ],
        ),
      ),
    );
  }
}
