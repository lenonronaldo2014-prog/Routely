import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:routely/core/error/failures.dart';
import 'package:routely/features/location/data/repositories/location_repository_impl.dart';

Position _position(double lat, double lng) => Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime(2026, 7, 1),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

/// Geolocator controlável. `Completer` sem completar simula o caso que motivou
/// o teste: no aparelho, `getCurrentPosition` ficou pendurado e a tela do mapa
/// girou para sempre.
class _FakeGeolocator extends GeolocatorPlatform {
  bool serviceEnabled;
  LocationPermission permission;

  /// Quando true, `getCurrentPosition` nunca completa.
  bool hangCurrentPosition;

  /// Quando true, `getLastKnownPosition` nunca completa.
  bool hangLastKnown;

  Position? currentPosition;
  Position? lastKnownPosition;

  _FakeGeolocator({
    this.serviceEnabled = true,
    this.permission = LocationPermission.whileInUse,
    this.hangCurrentPosition = false,
    this.hangLastKnown = false,
    this.currentPosition,
    this.lastKnownPosition,
  });

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async => permission;

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) {
    if (hangCurrentPosition) return Completer<Position>().future;
    final position = currentPosition;
    if (position == null) return Future.error(TimeoutException('sem fix'));
    return Future.value(position);
  }

  @override
  Future<Position?> getLastKnownPosition({bool forceLocationManager = false}) {
    if (hangLastKnown) return Completer<Position?>().future;
    return Future.value(lastKnownPosition);
  }
}

/// Timeouts curtos: o comportamento testado é o mesmo, mas com os 12 segundos
/// reais a suíte inteira ficaria 30 segundos mais lenta.
LocationRepositoryImpl _repositoryWithFastTimeouts(_FakeGeolocator geolocator) {
  return LocationRepositoryImpl(
    geolocator: geolocator,
    timeout: const Duration(milliseconds: 120),
    lastKnownTimeout: const Duration(milliseconds: 120),
  );
}

void main() {
  group('permissões e serviço', () {
    test('GPS desligado devolve serviceDisabled', () async {
      final repository = LocationRepositoryImpl(
        geolocator: _FakeGeolocator(serviceEnabled: false),
      );

      final result = await repository.getCurrentLocation();

      expect(
        result.fold((f) => (f as LocationFailure).reason, (_) => null),
        LocationFailureReason.serviceDisabled,
      );
    });

    test('permissão negada de vez pede as configurações', () async {
      final repository = LocationRepositoryImpl(
        geolocator: _FakeGeolocator(
          permission: LocationPermission.deniedForever,
        ),
      );

      final result = await repository.getCurrentLocation();

      expect(
        result.fold((f) => (f as LocationFailure).reason, (_) => null),
        LocationFailureReason.permissionDeniedForever,
      );
    });
  });

  group('caminho feliz', () {
    test('devolve a posição atual', () async {
      final repository = LocationRepositoryImpl(
        geolocator: _FakeGeolocator(
          currentPosition: _position(-23.5505, -46.6333),
        ),
      );

      final result = await repository.getCurrentLocation();

      expect(result.isRight(), isTrue);
      expect(
        result.fold((_) => null, (p) => p.latitude),
        closeTo(-23.5505, 0.00001),
      );
    });

    test('sem fix novo, usa o último ponto conhecido', () async {
      final repository = LocationRepositoryImpl(
        geolocator: _FakeGeolocator(
          lastKnownPosition: _position(-23.5613, -46.6560),
        ),
      );

      final result = await repository.getCurrentLocation();

      expect(
        result.fold((_) => null, (p) => p.longitude),
        closeTo(-46.6560, 0.00001),
      );
    });
  });

  // O motivo deste arquivo existir: no emulador, o botão de localização girou
  // indefinidamente porque o `timeLimit` do geolocator não disparou. Tela
  // travada é pior que mensagem de erro — o future tem que completar sempre.
  group('travamento', () {
    test('getCurrentPosition pendurado cai no último ponto conhecido',
        () async {
      final repository = _repositoryWithFastTimeouts(
        _FakeGeolocator(
          hangCurrentPosition: true,
          lastKnownPosition: _position(-23.55, -46.63),
        ),
      );

      final result = await repository.getCurrentLocation().timeout(
            const Duration(seconds: 5),
            onTimeout: () => throw StateError('o future nunca completou'),
          );

      expect(result.isRight(), isTrue);
    });

    test('tudo pendurado ainda assim termina com erro', () async {
      final repository = _repositoryWithFastTimeouts(
        _FakeGeolocator(
          hangCurrentPosition: true,
          hangLastKnown: true,
        ),
      );

      final result = await repository.getCurrentLocation().timeout(
            const Duration(seconds: 5),
            onTimeout: () => throw StateError('o future nunca completou'),
          );

      expect(
        result.fold((f) => (f as LocationFailure).reason, (_) => null),
        LocationFailureReason.timeout,
      );
    });
  });
}
