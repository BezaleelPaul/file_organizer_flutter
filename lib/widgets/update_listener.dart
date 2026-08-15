import 'package:file_organizer/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Checks for updates once on startup and shows a dialog when a newer Mise
/// release is available.
class UpdateListener extends StatefulWidget {
  const UpdateListener({
    super.key,
    required this.state,
    required this.child,
  });

  final AppState state;
  final Widget child;

  @override
  State<UpdateListener> createState() => _UpdateListenerState();
}

class _UpdateListenerState extends State<UpdateListener> {
  bool _showing = false;
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_onState);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_checked) return;
      _checked = true;
      widget.state.checkForUpdates();
    });
  }

  @override
  void didUpdateWidget(UpdateListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      oldWidget.state.removeListener(_onState);
      widget.state.addListener(_onState);
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(_onState);
    super.dispose();
  }

  void _onState() {
    final update = widget.state.availableUpdate;
    if (update == null || _showing) return;
    _showing = true;
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.system_update_alt_rounded),
        title: const Text('Update available'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Mise ${update.latestVersion} is available — you have '
                '${update.currentVersion}.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (update.notes.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  update.notes,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Later'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              _download(update.releaseUrl);
            },
            icon: const Icon(Icons.download),
            label: const Text('Update'),
          ),
        ],
      ),
    ).whenComplete(() {
      widget.state.dismissUpdate();
      _showing = false;
    });
  }

  Future<void> _download(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
