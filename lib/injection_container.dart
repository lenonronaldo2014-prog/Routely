import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'core/config/app_config.dart';
import 'core/database/app_database.dart';
import 'core/network/network_info.dart';
import 'core/services/daily_quota.dart';
import 'core/services/navigation_launcher.dart';
import 'core/settings/app_settings.dart';
import 'features/location/data/repositories/location_repository_impl.dart';
import 'features/location/domain/repositories/location_repository.dart';
import 'features/location/domain/usecases/get_current_location.dart';
import 'features/routing/data/datasources/route_local_data_source.dart';
import 'features/routing/data/providers/haversine_matrix_provider.dart';
import 'features/routing/data/repositories/routing_repository_impl.dart';
import 'features/routing/domain/repositories/routing_repository.dart';
import 'features/routing/domain/repositories/travel_matrix_provider.dart';
import 'features/routing/domain/services/route_optimizer.dart';
import 'features/routing/domain/usecases/calculate_route_options.dart';
import 'features/routing/domain/usecases/finish_route.dart';
import 'features/routing/domain/usecases/get_active_route.dart';
import 'features/routing/domain/usecases/recalculate_route.dart';
import 'features/routing/domain/usecases/start_route.dart';
import 'features/routing/presentation/bloc/active_route_bloc.dart';
import 'features/routing/presentation/bloc/route_bloc.dart';
import 'features/settings/presentation/cubit/settings_cubit.dart';
import 'features/stops/data/datasources/address_local_data_source.dart';
import 'features/stops/data/datasources/address_remote_data_source.dart';
import 'features/stops/data/datasources/cep_directory_local_data_source.dart';
import 'features/stops/data/datasources/geoapify_remote_data_source.dart';
import 'features/stops/data/datasources/backup_data_source.dart';
import 'features/stops/data/datasources/history_local_data_source.dart';
import 'features/stops/data/datasources/label_scanner_data_source.dart';
import 'features/stops/data/datasources/stops_local_data_source.dart';
import 'features/stops/data/repositories/address_repository_impl.dart';
import 'features/stops/data/repositories/backup_repository_impl.dart';
import 'features/stops/data/repositories/cep_directory_repository_impl.dart';
import 'features/stops/data/repositories/history_repository_impl.dart';
import 'features/stops/data/repositories/label_scanner_repository_impl.dart';
import 'features/stops/data/repositories/stops_repository_impl.dart';
import 'features/stops/domain/repositories/address_repository.dart';
import 'features/stops/domain/repositories/backup_repository.dart';
import 'features/stops/domain/repositories/cep_directory_repository.dart';
import 'features/stops/domain/repositories/history_repository.dart';
import 'features/stops/domain/repositories/label_scanner_repository.dart';
import 'features/stops/domain/services/label_parser.dart';
import 'features/stops/domain/repositories/stops_repository.dart';
import 'features/stops/presentation/cubit/cep_packs_cubit.dart';
import 'features/stops/presentation/cubit/history_cubit.dart';
import 'features/stops/domain/usecases/clear_completed_stops.dart';
import 'features/stops/domain/usecases/delete_stop.dart';
import 'features/stops/domain/usecases/get_stops.dart';
import 'features/stops/domain/usecases/lookup_cep.dart';
import 'features/stops/domain/usecases/resolve_pending_coordinates.dart';
import 'features/stops/domain/usecases/save_stop.dart';
import 'features/stops/domain/usecases/set_stop_status.dart';
import 'features/stops/presentation/bloc/stop_form_bloc.dart';
import 'features/stops/presentation/bloc/stops_bloc.dart';

final sl = GetIt.instance;

Future<void> init() async {
  //! Features - Stops
  // Bloc
  sl.registerFactory(
    () => StopsBloc(
      getStops: sl(),
      deleteStop: sl(),
      setStopStatus: sl(),
      clearCompletedStops: sl(),
      resolvePendingCoordinates: sl(),
      saveStop: sl(),
    ),
  );
  sl.registerFactory(
    () => StopFormBloc(
      lookupCep: sl(),
      saveStop: sl(),
      addressRepository: sl(),
    ),
  );
  sl.registerFactory(() => CepPacksCubit(sl()));
  sl.registerFactory(() => HistoryCubit(sl()));

  // Use cases
  sl.registerLazySingleton(() => GetStops(sl()));
  sl.registerLazySingleton(() => SaveStop(sl()));
  sl.registerLazySingleton(() => DeleteStop(sl()));
  sl.registerLazySingleton(() => SetStopStatus(sl()));
  sl.registerLazySingleton(() => ClearCompletedStops(sl()));
  sl.registerLazySingleton(() => ResolvePendingCoordinates(sl()));
  sl.registerLazySingleton(() => LookupCep(sl()));

  // Repositories
  sl.registerLazySingleton<StopsRepository>(
    () => StopsRepositoryImpl(
      localDataSource: sl(),
      addressRepository: sl(),
      historyDataSource: sl(),
    ),
  );
  sl.registerLazySingleton<HistoryRepository>(
    () => HistoryRepositoryImpl(localDataSource: sl()),
  );
  sl.registerLazySingleton<BackupRepository>(
    () => BackupRepositoryImpl(dataSource: sl()),
  );
  sl.registerLazySingleton<CepDirectoryRepository>(
    () => CepDirectoryRepositoryImpl(localDataSource: sl()),
  );
  sl.registerLazySingleton<AddressRepository>(
    () => AddressRepositoryImpl(
      remoteDataSource: sl(),
      geoapifyDataSource: sl(),
      geoapifyQuota: sl(),
      localDataSource: sl(),
      directoryDataSource: sl(),
      networkInfo: sl(),
    ),
  );

  // Data sources
  sl.registerLazySingleton<StopsLocalDataSource>(
    () => StopsLocalDataSourceImpl(appDatabase: sl()),
  );
  sl.registerLazySingleton<AddressLocalDataSource>(
    () => AddressLocalDataSourceImpl(appDatabase: sl()),
  );
  sl.registerLazySingleton<AddressRemoteDataSource>(
    () => AddressRemoteDataSourceImpl(client: sl()),
  );
  sl.registerLazySingleton<GeoapifyRemoteDataSource>(
    () => GeoapifyRemoteDataSourceImpl(client: sl()),
  );
  sl.registerLazySingleton<CepDirectoryLocalDataSource>(
    () => CepDirectoryLocalDataSourceImpl(appDatabase: sl()),
  );
  sl.registerLazySingleton<HistoryLocalDataSource>(
    () => HistoryLocalDataSourceImpl(appDatabase: sl()),
  );
  sl.registerLazySingleton<BackupDataSource>(
    () => BackupDataSourceImpl(appDatabase: sl()),
  );

  // Leitura da etiqueta
  sl.registerLazySingleton<LabelScannerRepository>(
    () => LabelScannerRepositoryImpl(dataSource: sl(), parser: sl()),
  );
  sl.registerLazySingleton<LabelScannerDataSource>(
    () => LabelScannerDataSourceImpl(),
  );
  sl.registerLazySingleton(() => const LabelParser());

  //! Features - Routing
  // Bloc
  sl.registerFactory(
    () => RouteBloc(
      getCurrentLocation: sl(),
      calculateRouteOptions: sl(),
    ),
  );

  sl.registerFactory(
    () => ActiveRouteBloc(
      getActiveRoute: sl(),
      startRoute: sl(),
      finishRoute: sl(),
      recalculateRoute: sl(),
      getCurrentLocation: sl(),
    ),
  );

  // Use cases
  sl.registerLazySingleton(() => CalculateRouteOptions(sl()));
  sl.registerLazySingleton(() => StartRoute(sl()));
  sl.registerLazySingleton(() => GetActiveRoute(sl()));
  sl.registerLazySingleton(() => FinishRoute(sl()));
  sl.registerLazySingleton(() => RecalculateRoute(sl()));

  // Repository
  sl.registerLazySingleton<RoutingRepository>(
    () => RoutingRepositoryImpl(
      matrixProvider: sl(),
      optimizer: sl(),
      settings: sl(),
      localDataSource: sl(),
    ),
  );

  sl.registerLazySingleton<RouteLocalDataSource>(
    () => RouteLocalDataSourceImpl(appDatabase: sl()),
  );

  // A fonte dos tempos de viagem. É o único ponto a trocar para ligar um
  // serviço de rotas real (OSRM próprio, Google, Mapbox) — nada acima disso
  // precisa mudar.
  sl.registerLazySingleton<TravelMatrixProvider>(
    () => HaversineMatrixProvider(settings: sl()),
  );
  sl.registerLazySingleton(() => const RouteOptimizer());

  //! Features - Location
  sl.registerLazySingleton(() => GetCurrentLocation(sl()));
  sl.registerLazySingleton<LocationRepository>(
    () => LocationRepositoryImpl(geolocator: sl()),
  );

  //! Features - Settings
  sl.registerFactory(() => SettingsCubit(sl()));

  //! Core
  sl.registerLazySingleton<NetworkInfo>(() => NetworkInfoImpl(sl()));

  // Segura o consumo do plano gratuito do Geoapify. Estourado o teto do dia, o
  // app cai no Nominatim em vez de começar a receber recusa do provedor.
  sl.registerLazySingleton(
    () => DailyQuota(
      prefs: sl(),
      name: 'geoapify',
      budget: AppConfig.geoapifyDailyBudget,
    ),
  );
  sl.registerLazySingleton(() => NavigationLauncher());
  sl.registerLazySingleton(() => AppSettings(sl()));
  sl.registerLazySingleton(() => AppDatabase());

  //! External
  final sharedPreferences = await SharedPreferences.getInstance();
  sl.registerLazySingleton(() => sharedPreferences);
  sl.registerLazySingleton(() => http.Client());
  sl.registerLazySingleton(() => Connectivity());
  sl.registerLazySingleton(() => GeolocatorPlatform.instance);
}
