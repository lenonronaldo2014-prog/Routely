import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/services/update_checker.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/responsive_body.dart';
import '../../../../injection_container.dart';
import '../../../stops/domain/repositories/backup_repository.dart';
import '../../../stops/presentation/bloc/stops_bloc.dart';
import '../../../stops/presentation/bloc/stops_event.dart';
import '../../../stops/presentation/pages/history_page.dart';
import '../cubit/settings_cubit.dart';
import '../widgets/theme_option_card.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: BlocBuilder<SettingsCubit, SettingsState>(
        builder: (context, state) {
          return ResponsiveBody(
            child: ListView(
              padding: const EdgeInsets.only(
                top: AppSpacing.xs,
                bottom: AppSpacing.xxl,
              ),
              children: [
                const SectionHeader(title: 'Aparência'),
                const SizedBox(height: AppSpacing.sm),
                _ThemeSelector(current: state.themeMode),
                const SizedBox(height: AppSpacing.xl),
                const SectionHeader(title: 'Cálculo da rota'),
                const SizedBox(height: AppSpacing.xxs),
                _SectionHint(
                  text: 'Estes dois valores são o que mais mexem na precisão '
                      'do tempo estimado. Ajuste para o seu jeito de trabalhar.',
                ),
                const SizedBox(height: AppSpacing.sm),
                _ServiceTimeCard(minutes: state.serviceTimeMinutes),
                const SizedBox(height: AppSpacing.sm),
                _SpeedCard(kmh: state.averageSpeedKmh),
                const SizedBox(height: AppSpacing.xl),
                const SectionHeader(title: 'Meus dados'),
                const SizedBox(height: AppSpacing.sm),
                const _DataCard(),
                const SizedBox(height: AppSpacing.xl),
                const _AboutCard(),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ThemeSelector extends StatelessWidget {
  final ThemeMode current;

  const _ThemeSelector({required this.current});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SettingsCubit>();

    return Row(
      spacing: AppSpacing.xs,
      children: [
        ThemeOptionCard(
          label: 'Claro',
          preview: AppColors.light,
          isSelected: current == ThemeMode.light,
          onTap: () => cubit.setThemeMode(ThemeMode.light),
        ),
        ThemeOptionCard(
          label: 'Escuro',
          preview: AppColors.dark,
          isSelected: current == ThemeMode.dark,
          onTap: () => cubit.setThemeMode(ThemeMode.dark),
        ),
        ThemeOptionCard(
          label: 'Sistema',
          isSelected: current == ThemeMode.system,
          onTap: () => cubit.setThemeMode(ThemeMode.system),
        ),
      ],
    );
  }
}

/// Tempo de parada, em passos de 1 minuto.
class _ServiceTimeCard extends StatelessWidget {
  final int minutes;

  const _ServiceTimeCard({required this.minutes});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cubit = context.read<SettingsCubit>();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.timer_outlined, size: 19, color: c.textSecondary),
              const SizedBox(width: AppSpacing.xs),
              const Expanded(
                child: Text(
                  'Tempo em cada entrega',
                  style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            'Estacionar, achar o cliente, entregar.',
            style: TextStyle(fontSize: 12.8, color: c.textTertiary),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              _StepButton(
                icon: Icons.remove_rounded,
                onTap: minutes <= 0
                    ? null
                    : () => cubit.setServiceTimeMinutes(minutes - 1),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    minutes == 0 ? 'sem parada' : '$minutes min',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      color: c.textPrimary,
                    ),
                  ),
                ),
              ),
              _StepButton(
                icon: Icons.add_rounded,
                onTap: minutes >= 60
                    ? null
                    : () => cubit.setServiceTimeMinutes(minutes + 1),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SpeedCard extends StatelessWidget {
  final double kmh;

  const _SpeedCard({required this.kmh});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cubit = context.read<SettingsCubit>();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.speed_rounded, size: 19, color: c.textSecondary),
              const SizedBox(width: AppSpacing.xs),
              const Expanded(
                child: Text(
                  'Velocidade média',
                  style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                '${kmh.round()} km/h',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: c.brand,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            'Já contando semáforo e trânsito. Moto em cidade média fica '
            'perto de 28; carro em capital, perto de 20.',
            style: TextStyle(
              fontSize: 12.8,
              color: c.textTertiary,
              height: 1.35,
            ),
          ),
          Slider(
            value: kmh.clamp(5, 80),
            min: 5,
            max: 80,
            divisions: 15,
            label: '${kmh.round()} km/h',
            onChanged: (value) => cubit.setAverageSpeedKmh(value),
          ),
        ],
      ),
    );
  }
}

/// Histórico e backup.
///
/// O backup é a resposta sem servidor para "troquei de celular e perdi tudo":
/// o usuário gera um arquivo e manda para si mesmo. Zero infraestrutura, zero
/// custo, e ele fica dono do próprio backup.
class _DataCard extends StatefulWidget {
  const _DataCard();

  @override
  State<_DataCard> createState() => _DataCardState();
}

class _DataCardState extends State<_DataCard> {
  bool _isBusy = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _Row(
            icon: Icons.history_rounded,
            title: 'Histórico de entregas',
            subtitle: 'O que você já entregou, por dia',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const HistoryPage()),
            ),
          ),
          Divider(height: 1, color: c.border),
          _Row(
            icon: Icons.ios_share_rounded,
            title: 'Exportar meus dados',
            subtitle: 'Gera um arquivo para você guardar ou mandar para si',
            onTap: _isBusy ? null : _export,
          ),
          Divider(height: 1, color: c.border),
          _Row(
            icon: Icons.download_rounded,
            title: 'Importar de um arquivo',
            subtitle: 'Substitui o que está no aparelho pelo do backup',
            onTap: _isBusy ? null : _confirmImport,
          ),
        ],
      ),
    );
  }

  Future<void> _export() async {
    setState(() => _isBusy = true);

    final result = await sl<BackupRepository>().exportToFile();
    if (!mounted) return;
    setState(() => _isBusy = false);

    await result.fold(
      (_) async => _snack('Não foi possível gerar o backup.'),
      (file) async {
        await Share.shareXFiles(
          [XFile(file.path)],
          subject: 'Backup do Routely',
          text: 'Backup das minhas entregas do Routely.',
        );
      },
    );
  }

  Future<void> _confirmImport() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Importar backup?'),
        content: const Text(
          'As entregas e o histórico que estão neste aparelho serão '
          'substituídos pelos do arquivo. Não dá para desfazer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Importar'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final picked = await FilePicker.platform.pickFiles(withData: false);
    final path = picked?.files.singleOrNull?.path;
    if (path == null || !mounted) return;

    setState(() => _isBusy = true);
    final result = await sl<BackupRepository>().importFromFile(File(path));
    if (!mounted) return;
    setState(() => _isBusy = false);

    result.fold(
      (failure) => _snack(
        failure is GeocodingFailure && failure.message.isNotEmpty
            ? failure.message
            : 'Não foi possível importar.',
      ),
      (summary) {
        // A lista precisa refletir o que acabou de entrar.
        context.read<StopsBloc>().add(const StopsLoadRequested());
        _snack(
          '${summary.stops} entregas e ${summary.history} registros '
          'importados.',
        );
      },
    );
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _Row({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Icon(icon, size: 20, color: c.textSecondary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12.5, color: c.textTertiary),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: c.textTertiary),
          ],
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _StepButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = onTap != null;

    return Material(
      color: enabled ? c.surfaceAlt : c.surfaceAlt.withValues(alpha: 0.5),
      borderRadius: AppRadius.smAll,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.smAll,
        child: SizedBox(
          width: 52,
          height: 46,
          child: Icon(
            icon,
            size: 22,
            color: enabled ? c.textPrimary : c.textTertiary,
          ),
        ),
      ),
    );
  }
}

class _SectionHint extends StatelessWidget {
  final String text;

  const _SectionHint({required this.text});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Text(
      text,
      style: TextStyle(fontSize: 12.8, color: c.textTertiary, height: 1.35),
    );
  }
}

class _AboutCard extends StatefulWidget {
  const _AboutCard();

  @override
  State<_AboutCard> createState() => _AboutCardState();
}

class _AboutCardState extends State<_AboutCard> {
  /// Null enquanto ainda não leu. O texto simplesmente não aparece nesse
  /// instante, em vez de piscar um valor de mentira.
  String? _version;

  /// Só o número, sem o build. É o que se compara com a tag do GitHub.
  String? _versionNumber;

  bool _isChecking = false;

  /// Mensagem do resultado da última checagem, e se ela é boa notícia.
  String? _updateMessage;
  bool _updateFound = false;
  String? _updatePageUrl;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  /// Pergunta ao GitHub qual é a última release.
  ///
  /// Só por botão. Checar sozinho ao abrir o app gastaria rede de quem
  /// trabalha com dados limitados para responder algo que quase sempre é
  /// "está atualizado".
  Future<void> _checkForUpdate() async {
    final current = _versionNumber;
    if (_isChecking || current == null) return;

    setState(() {
      _isChecking = true;
      _updateMessage = null;
      _updatePageUrl = null;
    });

    try {
      final result = await sl<UpdateChecker>().check(current);
      if (!mounted) return;

      setState(() {
        _isChecking = false;
        _updateFound = result.hasUpdate;
        _updatePageUrl = result.hasUpdate ? result.pageUrl : null;
        _updateMessage = result.hasUpdate
            ? 'Versão ${result.latest} disponível'
            : 'Você já está na versão mais recente';
      });
    } catch (_) {
      if (!mounted) return;

      // Sem detalhe técnico: o usuário não pode fazer nada com um código de
      // status, e a ação útil é a mesma de sempre — tentar de novo depois.
      setState(() {
        _isChecking = false;
        _updateFound = false;
        _updateMessage = 'Não consegui verificar agora. Tente mais tarde.';
      });
    }
  }

  Future<void> _openReleasePage() async {
    final url = _updatePageUrl;
    if (url == null) return;

    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  /// Lê a versão do pacote instalado, e não uma constante no código.
  ///
  /// Constante escrita à mão sai de sincronia com o `pubspec.yaml` na primeira
  /// vez que alguém esquece de atualizar as duas — e aí a tela que existe para
  /// responder "qual versão você está usando?" passa a mentir. O número do
  /// build vem junto porque duas correções podem sair com o mesmo nome de
  /// versão.
  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _version = 'Versão ${info.version} (${info.buildNumber})';
        _versionNumber = info.version;
      });
    } catch (_) {
      // Sem versão a tela continua útil. Não vale mostrar erro por isso.
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Center(
      child: Column(
        children: [
          Icon(Icons.local_shipping_rounded, size: 26, color: c.textTertiary),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Routely',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
              color: c.textSecondary,
            ),
          ),
          Text(
            'Suas entregas, na melhor ordem.',
            style: TextStyle(fontSize: 12.5, color: c.textTertiary),
          ),
          if (_version != null) ...[
            const SizedBox(height: AppSpacing.xxs),
            SelectableText(
              _version!,
              style: TextStyle(
                fontSize: 12,
                color: c.textTertiary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
          if (AppConfig.checksForUpdates && _versionNumber != null) ...[
            const SizedBox(height: AppSpacing.xs),
            TextButton.icon(
              onPressed: _isChecking ? null : _checkForUpdate,
              icon: _isChecking
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded, size: 18),
              label: Text(
                _isChecking ? 'Verificando…' : 'Buscar atualização',
              ),
            ),
            if (_updateMessage != null) ...[
              Text(
                _updateMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: _updateFound ? FontWeight.w700 : FontWeight.w400,
                  color: _updateFound ? c.success : c.textTertiary,
                ),
              ),
              if (_updateFound) ...[
                const SizedBox(height: AppSpacing.xs),
                // Abre a página da release no navegador em vez de baixar por
                // dentro: instalar APK pelo próprio app exigiria permissão de
                // fonte desconhecida e é justamente o que a Play Store proíbe.
                FilledButton.icon(
                  onPressed: _openReleasePage,
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('Abrir página de download'),
                ),
              ],
            ],
          ],
        ],
      ),
    );
  }
}
