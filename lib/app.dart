// lib/app.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/auth/screens/register_screen.dart';
// import 'features/auth/providers/auth_provider.dart';
import 'features/history/screens/history_screen.dart';
import 'features/contributor/screens/recording_screen.dart';
import 'features/navigator_mode/screens/map_download_screen.dart';
import 'features/navigator_mode/screens/ar_navigation_screen.dart';
import 'features/relocalization/screens/relocalization_screen.dart';

final _routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/recording',
    redirect: (context, state) => null,
    routes: [
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        name: 'register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/history',
        name: 'history',
        builder: (context, state) => const HistoryScreen(),
      ),
      GoRoute(
        path: '/recording',
        name: 'recording',
        builder: (context, state) => const RecordingScreen(),
      ),
      GoRoute(
        path: '/map-download',
        name: 'mapDownload',
        builder: (context, state) => const MapDownloadScreen(),
      ),
      GoRoute(
        path: '/ar-navigation',
        name: 'arNavigation',
        builder: (context, state) => const ArNavigationScreen(),
      ),
      GoRoute(
        path: '/relocalization',
        name: 'relocalization',
        builder: (context, state) => const RelocalizationScreen(),
      ),
    ],
  );
});

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(_routerProvider);

    return MaterialApp.router(
      title: 'DDaMin',
      routerConfig: router,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D32)),
        useMaterial3: true,
      ),
    );
  }
}
