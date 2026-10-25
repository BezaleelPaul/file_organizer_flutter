import 'package:file_organizer/screens/home_shell.dart';
import 'package:file_organizer/services/desktop_service.dart';
import 'package:file_organizer/state/app_scope.dart';
import 'package:file_organizer/state/app_state.dart';
import 'package:file_organizer/state/settings_store.dart';
import 'package:file_organizer/theme.dart';
import 'package:file_organizer/widgets/completion_dialog.dart';
import 'package:file_organizer/widgets/splash_screen.dart';
import 'package:file_organizer/widgets/update_listener.dart';
import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = SettingsStore();
  final minimizeToTray = await store.loadMinimizeToTray();
  await initDesktop(minimizeToTray: minimizeToTray);
  registerWindowCloseListener();
  TrayManager.instance.addListener(_TrayListener());
  final state = AppState(store: store);
  setTrayActionHandler(state.handleTrayAction);
  runApp(FileOrganizerApp(state: state));
}

class _TrayListener extends TrayListener {
  @override
  void onTrayIconMouseDown() {
    onTrayMenuClick('show');
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    onTrayMenuClick(menuItem.key ?? '');
  }
}

class _StartupErrorScreen extends StatelessWidget {
  const _StartupErrorScreen({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 56,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  'Mise could not start',
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Your settings and files were not changed. The details '
                  'below can help diagnose the problem.',
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    '${state.startupError}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: state.retryInit,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class FileOrganizerApp extends StatelessWidget {
  const FileOrganizerApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          return MaterialApp(
            title: 'Mise',
            debugShowCheckedModeBanner: false,
            theme: buildTheme(Brightness.light),
            darkTheme: buildTheme(Brightness.dark),
            builder: (context, child) => CompletionListener(
              state: state,
              child: UpdateListener(
                state: state,
                child: child ?? const SizedBox.shrink(),
              ),
            ),
            home: AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: state.startupError != null
                  ? _StartupErrorScreen(
                      key: const ValueKey('startup-error'),
                      state: state,
                    )
                  : state.initialized
                  ? HomeShell(key: const ValueKey('home'), state: state)
                  : const SplashScreen(key: ValueKey('splash')),
            ),
          );
        },
      ),
    );
  }
}
