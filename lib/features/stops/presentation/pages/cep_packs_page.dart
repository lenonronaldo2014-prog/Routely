import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/util/cep_range_resolver.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/responsive_body.dart';
import '../../../../injection_container.dart';
import '../../domain/entities/cep_pack.dart';
import '../cubit/cep_packs_cubit.dart';

/// Gerencia as bases de CEP instaladas no aparelho.
///
/// É o que transforma "funciona offline pro que você já usou" em "funciona
/// offline de verdade": com a base do estado instalada, qualquer CEP daquele
/// estado resolve sem rede, mesmo nunca tendo sido consultado antes.
class CepPacksPage extends StatelessWidget {
  const CepPacksPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<CepPacksCubit>()..load(),
      child: const _CepPacksView(),
    );
  }
}

class _CepPacksView extends StatelessWidget {
  const _CepPacksView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bases offline')),
      body: BlocConsumer<CepPacksCubit, CepPacksState>(
        listenWhen: (previous, current) =>
            previous.error != current.error ||
            previous.lastImported != current.lastImported,
        listener: (context, state) {
          final messenger = ScaffoldMessenger.of(context);

          if (state.error != null) {
            messenger
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text(state.error!)));
            return;
          }

          if (state.lastImported != null) {
            messenger
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(
                content: Text(
                  '${_formatCount(state.lastImported!)} CEPs instalados.',
                ),
              ));
          }
        },
        builder: (context, state) {
          if (state.isImporting) return _ImportingView(state: state);

          return ResponsiveBody(
            child: ListView(
              padding: const EdgeInsets.only(
                top: AppSpacing.xs,
                bottom: AppSpacing.bottomActionInset,
              ),
              children: [
                const _Explanation(),
                const SizedBox(height: AppSpacing.lg),
                SectionHeader(
                  title: 'Instaladas',
                  count: state.packs.isEmpty ? null : state.packs.length,
                ),
                const SizedBox(height: AppSpacing.sm),
                if (state.isLoading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacing.xl),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (state.packs.isEmpty)
                  const _EmptyPacks()
                else
                  ...state.packs.map((pack) => Padding(
                        padding:
                            const EdgeInsets.only(bottom: AppSpacing.sm - 2),
                        child: _PackTile(pack: pack),
                      )),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: BlocBuilder<CepPacksCubit, CepPacksState>(
        builder: (context, state) {
          if (state.isImporting) return const SizedBox.shrink();

          return ResponsiveActionBar(
            child: ElevatedButton.icon(
              onPressed: () => _startImport(context),
              icon: const Icon(Icons.download_rounded),
              label: const Text('Instalar base de um estado'),
            ),
          );
        },
      ),
    );
  }

  Future<void> _startImport(BuildContext context) async {
    final cubit = context.read<CepPacksCubit>();

    final uf = await _pickState(context);
    if (uf == null) return;

    final picked = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: false,
    );

    final path = picked?.files.singleOrNull?.path;
    if (path == null) return;

    await cubit.import(state_: uf, file: File(path));
  }

  Future<String?> _pickState(BuildContext context) {
    final ufs = CepRangeResolver.ranges.map((r) => r.uf).toSet().toList()
      ..sort();

    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Text(
                'De qual estado é o arquivo?',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Flexible(
              child: GridView.count(
                shrinkWrap: true,
                crossAxisCount: 4,
                childAspectRatio: 2.1,
                padding: const EdgeInsets.all(AppSpacing.md),
                mainAxisSpacing: AppSpacing.xs,
                crossAxisSpacing: AppSpacing.xs,
                children: [
                  for (final uf in ufs)
                    OutlinedButton(
                      onPressed: () => Navigator.of(sheetContext).pop(uf),
                      child: Text(uf),
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

class _Explanation extends StatelessWidget {
  const _Explanation();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const InfoBanner(
          icon: Icons.wifi_off_rounded,
          title: 'Para o CEP funcionar sem internet',
          message: 'Com a base do seu estado instalada, qualquer CEP dele '
              'preenche o endereço na hora — mesmo sem sinal e mesmo que você '
              'nunca tenha consultado aquele CEP antes.',
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'FORMATO DO ARQUIVO',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
            color: c.textTertiary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: c.surfaceAlt,
            borderRadius: AppRadius.smAll,
          ),
          child: Text(
            'cep;logradouro;bairro;cidade;uf\n'
            '01001-000;Praça da Sé;Sé;São Paulo;SP',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11.5,
              height: 1.5,
              color: c.textSecondary,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Um CEP por linha. Linhas em branco e começadas com # são ignoradas.',
          style: TextStyle(fontSize: 12.5, color: c.textTertiary, height: 1.35),
        ),
      ],
    );
  }
}

class _PackTile extends StatelessWidget {
  final CepPack pack;

  const _PackTile({required this.pack});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return AppCard(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.brandSoft,
              borderRadius: AppRadius.smAll,
            ),
            child: Text(
              pack.state,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: c.brand,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_formatCount(pack.entryCount)} CEPs',
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Instalada em ${_formatDate(pack.importedAt)}',
                  style: TextStyle(fontSize: 12.5, color: c.textTertiary),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remover base',
            icon: const Icon(Icons.delete_outline_rounded),
            color: c.textTertiary,
            onPressed: () => _confirmRemove(context),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRemove(BuildContext context) async {
    final cubit = context.read<CepPacksCubit>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remover a base de ${pack.state}?'),
        content: const Text(
          'Os CEPs desse estado voltam a depender de internet. '
          'As entregas já cadastradas não mudam.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );

    if (confirmed == true) await cubit.remove(pack.state);
  }
}

class _ImportingView extends StatelessWidget {
  final CepPacksState state;

  const _ImportingView({required this.state});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Center(
      child: ResponsiveBody(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: AppSpacing.xl),
            Text(
              'Instalando a base de ${state.importingState}…',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${_formatCount(state.importedCount)} CEPs gravados',
              style: TextStyle(fontSize: 14, color: c.textSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Pode levar alguns minutos. Não feche o app.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: c.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyPacks extends StatelessWidget {
  const _EmptyPacks();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: AppRadius.mdAll,
      ),
      child: Column(
        children: [
          Icon(Icons.inbox_rounded, size: 34, color: c.textTertiary),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Nenhuma base instalada',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: c.textSecondary,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Sem internet, o app ainda identifica o estado pelo número do CEP.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.8, color: c.textTertiary, height: 1.35),
          ),
        ],
      ),
    );
  }
}

String _formatCount(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();

  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

String _formatDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/'
    '${date.month.toString().padLeft(2, '0')}/${date.year}';
