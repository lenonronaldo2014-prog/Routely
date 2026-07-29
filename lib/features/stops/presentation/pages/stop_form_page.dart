import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/geo/geo_point.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/util/cep_formatter.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/responsive_body.dart';
import '../../../../injection_container.dart';
import '../../domain/entities/address_lookup.dart';
import '../../domain/entities/address_query.dart';
import '../../domain/entities/address_suggestion.dart';
import '../../domain/entities/delivery_stop.dart';
import '../../domain/entities/scanned_address.dart';
import '../bloc/stop_form_bloc.dart';
import '../bloc/stop_form_event.dart';
import '../bloc/stop_form_state.dart';
import 'location_picker_page.dart';

class StopFormPage extends StatelessWidget {
  final DeliveryStop? existing;

  /// Preenchimento vindo da leitura de uma etiqueta. Chega como sugestão: o
  /// formulário abre preenchido e com um aviso pedindo conferência.
  final ScannedAddress? scanned;

  const StopFormPage({super.key, this.existing, this.scanned});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          sl<StopFormBloc>()..add(StopFormStarted(existing: existing)),
      child: _StopFormView(existing: existing, scanned: scanned),
    );
  }
}

class _StopFormView extends StatefulWidget {
  final DeliveryStop? existing;
  final ScannedAddress? scanned;

  const _StopFormView({this.existing, this.scanned});

  @override
  State<_StopFormView> createState() => _StopFormViewState();
}

class _StopFormViewState extends State<_StopFormView> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _label;
  late final TextEditingController _cep;
  late final TextEditingController _street;
  late final TextEditingController _number;
  late final TextEditingController _complement;
  late final TextEditingController _neighborhood;
  late final TextEditingController _city;
  late final TextEditingController _state;
  late final TextEditingController _notes;

  final _numberFocus = FocusNode();
  final _streetFocus = FocusNode();

  /// Evita disparar a mesma consulta várias vezes enquanto o usuário mexe no
  /// campo depois que ele já completou os 8 dígitos.
  String? _lastLookedUpCep;

  /// Ligado enquanto o app escreve nos campos.
  ///
  /// Preencher a rua a partir do CEP ou de uma sugestão dispararia o listener
  /// como se o usuário tivesse digitado, e o app pediria sugestões para um
  /// endereço que ele mesmo acabou de resolver — chamada paga por nada.
  bool _fillingFields = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final scan = widget.scanned;

    // A etiqueta lida preenche o que a parada ainda não tem. Edição de uma
    // parada existente tem precedência: quem abriu para editar não quer o
    // campo trocado por baixo.
    _label = TextEditingController(text: e?.label ?? scan?.recipient ?? '');
    _cep = TextEditingController(
      text: _maskedCep(e?.cep ?? scan?.cep),
    );
    _street = TextEditingController(text: e?.street ?? scan?.street ?? '');
    _number = TextEditingController(text: e?.number ?? scan?.number ?? '');
    _complement =
        TextEditingController(text: e?.complement ?? scan?.complement ?? '');
    _neighborhood = TextEditingController(
      text: e?.neighborhood ?? scan?.neighborhood ?? '',
    );
    _city = TextEditingController(text: e?.city ?? scan?.city ?? '');
    _state = TextEditingController(text: e?.state ?? scan?.state ?? '');
    _notes = TextEditingController(text: e?.notes ?? '');

    // Marca o CEP da etiqueta como já consultado: ele acabou de vir preenchido
    // e disparar a busca por cima sobrescreveria o que foi lido.
    _lastLookedUpCep = e?.cep ?? scan?.cep;
    _cep.addListener(_onCepChanged);
    _street.addListener(_onStreetChanged);
  }

  String _maskedCep(String? cep) =>
      cep == null || cep.isEmpty ? '' : CepFormatter.mask(cep);

  @override
  void dispose() {
    _cep.removeListener(_onCepChanged);
    _street.removeListener(_onStreetChanged);
    for (final c in [
      _label,
      _cep,
      _street,
      _number,
      _complement,
      _neighborhood,
      _city,
      _state,
      _notes,
    ]) {
      c.dispose();
    }
    _numberFocus.dispose();
    _streetFocus.dispose();
    super.dispose();
  }

  /// Busca assim que os 8 dígitos estão completos — sem botão "buscar".
  /// Uma interação a menos num app usado com pressa.
  void _onCepChanged() {
    final digits = CepFormatter.normalize(_cep.text);

    if (digits.length != 8) {
      _lastLookedUpCep = null;
      return;
    }
    if (digits == _lastLookedUpCep) return;

    _lastLookedUpCep = digits;
    context.read<StopFormBloc>().add(CepLookupRequested(digits));
  }

  /// Pede sugestões enquanto o usuário digita a rua.
  ///
  /// O bloc é que espera a digitação parar. A tela só avisa que mudou — se
  /// tentasse decidir aqui, o cancelamento teria que ser refeito em cada campo
  /// que mexe no endereço.
  void _onStreetChanged() {
    if (_fillingFields) return;
    context.read<StopFormBloc>().add(AddressTextChanged(_suggestionText()));
  }

  /// Junta cidade e UF ao que foi digitado, quando já se sabe.
  ///
  /// Sem isso, "Rua São João" devolve as de todo o Brasil e a certa
  /// dificilmente estaria entre as cinco primeiras. Como o CEP costuma ser
  /// preenchido antes, na prática a busca quase sempre já sai restrita à
  /// cidade certa.
  String _suggestionText() {
    final street = _street.text.trim();
    if (street.isEmpty) return '';

    return [
      street,
      if (_city.text.trim().isNotEmpty) _city.text.trim(),
      if (_state.text.trim().isNotEmpty) _state.text.trim(),
    ].join(', ');
  }

  /// Preenche o formulário com a sugestão escolhida.
  ///
  /// A coordenada dela vai junto para o bloc, e é isso que evita uma segunda
  /// consulta: o endereço já está localizado no momento da escolha.
  ///
  /// Bairro, cidade, UF e CEP são **substituídos**, inclusive quando a
  /// sugestão vem sem eles. Manter o que estava faria o endereço misturar duas
  /// origens: numa troca de rua, o bairro da anterior ficaria para trás e a
  /// entrega seria salva com uma localidade que não é a dela.
  ///
  /// O número é a exceção — vem da etiqueta do pacote, não do mapa. Uma
  /// sugestão de nível rua não traz número, e apagar o que o usuário já digitou
  /// o obrigaria a redigitar.
  void _applySuggestion(AddressSuggestion suggestion) {
    final q = suggestion.query;

    _fillingFields = true;

    if (q.hasStreet) _street.text = q.street!;
    if ((q.number ?? '').isNotEmpty) _number.text = q.number!;

    _neighborhood.text = q.neighborhood?.trim() ?? '';
    _city.text = q.city?.trim() ?? '';
    _state.text = q.state?.trim() ?? '';

    final cep = q.normalizedCep;
    if (cep != null) {
      // Marca como já consultado antes de escrever: o listener do CEP dispara
      // na atribuição e a busca sobrescreveria estes campos com o resultado do
      // ViaCEP, desfazendo a escolha do usuário.
      _lastLookedUpCep = cep;
      _cep.text = CepFormatter.mask(cep);
    }

    _fillingFields = false;

    context.read<StopFormBloc>().add(AddressSuggestionSelected(suggestion));

    // O número é o que a sugestão mais costuma não trazer.
    _numberFocus.requestFocus();
  }

  void _applyLookup(StopFormState state) {
    final lookup = state.cepResult;
    if (lookup == null) return;

    _fillingFields = true;

    if (lookup.hasStreet) _street.text = lookup.street;
    if (lookup.neighborhood.isNotEmpty) _neighborhood.text = lookup.neighborhood;
    if (lookup.hasCity) _city.text = lookup.city;
    _state.text = lookup.state;

    _fillingFields = false;

    // Resultado parcial (só a UF, deduzida da faixa): o logradouro é o que
    // falta, então o cursor vai para lá em vez do número.
    if (lookup.source.isPartial) {
      _streetFocus.requestFocus();
      return;
    }

    // O número é a única coisa que o CEP não traz, então mandamos o cursor
    // direto para lá.
    _numberFocus.requestFocus();
  }

  /// Abre o mapa no endereço que está digitado agora.
  ///
  /// Passar só a coordenada salva não bastava: se o usuário trocou o endereço,
  /// o mapa abria no ponto antigo e ele tinha que procurar o lugar na mão. O
  /// endereço digitado vai junto para a tela do mapa poder localizá-lo.
  Future<void> _openMap(StopFormState state) async {
    final bloc = context.read<StopFormBloc>();

    final label = [
      _street.text.trim(),
      if (_number.text.trim().isNotEmpty) _number.text.trim(),
    ].where((part) => part.isNotEmpty).join(', ');

    final picked = await Navigator.of(context).push<GeoPoint>(
      MaterialPageRoute(
        builder: (_) => LocationPickerPage(
          // Só o pino marcado à mão tem prioridade sobre o endereço digitado.
          initial: state.pickedCoordinate,
          fallback: state.existing?.coordinate,
          query: _typedQuery(),
          addressLabel: label,
        ),
      ),
    );

    if (picked != null) bloc.add(StopLocationPicked(picked));
  }

  /// Monta o endereço com o que está nos campos agora — não o que foi salvo.
  ///
  /// Os campos vão separados porque a tela do mapa afrouxa a busca em degraus
  /// quando o endereço exato não é encontrado, e para isso precisa saber qual
  /// parte é rua, qual é bairro e qual é cidade.
  AddressQuery _typedQuery() => AddressQuery(
        cep: CepFormatter.normalize(_cep.text),
        street: _street.text.trim(),
        number: _number.text.trim(),
        neighborhood: _neighborhood.text.trim(),
        city: _city.text.trim(),
        state: _state.text.trim(),
      );

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    context.read<StopFormBloc>().add(StopFormSubmitted(
          label: _label.text,
          street: _street.text,
          number: _number.text,
          complement: _complement.text,
          neighborhood: _neighborhood.text,
          city: _city.text,
          state: _state.text,
          cep: CepFormatter.normalize(_cep.text),
          notes: _notes.text,
        ));
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;

    return BlocConsumer<StopFormBloc, StopFormState>(
      listenWhen: (previous, current) =>
          previous.cepResult != current.cepResult ||
          previous.status != current.status ||
          previous.saveError != current.saveError,
      listener: (context, state) {
        if (state.cepResult != null) _applyLookup(state);

        if (state.status == StopFormStatus.saved) {
          if (state.savedWithoutCoordinate) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(const SnackBar(
                duration: Duration(seconds: 4),
                content: Text(
                  'Entrega salva, mas sem localização no mapa. '
                  'Ela não entra na rota até você atualizar com internet.',
                ),
              ));
          }
          Navigator.of(context).pop(true);
        }

        if (state.saveError != null) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(state.saveError!)));
        }
      },
      builder: (context, state) {
        final isSaving = state.status == StopFormStatus.saving;

        return Scaffold(
          appBar: AppBar(
            title: Text(isEditing ? 'Editar entrega' : 'Nova entrega'),
          ),
          body: Form(
            key: _formKey,
            child: ResponsiveBody(
              child: ListView(
                padding: const EdgeInsets.only(
                  top: AppSpacing.xs,
                  bottom: AppSpacing.bottomActionInset,
                ),
                children: [
                  if (widget.scanned != null) ...[
                    _ScanReviewBanner(scanned: widget.scanned!),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                  _FormSection(
                    title: 'Endereço',
                    children: [
                      _cepField(state),
                      const SizedBox(height: AppSpacing.sm),
                      _streetField(state),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 2,
                            child: _field(
                              controller: _number,
                              label: 'Número',
                              focusNode: _numberFocus,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            flex: 3,
                            child: _field(
                              controller: _complement,
                              label: 'Complemento',
                              hint: 'Apto, bloco…',
                              textCapitalization: TextCapitalization.sentences,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _field(
                        controller: _neighborhood,
                        label: 'Bairro',
                        textCapitalization: TextCapitalization.words,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: _field(
                              controller: _city,
                              label: 'Cidade',
                              textCapitalization: TextCapitalization.words,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: _field(
                              controller: _state,
                              label: 'UF',
                              textCapitalization:
                                  TextCapitalization.characters,
                              maxLength: 2,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _LocationSection(
                    state: state,
                    onAdjust: () => _openMap(state),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _FormSection(
                    title: 'Detalhes',
                    subtitle: 'Opcional, mas ajuda na hora de entregar',
                    children: [
                      _field(
                        controller: _label,
                        label: 'Apelido',
                        hint: 'Ex.: Pedido 4821, Cliente Maria',
                        textCapitalization: TextCapitalization.sentences,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _field(
                        controller: _notes,
                        label: 'Observações',
                        hint: 'Portão azul, falar com o porteiro…',
                        maxLines: 3,
                        textCapitalization: TextCapitalization.sentences,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          bottomNavigationBar: ResponsiveActionBar(
            child: ElevatedButton(
              onPressed: isSaving ? null : _submit,
              child: isSaving
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      isEditing ? 'Salvar alterações' : 'Adicionar entrega',
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _cepField(StopFormState state) {
    final c = context.colors;
    final result = state.cepResult;
    final isPartial = result?.source.isPartial ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _cep,
          keyboardType: TextInputType.number,
          inputFormatters: [_CepInputFormatter()],
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
          decoration: InputDecoration(
            labelText: 'CEP',
            hintText: '00000-000',
            helperText: result == null
                ? 'Preenche rua, bairro e cidade sozinho'
                : _helperFor(result.source),
            helperStyle: result == null
                ? null
                : TextStyle(
                    color: isPartial ? c.warning : c.success,
                    fontWeight: FontWeight.w600,
                  ),
            errorText: state.cepError,
            prefixIcon: Icon(Icons.markunread_mailbox_outlined,
                size: 20, color: c.textTertiary),
            suffixIcon: state.isLookingUpCep
                ? const Padding(
                    padding: EdgeInsets.all(15),
                    child: SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  )
                : result == null
                    ? null
                    : Icon(
                        isPartial
                            ? Icons.error_outline_rounded
                            : Icons.check_circle_rounded,
                        color: isPartial ? c.warning : c.success,
                      ),
          ),
        ),
        if (isPartial) ...[
          const SizedBox(height: AppSpacing.xs),
          const InfoBanner(
            icon: Icons.wifi_off_rounded,
            tone: BannerTone.warning,
            title: 'Só deu para identificar o estado',
            message: 'Sem internet e sem a base deste estado instalada. '
                'Digite a rua e a cidade — a entrega é salva do mesmo jeito.',
          ),
        ],
      ],
    );
  }

  String _helperFor(AddressSource source) => switch (source) {
        AddressSource.localDirectory => 'Preenchido pela base offline',
        AddressSource.cache => 'Preenchido de uma consulta anterior',
        AddressSource.network => 'Endereço preenchido automaticamente',
        AddressSource.cepRange => 'Complete a rua e a cidade',
      };

  /// Campo de rua com as sugestões logo abaixo.
  ///
  /// A lista fica no fluxo da página, e não flutuando por cima: dentro de um
  /// `ListView` uma camada sobreposta desalinha assim que o usuário rola, e
  /// aqui ela sempre aparece com o campo à vista porque o teclado acabou de
  /// empurrar a tela para cima.
  Widget _streetField(StopFormState state) {
    final c = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _street,
          focusNode: _streetFocus,
          textCapitalization: TextCapitalization.words,
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'Informe a rua' : null,
          decoration: InputDecoration(
            labelText: 'Rua / Avenida',
            counterText: '',
            suffixIcon: state.isSuggesting
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
          ),
        ),
        if (state.suggestions.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xxs),
          Container(
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: AppRadius.mdAll,
              border: Border.all(color: c.border),
            ),
            child: Column(
              children: [
                for (final suggestion in state.suggestions)
                  _SuggestionTile(
                    suggestion: suggestion,
                    onTap: () => _applySuggestion(suggestion),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? hint,
    FocusNode? focusNode,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
    int maxLines = 1,
    int? maxLength,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      maxLines: maxLines,
      maxLength: maxLength,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        counterText: '',
      ),
    );
  }
}

/// Uma opção do autocomplete.
///
/// A segunda linha (bairro, cidade, UF, CEP) não é enfeite: nomes de rua se
/// repetem muito entre cidades, e sem ela o usuário escolheria a errada sem
/// perceber.
class _SuggestionTile extends StatelessWidget {
  final AddressSuggestion suggestion;
  final VoidCallback onTap;

  const _SuggestionTile({required this.suggestion, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.mdAll,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          children: [
            Icon(Icons.place_outlined, size: 19, color: c.textTertiary),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    suggestion.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (suggestion.detail.isNotEmpty)
                    Text(
                      suggestion.detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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

/// Aviso de que os campos vieram de uma foto e precisam de conferência.
///
/// Nunca some sozinho e nunca some sem o usuário olhar: OCR errado que vira
/// entrega errada destrói a confiança no app inteiro. Um segundo conferindo
/// vale o roteiro do dia.
class _ScanReviewBanner extends StatelessWidget {
  final ScannedAddress scanned;

  const _ScanReviewBanner({required this.scanned});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isConfident = scanned.confidence == ScanConfidence.labelled;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isConfident
            ? c.brandSoft
            : c.warning.withValues(alpha: 0.12),
        borderRadius: AppRadius.mdAll,
        border: Border.all(
          color: isConfident
              ? c.brand.withValues(alpha: 0.3)
              : c.warning.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.document_scanner_rounded,
            size: 19,
            color: isConfident ? c.brand : c.warning,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isConfident
                      ? 'Lido da etiqueta — confira'
                      : 'Leitura parcial — complete o que faltou',
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isConfident
                      ? 'Dê uma olhada no número e no complemento antes de '
                          'salvar. É onde a foto costuma errar.'
                      : 'Não achei todos os campos. Preencha os que estão '
                          'vazios.',
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
    );
  }
}

/// Estado da localização da entrega, com a saída manual sempre à mão.
///
/// Não fica escondida atrás de um erro: mesmo quando o geocoding acerta, o
/// ponto pode cair no meio da quadra ou no portão errado do condomínio. Quem
/// conhece o endereço é o entregador.
class _LocationSection extends StatelessWidget {
  final StopFormState state;
  final VoidCallback onAdjust;

  const _LocationSection({required this.state, required this.onAdjust});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    final isManual = state.pickedCoordinate != null;
    final hasCoordinate = state.hasCoordinate;

    final (icon, title, message, tone) = switch ((hasCoordinate, isManual)) {
      (true, true) => (
          Icons.push_pin_rounded,
          'Ponto marcado no mapa',
          'É esta coordenada que vai para a rota.',
          c.success,
        ),
      (true, false) => (
          Icons.place_rounded,
          'Localização encontrada',
          'Se o ponto não estiver na porta certa, ajuste no mapa.',
          c.textSecondary,
        ),
      _ => (
          Icons.location_off_outlined,
          'Sem localização',
          'Vamos tentar localizar ao salvar. Se não achar, marque no mapa — '
              'entrega sem ponto fica de fora da rota.',
          c.warning,
        ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Localização'),
        const SizedBox(height: AppSpacing.sm),
        AppCard(
          borderColor: hasCoordinate ? c.border : c.warning.withValues(alpha: 0.5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 19, color: tone),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          message,
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
              if (hasCoordinate) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${state.effectiveCoordinate!.latitude.toStringAsFixed(5)}, '
                  '${state.effectiveCoordinate!.longitude.toStringAsFixed(5)}',
                  style: TextStyle(fontSize: 12, color: c.textTertiary),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: onAdjust,
                icon: const Icon(Icons.map_outlined, size: 19),
                label: Text(
                  hasCoordinate ? 'Ajustar no mapa' : 'Marcar no mapa',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Agrupa campos relacionados sob um título. Quebra o formulário em blocos
/// digeríveis em vez de uma pilha única de dez caixas iguais.
class _FormSection extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;

  const _FormSection({
    required this.title,
    this.subtitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: title),
        if (subtitle != null) ...[
          const SizedBox(height: 3),
          Text(
            subtitle!,
            style: TextStyle(fontSize: 12.8, color: c.textTertiary),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        ...children,
      ],
    );
  }
}

/// Aplica a máscara 00000-000 enquanto o usuário digita.
class _CepInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = CepFormatter.normalize(newValue.text);
    if (digits.length > 8) return oldValue;

    final masked = CepFormatter.mask(digits);
    return TextEditingValue(
      text: masked,
      selection: TextSelection.collapsed(offset: masked.length),
    );
  }
}
