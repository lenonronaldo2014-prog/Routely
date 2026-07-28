import 'package:routely/features/routing/data/datasources/route_local_data_source.dart';
import 'package:routely/features/routing/domain/entities/active_route.dart';

/// Persistência inerte para os testes que só exercitam o cálculo da rota.
/// Evita arrastar um banco de verdade para dentro de teste de lógica pura.
class NoopRouteLocalDataSource implements RouteLocalDataSource {
  @override
  Future<void> saveActiveRoute(ActiveRoute route) async {}

  @override
  Future<ActiveRoute?> getActiveRoute() async => null;

  @override
  Future<void> clearActiveRoute() async {}
}
