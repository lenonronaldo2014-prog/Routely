import 'package:url_launcher/url_launcher.dart';

import '../geo/geo_point.dart';

/// Abre a navegação num app externo em vez de implementar turn-by-turn.
///
/// Não é atalho preguiçoso: navegação própria exige mapa, roteamento, voz,
/// recálculo, e — o que mais pesa — localização em background, que é
/// justamente o que trava a aprovação na Play Store. Delegar para o Google
/// Maps ou Waze resolve o problema real do usuário sem nada disso.
class NavigationLauncher {
  /// A URL universal do Google Maps aceita no máximo 9 pontos intermediários
  /// entre origem e destino. Roteiros maiores são quebrados em trechos.
  static const int maxWaypointsPerLeg = 9;

  /// Monta as URLs do roteiro completo. Devolve mais de uma quando o roteiro
  /// passa do limite de waypoints — a UI mostra "trecho 1 de N".
  List<Uri> buildGoogleMapsRoute({
    required GeoPoint origin,
    required List<GeoPoint> stops,
  }) {
    if (stops.isEmpty) return const [];

    final urls = <Uri>[];
    var legOrigin = origin;
    var remaining = List<GeoPoint>.from(stops);

    while (remaining.isNotEmpty) {
      // Cada trecho leva até 9 waypoints + 1 destino.
      final chunkSize = remaining.length <= maxWaypointsPerLeg + 1
          ? remaining.length
          : maxWaypointsPerLeg + 1;

      final chunk = remaining.take(chunkSize).toList();
      final destination = chunk.last;
      final waypoints = chunk.sublist(0, chunk.length - 1);

      urls.add(Uri.parse('https://www.google.com/maps/dir/').replace(
        queryParameters: {
          'api': '1',
          'origin': '${legOrigin.latitude},${legOrigin.longitude}',
          'destination': '${destination.latitude},${destination.longitude}',
          if (waypoints.isNotEmpty)
            'waypoints': waypoints
                .map((p) => '${p.latitude},${p.longitude}')
                .join('|'),
          'travelmode': 'driving',
        },
      ));

      // O próximo trecho começa onde este terminou.
      legOrigin = destination;
      remaining = remaining.sublist(chunkSize);
    }

    return urls;
  }

  /// O Waze não aceita múltiplas paradas por deep link, então só dá para
  /// mandar a próxima entrega.
  Uri buildWazeDestination(GeoPoint point) {
    return Uri.parse(
      'https://waze.com/ul?ll=${point.latitude},${point.longitude}&navigate=yes',
    );
  }

  Uri buildGoogleMapsDestination(GeoPoint point) {
    return Uri.parse('https://www.google.com/maps/dir/').replace(
      queryParameters: {
        'api': '1',
        'destination': '${point.latitude},${point.longitude}',
        'travelmode': 'driving',
      },
    );
  }

  Future<bool> launch(Uri uri) {
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
