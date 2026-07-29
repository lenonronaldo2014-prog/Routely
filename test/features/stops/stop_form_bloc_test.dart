import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routely/core/error/failures.dart';
import 'package:routely/core/geo/geo_point.dart';
import 'package:routely/features/stops/domain/entities/address_lookup.dart';
import 'package:routely/features/stops/domain/entities/address_query.dart';
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
  Future<Either<Failure, GeoPoint>> geocode(String fullAddress) async =>
      Left(GeocodingFailure('não usado'));

  @override
  Future<GeoPoint?> coordinateFromDirectory(String cep) async => null;

  @override
  Future<ApproximateLocation?> locateApproximate(AddressQuery query) async =>
      null;
}

const _pinned = GeoPoint(latitude: -23.5613, longitude: -46.6560);
const _geocoded = GeoPoint(latitude: -23.5000, longitude: -46.6000);

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

  void buildBloc({GeoPoint? geocodeResult}) {
    stopsRepository = _CapturingStopsRepository(geocodeResult: geocodeResult);
    bloc = StopFormBloc(
      lookupCep: LookupCep(_StubAddressRepository()),
      saveStop: SaveStop(stopsRepository),
    );
  }

  tearDown(() => bloc.close());

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
