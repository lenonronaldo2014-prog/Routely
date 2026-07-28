import 'package:dartz/dartz.dart';
import 'package:geolocator/geolocator.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/geo/geo_point.dart';
import '../../domain/repositories/location_repository.dart';

/// Localização **somente em primeiro plano**.
///
/// Essa é uma decisão de política, não técnica: o Google Play exige formulário
/// de declaração, vídeo de demonstração e justificativa para acesso à
/// localização em background, e é a principal causa de recusa em apps de rota.
/// O Routely lê a posição só quando o usuário toca em "calcular", enquanto o
/// app está aberto — então não precisa de `ACCESS_BACKGROUND_LOCATION`, nem de
/// serviço em primeiro plano, e a revisão da loja fica trivial.
class LocationRepositoryImpl implements LocationRepository {
  /// Depois disso desistimos e usamos o último ponto conhecido, se houver.
  /// GPS em área urbana densa pode demorar muito para fixar.
  static const defaultTimeout = Duration(seconds: 12);

  /// O último ponto conhecido vem da memória do sistema e deveria ser
  /// instantâneo — se demorar isso, também travou.
  static const defaultLastKnownTimeout = Duration(seconds: 4);

  final GeolocatorPlatform geolocator;

  /// Configuráveis só para teste: verificar o caminho de travamento com os
  /// valores reais deixaria a suíte 30 segundos mais lenta.
  final Duration timeout;
  final Duration lastKnownTimeout;

  LocationRepositoryImpl({
    required this.geolocator,
    this.timeout = defaultTimeout,
    this.lastKnownTimeout = defaultLastKnownTimeout,
  });

  @override
  Future<Either<Failure, GeoPoint>> getCurrentLocation() async {
    final serviceEnabled = await geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Left(LocationFailure(LocationFailureReason.serviceDisabled));
    }

    var permission = await geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      return Left(LocationFailure(LocationFailureReason.permissionDeniedForever));
    }
    if (permission == LocationPermission.denied) {
      return Left(LocationFailure(LocationFailureReason.permissionDenied));
    }

    try {
      // O `.timeout()` do Dart é redundante com o `timeLimit` do
      // LocationSettings — de propósito. O `timeLimit` do geolocator não
      // dispara de forma confiável em todas as combinações de provider no
      // Android; quando ele falha, o future simplesmente nunca completa e a
      // tela fica girando para sempre, sem saída. Uma tela travada é pior que
      // uma mensagem de erro.
      final position = await geolocator
          .getCurrentPosition(
            locationSettings: LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: timeout,
            ),
          )
          .timeout(timeout);

      return Right(GeoPoint(
        latitude: position.latitude,
        longitude: position.longitude,
      ));
    } catch (_) {
      return _fallbackToLastKnown();
    }
  }

  /// Fixar o GPS falhou ou estourou o tempo. Um ponto de alguns minutos atrás
  /// ainda ordena as paradas bem melhor do que erro na tela.
  Future<Either<Failure, GeoPoint>> _fallbackToLastKnown() async {
    try {
      final lastKnown =
          await geolocator.getLastKnownPosition().timeout(lastKnownTimeout);

      if (lastKnown != null) {
        return Right(GeoPoint(
          latitude: lastKnown.latitude,
          longitude: lastKnown.longitude,
        ));
      }
    } catch (_) {
      // Também travou ou falhou — cai no erro abaixo.
    }

    return Left(LocationFailure(LocationFailureReason.timeout));
  }

  @override
  Future<void> openAppSettings() async {
    await geolocator.openAppSettings();
  }
}
