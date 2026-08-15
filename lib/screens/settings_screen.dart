import 'package:file_organizer/services/desktop_service.dart';
import 'package:file_organizer/state/app_state.dart';
import 'package:flutter/material.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.state});

  final AppState state;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _checking = false;

  AppState get state => widget.state;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: state,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (isDesktop) ...[
              _Section(
                title: 'General',
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Launch at startup'),
                    subtitle: const Text(
                        'Start Mise automatically when you sign in.'),
                    value: state.launchAtStartup,
                    onChanged: (v) => state.setLaunchAtStartup(v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Minimize to tray'),
                    subtitle: const Text(
                        'Closing the window keeps Mise running in the '
                        'system tray so auto-organizing keeps working.'),
                    value: state.minimizeToTray,
                    onChanged: (v) => state.setMinimizeToTray(v),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            _Section(
              title: 'Updates',
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: _checking
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(state.availableUpdate != null
                          ? Icons.system_update_alt_rounded
                          : Icons.check_circle_outline),
                  title: const Text('Check for updates'),
                  subtitle: Text(
                    state.availableUpdate != null
                        ? 'Mise ${state.availableUpdate!.latestVersion} is '
                            'available'
                        : 'You have the latest version.',
                  ),
                  trailing: FilledButton.tonal(
                    onPressed: _checking ? null : () => _check(),
                    child: const Text('Check'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _Section(
              title: 'About',
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.info_outline),
                  title: const Text('Mise'),
                  subtitle: Text('Version ${state.appVersion}'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    await state.checkForUpdates();
    if (mounted) setState(() => _checking = false);
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}