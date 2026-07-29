import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routely/core/error/failures.dart';
import 'package:routely/core/geo/geo_point.dart';
import 'package:routely/features/stops/domain/entities/address_lookup.dart';
import 'package:routely/features/stops/domain/entities/address_query.dart';
import 'package:routely/features/stops/domain/entities/address_suggestion.dart';
import 'package:routely/features/stops/domain/entities/delivery_stop.dart';
import 'package:routely/features/stops/domain/repositories/address_repository.dart';
import 'package:routely/features/stops/domain/repositories/stops_repository.dart';
import 'package:routely/features/stops/domain/usecases/lookup_cep.dart';
import 'package:routely/features/stops/domain/usecases/save_stop.dart';
import 'package:routely/features/stops/presentation/bloc/stop_form_bloc.dart';
import 'package:routely/features/stops/presentation/bloc/stop_form_event.dart';
import 'package:routely/features/stops/presentation/bloc/stop_form_state.dart';

/// Guarda a parada que o formulário mandou salvar, para o teste inspecionar.
class _CapturingStopsRepository implements StopsRepository {
  DeliveryStop? saved;

  /// Simula o geocoding do repositório: só roda quando a parada chega sem
  /// coordenada.
  final GeoPoint? geocodeResult;

  _CapturingStopsRepository({this.geocodeResult});

  @override
  Future<Either<Failure, DeliveryStop>> saveStop(DeliveryStop stop) async {
    final resolved = stop.isRoutable || geocodeResult == null
        ? stop
        : stop.copyWith(coordinate: geocodeResult);
    saved = resolved;
    return Right(resolved);
  }

  @override
  Future<Either<Failure, List<DeliveryStop>>> getStops() async =>
      const Right([]);

  @override
  Future<Either<Failure, void>> deleteStop(String id) async =>
      const Right(null);

  @override
  Future<Either<Failure, DeliveryStop>> setStatus(
    DeliveryStop stop,
    StopStatus status,
  ) async =>
      Right(stop);

  @override
  Future<Either<Failure, int>> clearCompleted() async => const Right(0);

  @override
  Future<Either<Failure, List<DeliveryStop>>>
      resolvePendingCoordinates() async => const Right([]);
}

class _StubAddressRepository implements AddressRepository {
  /// O que o autocomplete devolve.
  final List<AddressSuggestion> suggestions;

  /// Quantas vezes o bloc chegou a consultar. É o número que o debounce
  /// existe para manter baixo.
  int suggestCalls = 0;

  final remembered = <AddressSuggestion>[];

  _StubAddressRepository({this.suggestions = const []});

  @override
  Future<Either<Failure, AddressLookup>> lookupCep(String cep) async {
    return const Right(AddressLookup(
      cep: '01310100',
      street: 'Avenida Paulista',
      neighborhood: 'Bela Vista',
      city: 'São Paulo',
      state: 'SP',
      source: AddressSource.network,
    ));
  }

  @override
  Future<GeoPoint?> coordinateFromDirectory(String cep) async => null;

  @override
  Future<ApproximateLocation?> locateApproximate(AddressQuery query) async =>
      null;

  @override
  Future<List<AddressSuggestion>> suggest(String text, {GeoPoint? bias}) async {
    suggestCalls++;
    return suggestions;
  }

  @override
  Future<void> rememberSuggestion(AddressSuggestion suggestion) async {
    remembered.add(suggestion);
  }
}

const _pinned = GeoPoint(latitude: -23.5613, longitude: -46.6560);
const _geocoded = GeoPoint(latitude: -23.5000, longitude: -46.6000);
const _suggested = GeoPoint(latitude: -23.5614, longitude: -46.6558);

DeliveryStop _existing({GeoPoint? coordinate}) => DeliveryStop(
      id: 'stop-1',
      street: 'Avenida Paulista',
      number: '1578',
      city: 'São Paulo',
      state: 'SP',
      cep: '01310100',
      coordinate: coordinate,
      createdAt: DateTime(2026, 7, 1),
    );

const _submit = StopFormSubmitted(
  street: 'Avenida Paulista',
  number: '1578',
  city: 'São Paulo',
  state: 'SP',
  cep: '01310100',
);

void main() {
  late _CapturingStopsRepository stopsRepository;
  late StopFormBloc bloc;

  void buildBloc({
    GeoPoint? geocodeResult,
    _StubAddressRepository? addresses,
    // Testar o valor real do debounce é assunto do teste do debounce; nos
    // outros ele só atrasaria tudo.
    Duration debounce = Duration.zero,
  }) {
    stopsRepository = _CapturingStopsRepository(geocodeResult: geocodeResult);
    final addressRepository = addresses ?? _StubAddressRepository();
    bloc = StopFormBloc(
      lookupCep: LookupCep(addressRepository),
      saveStop: SaveStop(stopsRepository),
      addressRepository: addressRepository,
      suggestionDebounce: debounce,
    );
  }

  tearDown(() => bloc.close());

  group('autocomplete', () {
    final suggestion = AddressSuggestion(
      label: 'Avenida Paulista, 1578',
      detail: 'Bela Vista · São Paulo · SP',
      query: const AddressQuery(
        cep: '01310100',
        street: 'Avenida Paulista',
        number: '1578',
        city: 'São Paulo',
        state: 'SP',
      ),
      point: _suggested,
      precision: LocationPrecision.exact,
    );

    // O ponto do debounce: digitar "Avenida Paulista" são 16 teclas. Sem
    // esperar, seriam 16 consultas pagas para um endereço só.
    test('digitação seguida vira uma consulta só', () async {
      final addresses = _StubAddressRepository();
      buildBloc(
        addresses: addresses,
        debounce: const Duration(milliseconds: 60),
      );

      for (final text in ['Aven', 'Avenid', 'Avenida', 'Avenida Pau']) {
        bloc.add(AddressTextChanged(text));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(addresses.suggestCalls, 1);
    });

    test('parar e digitar de novo consulta duas vezes', () async {
      final addresses = _StubAddressRepository();
      buildBloc(
        addresses: addresses,
        debounce: const Duration(milliseconds: 40),
      );

      bloc.add(const AddressTextChanged('Avenida Paulista'));
      await Future<void>.delayed(const Duration(milliseconds: 90));
      bloc.add(const AddressTextChanged('Rua Augusta'));
      await Future<void>.delayed(const Duration(milliseconds: 90));

      expect(addresses.suggestCalls, 2);
    });

    test('as sugestões chegam ao estado', () async {
      final addresses = _StubAddressRepository(suggestions: [suggestion]);
      buildBloc(addresses: addresses);

      bloc.add(const AddressTextChanged('Avenida Paulista'));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(bloc.state.suggestions, [suggestion]);
      expect(bloc.state.isSuggesting, isFalse);
    });

    // A sugestão já traz a coordenada. Consultar de novo o mesmo endereço para
    // descobrir o que ela respondeu seria pagar duas vezes pela mesma coisa.
    test('escolher uma sugestão dispensa o geocoding ao salvar', () async {
      final addresses = _StubAddressRepository(suggestions: [suggestion]);
      buildBloc(addresses: addresses, geocodeResult: _geocoded);

      bloc.add(const StopFormStarted());
      bloc.add(AddressSuggestionSelected(suggestion));
      bloc.add(_submit);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(stopsRepository.saved?.coordinate, _suggested);
      expect(addresses.remembered, [suggestion]);
    });

    test('escolher uma sugestão fecha a lista', () async {
      final addresses = _StubAddressRepository(suggestions: [suggestion]);
      buildBloc(addresses: addresses);

      bloc.add(const AddressTextChanged('Avenida Paulista'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      bloc.add(AddressSuggestionSelected(suggestion));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(bloc.state.suggestions, isEmpty);
    });

    // Editar a rua depois de escolher significa que o texto não descreve mais
    // o lugar que o serviço devolveu. Manter a coordenada salvaria a parada no
    // endereço anterior.
    test('editar a rua depois descarta a coordenada da sugestão', () async {
      final addresses = _StubAddressRepository(suggestions: [suggestion]);
      buildBloc(addresses: addresses);

      bloc.add(AddressSuggestionSelected(suggestion));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(bloc.state.suggestedCoordinate, _suggested);

      bloc.add(const AddressTextChanged('Avenida Paulist'));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(bloc.state.suggestedCoordinate, isNull);
    });

    // O pino é o usuário olhando para a porta; a sugestão é um palpite de
    // serviço. Quando os dois existem, o pino vence.
    test('o pino marcado no mapa vence a sugestão', () async {
      final addresses = _StubAddressRepository(suggestions: [suggestion]);
      buildBloc(addresses: addresses);

      bloc.add(const StopFormStarted());
      bloc.add(AddressSuggestionSelected(suggestion));
      bloc.add(const StopLocationPicked(_pinned));
      bloc.add(_submit);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(stopsRepository.saved?.coordinate, _pinned);
    });
  });

  group('coordenada marcada no mapa', () {
    test('entra no estado e vira a coordenada efetiva', () async {
      buildBloc();
      bloc.add(const StopFormStarted());
      bloc.add(const StopLocationPicked(_pinned));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.pickedCoordinate, _pinned);
      expect(bloc.state.effectiveCoordinate, _pinned);
      expect(bloc.state.hasCoordinate, isTrue);
    });

    // O ponto central: quem marcou o pino estava olhando para a porta.
    test('vence o geocoding ao salvar', () async {
      buildBloc(geocodeResult: _geocoded);

      bloc.add(const StopFormStarted());
      bloc.add(const StopLocationPicked(_pinned));
      bloc.add(_submit);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(stopsRepository.saved?.coordinate, _pinned);
      expect(bloc.state.status, StopFormStatus.saved);
      expect(bloc.state.savedWithoutCoordinate, isFalse);
    });

    test('vence a coordenada que a parada já tinha', () async {
      buildBloc();

      bloc.add(StopFormStarted(existing: _existing(coordinate: _geocoded)));
      bloc.add(const StopLocationPicked(_pinned));
      bloc.add(_submit);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(stopsRepository.saved?.coordinate, _pinned);
    });

    test('preserva o id ao editar', () async {
      buildBloc();

      bloc.add(StopFormStarted(existing: _existing(coordinate: _geocoded)));
      bloc.add(const StopLocationPicked(_pinned));
      bloc.add(_submit);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(stopsRepository.saved?.id, 'stop-1');
    });
  });

  group('sem pino marcado', () {
    test('mantém a coordenada quando o endereço não mudou', () async {
      buildBloc();

      bloc.add(StopFormStarted(existing: _existing(coordinate: _geocoded)));
      bloc.add(_submit);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(stopsRepository.saved?.coordinate, _geocoded);
    });

    test('descarta a coordenada quando o endereço muda', () async {
      buildBloc();

      bloc.add(StopFormStarted(existing: _existing(coordinate: _geocoded)));
      bloc.add(const StopFormSubmitted(
        street: 'Rua Augusta',
        number: '900',
        city: 'São Paulo',
        state: 'SP',
        cep: '01310100',
      ));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(
        stopsRepository.saved?.coordinate,
        isNull,
        reason: 'endereço novo precisa ser geocodificado de novo',
      );
    });

    test('avisa quando salvou sem conseguir localizar', () async {
      buildBloc();

      bloc.add(const StopFormStarted());
      bloc.add(_submit);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(bloc.state.savedWithoutCoordinate, isTrue);
      expect(stopsRepository.saved?.isRoutable, isFalse);
    });
  });

  group('estado inicial', () {
    test('formulário novo não tem coordenada', () async {
      buildBloc();
      bloc.add(const StopFormStarted());
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.hasCoordinate, isFalse);
      expect(bloc.state.effectiveCoordinate, isNull);
    });

    test('edição já começa com a coordenada da parada', () async {
      buildBloc();
      bloc.add(StopFormStarted(existing: _existing(coordinate: _geocoded)));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.effectiveCoordinate, _geocoded);
      expect(bloc.state.pickedCoordinate, isNull);
    });
  });
}
