import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/theme/app_theme.dart';
import 'features/routing/presentation/bloc/active_route_bloc.dart';
import 'features/routing/presentation/bloc/active_route_event.dart';
import 'features/settings/presentation/cubit/settings_cubit.dart';
import 'features/stops/presentation/bloc/stops_bloc.dart';
import 'features/stops/presentation/bloc/stops_event.dart';
import 'features/stops/presentation/pages/stops_page.dart';
import 'injection_container.dart' as di;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await di.init();
  runApp(const RoutelyApp());
}

class RoutelyApp extends StatelessWidget {
  const RoutelyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => di.sl<StopsBloc>()..add(const StopsLoadRequested()),
        ),
        // Global e carregado na abertura: se o app foi morto no meio do
        // roteiro, a rota tem que estar de volta na tela inicial.
        BlocProvider(
          create: (_) =>
              di.sl<ActiveRouteBloc>()..add(const ActiveRouteLoadRequested()),
        ),
        // Acima do MaterialApp porque o tema escolhido precisa chegar nele —
        // trocar claro/escuro reflete na hora, sem reiniciar o app.
        BlocProvider(create: (_) => di.sl<SettingsCubit>()),
      ],
      child: BlocBuilder<SettingsCubit, SettingsState>(
        buildWhen: (previous, current) =>
            previous.themeMode != current.themeMode,
        builder: (context, settings) {
          return MaterialApp(
            title: 'Routely',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: settings.themeMode,
            home: const StopsPage(),
          );
        },
      ),
    );
  }
}
