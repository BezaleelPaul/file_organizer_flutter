import 'package:file_organizer/screens/home_shell.dart';
import 'package:file_organizer/state/app_state.dart';
import 'package:file_organizer/state/settings_store.dart';
import 'package:file_organizer/theme.dart';
import 'package:file_organizer/widgets/completion_dialog.dart';
import 'package:file_organizer/widgets/splash_screen.dart';
import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = SettingsStore();
  final state = AppState(store: store);
  runApp(FileOrganizerApp(state: state));
}

class FileOrganizerApp extends StatelessWidget {
  const FileOrganizerApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        return MaterialApp(
          title: 'File Organizer',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          builder: (context, child) => CompletionListener(
            state: state,
            child: child ?? const SizedBox.shrink(),
          ),
          home: AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: state.initialized
                ? HomeShell(
                    key: const ValueKey('home'),
                    state: state,
                  )
                : const SplashScreen(key: ValueKey('splash')),
          ),
        );
      },
    );
  }
}
