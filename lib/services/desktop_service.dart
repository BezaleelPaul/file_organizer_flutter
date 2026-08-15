/// Desktop integration: system tray, minimize-to-tray, and launch at startup.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// Whether the current platform supports desktop integration.
bool get isDesktop =>
    !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

/// Initializes the window and tray. Call once, before [runApp].
Future<void> initDesktop({required bool minimizeToTray}) async {
  if (!isDesktop) return;
  MinimizeToTrayController.enabled = minimizeToTray;
  await windowManager.ensureInitialized();
  // Closing is always intercepted so we can decide hide-to-tray vs. quit.
  await windowManager.setPreventClose(true);
  LaunchAtStartup.instance.setup(
    appName: 'Mise',
    appPath: Platform.resolvedExecutable,
  );
  await _setTrayIcon();
  await _refreshTrayMenu();
}

/// Writes the bundled tray icon to a temp file and hands it to the tray.
Future<void> _setTrayIcon() async {
  try {
    final useIco = Platform.isWindows;
    final data = await rootBundle.load(
      useIco ? 'assets/icon/app_icon.ico' : 'assets/icon/app_icon.png',
    );
    final file = File(
      '${Directory.systemTemp.path}/mise_tray_'
      '${useIco ? 'icon.ico' : 'icon.png'}',
    );
    await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
    await trayManager.setIcon(file.path);
  } catch (_) {
    // The tray is best-effort; the app still works without it.
  }
}

Future<void> _refreshTrayMenu() async {
  try {
    await trayManager.setToolTip('Mise — everything in its place');
    await trayManager.setContextMenu(Menu(items: [
      MenuItem(key: 'show', label: 'Open Mise'),
      MenuItem(key: 'quit', label: 'Quit'),
    ]));
  } catch (_) {}
}

/// Handles tray menu clicks (called from the tray listener).
Future<void> onTrayMenuClick(String key) async {
  switch (key) {
    case 'show':
      await windowManager.show();
      await windowManager.focus();
    case 'quit':
      await windowManager.destroy();
  }
}

/// Current close behavior: hide to the tray (true) or quit (false).
class MinimizeToTrayController {
  static bool enabled = true;
}

/// Intercepts window close. Hides to the tray when minimize-to-tray is on,
/// otherwise quits the app.
class MinimizeToTrayListener extends WindowListener {
  @override
  void onWindowClose() async {
    if (MinimizeToTrayController.enabled) {
      await windowManager.hide();
    } else {
      await windowManager.destroy();
    }
  }
}

/// Registers the close-to-tray listener. Call once at startup.
void registerWindowCloseListener() {
  windowManager.addListener(MinimizeToTrayListener());
}

/// Updates the close behavior to match the current minimize-to-tray setting.
Future<void> syncMinimizeToTray(bool enabled) async {
  MinimizeToTrayController.enabled = enabled;
}

Future<bool> launchAtStartupEnabled() async {
  try {
    return await LaunchAtStartup.instance.isEnabled();
  } catch (_) {
    return false;
  }
}

Future<bool> setLaunchAtStartupEnabled(bool enabled) async {
  try {
    return enabled
        ? await LaunchAtStartup.instance.enable()
        : await LaunchAtStartup.instance.disable();
  } catch (_) {
    return false;
  }
}

/// Reveal a file (or its folder) in the operating system file manager.
Future<void> revealInFileManager(String path) async {
  if (!isDesktop) return;
  try {
    if (Platform.isWindows) {
      await Process.run('explorer', ['/select,', path]);
    } else if (Platform.isMacOS) {
      await Process.run('open', ['-R', path]);
    } else {
      final dir = Directory(path);
      final target = dir.existsSync() ? dir.path : dir.parent.path;
      await Process.run('xdg-open', [target]);
    }
  } catch (_) {}
}