import 'package:file_organizer/state/app_state.dart';
import 'package:flutter/material.dart';

/// Watches [state.completion] and shows an animated completion dialog when a
/// background operation finishes.
class CompletionListener extends StatefulWidget {
  const CompletionListener({
    super.key,
    required this.state,
    required this.child,
  });

  final AppState state;
  final Widget child;

  @override
  State<CompletionListener> createState() => _CompletionListenerState();
}

class _CompletionListenerState extends State<CompletionListener> {
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_onState);
  }

  @override
  void didUpdateWidget(CompletionListener oldWidget) {
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
    final completion = widget.state.completion;
    if (completion != null && !_showing) {
      _showing = true;
      showGeneralDialog(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'Done',
        barrierColor: Colors.black54,
        transitionDuration: const Duration(milliseconds: 300),
        transitionBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutBack,
            reverseCurve: Curves.easeIn,
          );
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(scale: curved, child: child),
          );
        },
        pageBuilder: (context, _, _) => _CompletionDialog(
          message: completion,
          onDismiss: () {
            Navigator.of(context).pop();
          },
          onUndo: () {
            Navigator.of(context).pop();
            widget.state.undo(completion.undoEntry!);
          },
        ),
      ).whenComplete(() {
        widget.state.consumeCompletion();
        _showing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _CompletionDialog extends StatefulWidget {
  const _CompletionDialog({
    required this.message,
    required this.onDismiss,
    required this.onUndo,
  });

  final CompletionMessage message;
  final VoidCallback onDismiss;
  final VoidCallback onUndo;

  @override
  State<_CompletionDialog> createState() => _CompletionDialogState();
}

class _CompletionDialogState extends State<_CompletionDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final message = widget.message;
    final color = message.success ? Colors.green : scheme.primary;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Center(
        child: Container(
          width: 320,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 32,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Animated checkmark.
              AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  final t = Curves.elasticOut.transform(_controller.value);
                  return Transform.scale(
                    scale: t.clamp(0.0, 1.2),
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        message.success
                            ? Icons.check_rounded
                            : Icons.info_outline_rounded,
                        size: 40,
                        color: color,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
              Text(
                message.title,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                message.message,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: widget.onDismiss,
                    child: const Text('Close'),
                  ),
                  if (message.undoEntry != null) ...[
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: widget.onUndo,
                      icon: const Icon(Icons.undo),
                      label: const Text('Undo'),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
