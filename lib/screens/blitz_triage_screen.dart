import 'package:file_organizer/core/models.dart';
import 'package:file_organizer/core/rules.dart';
import 'package:file_organizer/state/app_state.dart';
import 'package:file_organizer/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum TriageDecision { autoFile, trash, keep }

class TriageAction {
  const TriageAction({
    required this.file,
    required this.decision,
    this.chosenCategory,
  });

  final PlannedMove file;
  final TriageDecision decision;
  final String? chosenCategory;
}

class BlitzTriageScreen extends StatefulWidget {
  const BlitzTriageScreen({super.key, required this.state});

  final AppState state;

  @override
  State<BlitzTriageScreen> createState() => _BlitzTriageScreenState();
}

class _BlitzTriageScreenState extends State<BlitzTriageScreen> {
  final FocusNode _focusNode = FocusNode();
  int _currentIndex = 0;
  final List<TriageAction> _history = [];
  bool _isApplying = false;
  bool _finished = false;

  List<PlannedMove> get _files => widget.state.scan?.files ?? [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _handleDecision(TriageDecision decision, [String? overrideCategory]) {
    if (_currentIndex >= _files.length) return;
    final current = _files[_currentIndex];

    setState(() {
      _history.add(TriageAction(
        file: current,
        decision: decision,
        chosenCategory: overrideCategory,
      ));
      if (overrideCategory != null) {
        current.overrideCategory = overrideCategory;
      }
      if (decision == TriageDecision.keep) {
        current.skipped = true;
      } else {
        current.skipped = false;
      }

      if (_currentIndex + 1 < _files.length) {
        _currentIndex++;
      } else {
        _finished = true;
      }
    });
  }

  void _undoLast() {
    if (_history.isEmpty) return;
    setState(() {
      final last = _history.removeLast();
      last.file.skipped = false;
      last.file.overrideCategory = null;
      if (_finished) {
        _finished = false;
      } else if (_currentIndex > 0) {
        _currentIndex--;
      }
    });
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _finished) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
        event.logicalKey == LogicalKeyboardKey.keyA) {
      _handleDecision(TriageDecision.trash);
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
        event.logicalKey == LogicalKeyboardKey.keyD) {
      _handleDecision(TriageDecision.autoFile);
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
        event.logicalKey == LogicalKeyboardKey.keyW) {
      _handleDecision(TriageDecision.keep);
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
        event.logicalKey == LogicalKeyboardKey.keyS) {
      _showCategoryPicker();
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.backspace ||
        (HardwareKeyboard.instance.isControlPressed &&
            event.logicalKey == LogicalKeyboardKey.keyZ)) {
      _undoLast();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _showCategoryPicker() {
    if (_currentIndex >= _files.length) return;
    final current = _files[_currentIndex];
    final categories = widget.state.categories.keys.toList();

    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'Re-route "${current.name}"',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.builder(
                    itemCount: categories.length,
                    itemBuilder: (ctx, i) {
                      final cat = categories[i];
                      return ListTile(
                        leading: const Icon(Icons.folder_outlined),
                        title: Text(cat),
                        onTap: () {
                          Navigator.pop(ctx);
                          _handleDecision(TriageDecision.autoFile, cat);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _applyAll() async {
    final root = widget.state.root;
    if (root == null) return;

    setState(() => _isApplying = true);

    try {
      final trashMoves = _history
          .where((a) => a.decision == TriageDecision.trash)
          .map((a) => a.file)
          .toList();

      if (trashMoves.isNotEmpty) {
        for (final m in trashMoves) {
          m.overrideCategory = 'Trash';
          m.skipped = false;
        }
      }

      await widget.state.organize();
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Triage execution error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isApplying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _onKeyEvent,
      autofocus: true,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Exit Blitz',
            onPressed: () => Navigator.pop(context),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: StudioColors.crimsonBurn.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bolt, size: 16, color: StudioColors.crimsonBurn),
                    SizedBox(width: 4),
                    Text(
                      'BLITZ TRIAGE',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: StudioColors.crimsonBurn,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (_files.isNotEmpty && !_finished)
                Text(
                  '${_currentIndex + 1} / ${_files.length}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                ),
            ],
          ),
          actions: [
            if (_history.isNotEmpty && !_finished)
              TextButton.icon(
                icon: const Icon(Icons.undo, size: 18),
                label: const Text('Undo'),
                onPressed: _undoLast,
              ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          child: _files.isEmpty
              ? _buildEmptyView()
              : _finished
                  ? _buildFinishedView()
                  : _buildCardView(scheme, isDark),
        ),
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_outline, size: 64, color: StudioColors.emeraldZen),
          const SizedBox(height: 16),
          const Text(
            'Nothing to triage!',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text('Scan a folder first to enter Blitz Mode.'),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Return to Studio'),
          ),
        ],
      ),
    );
  }

  Widget _buildFinishedView() {
    final filedCount = _history.where((a) => a.decision == TriageDecision.autoFile).length;
    final trashCount = _history.where((a) => a.decision == TriageDecision.trash).length;
    final keepCount = _history.where((a) => a.decision == TriageDecision.keep).length;

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: StudioColors.emeraldZen.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.done_all_rounded,
                size: 56,
                color: StudioColors.emeraldZen,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Blitz Run Complete! 🔥',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'You triaged ${_history.length} files in record time.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildStatPill('Auto-Filed', '$filedCount', StudioColors.electricIndigo),
                _buildStatPill('Sent to Trash', '$trashCount', StudioColors.crimsonBurn),
                _buildStatPill('Kept Untouched', '$keepCount', StudioColors.cyberAmber),
              ],
            ),
            const SizedBox(height: 36),
            if (_isApplying)
              const CircularProgressIndicator()
            else ...[
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.rocket_launch_rounded),
                  label: const Text('Apply Triaged Plan Now', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    backgroundColor: StudioColors.electricIndigo,
                  ),
                  onPressed: _applyAll,
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Review in Blueprint View'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatPill(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardView(ColorScheme scheme, bool isDark) {
    final current = _files[_currentIndex];
    final ext = extensionOf(current.name);
    final isInstaller = RegExp(r'\.(exe|msi|dmg|pkg|iso|apk)$').hasMatch(current.name.toLowerCase());
    final isScreenshot = RegExp(r'(screenshot|screen_shot|captura|snip)').hasMatch(current.name.toLowerCase());

    return Column(
      children: [
        LinearProgressIndicator(
          value: (_currentIndex + 1) / _files.length,
          backgroundColor: scheme.surfaceContainerLow,
          color: StudioColors.electricIndigo,
          minHeight: 4,
        ),
        Expanded(
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 480),
              padding: const EdgeInsets.all(24),
              child: GestureDetector(
                onHorizontalDragEnd: (details) {
                  if (details.primaryVelocity != null) {
                    if (details.primaryVelocity! < -200) {
                      _handleDecision(TriageDecision.trash);
                    } else if (details.primaryVelocity! > 200) {
                      _handleDecision(TriageDecision.autoFile);
                    }
                  }
                },
                child: Card(
                  elevation: 6,
                  color: isDark ? StudioColors.darkCard : Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Badges row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: StudioColors.electricIndigo.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                ext.isNotEmpty ? ext.toUpperCase() : 'NO EXT',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                  color: StudioColors.electricIndigo,
                                ),
                              ),
                            ),
                            if (isInstaller)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: StudioColors.crimsonBurn.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  '⚠️ INSTALLER',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 11,
                                    color: StudioColors.crimsonBurn,
                                  ),
                                ),
                              )
                            else if (isScreenshot)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: StudioColors.cyanBeam.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  '📸 SCREENSHOT',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 11,
                                    color: StudioColors.cyanBeam,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        // Big File Visual Icon
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Icon(
                            _iconForCategory(current.effectiveCategory),
                            size: 42,
                            color: scheme.primary,
                          ),
                        ),
                        const SizedBox(height: 20),
                        // File Name
                        Text(
                          current.name,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 10),
                        // Metadata pills
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              formatBytes(current.size),
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            const Text('  •  '),
                            Text(
                              '${current.modified.year}-${current.modified.month.toString().padLeft(2, '0')}-${current.modified.day.toString().padLeft(2, '0')}',
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        // Target destination banner
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: isDark ? StudioColors.darkSurface : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isDark ? StudioColors.darkBorder : const Color(0xFFE2E8F0),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.arrow_forward_rounded, size: 16, color: StudioColors.electricIndigo),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'Route to: ${current.effectiveCategory}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: StudioColors.electricIndigo,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        // Action buttons & hotkey guides
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.delete_outline, color: StudioColors.crimsonBurn),
                    label: const Text('Trash [← / A]'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: StudioColors.crimsonBurn,
                      side: const BorderSide(color: StudioColors.crimsonBurn),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onPressed: () => _handleDecision(TriageDecision.trash),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.visibility_off_outlined),
                    label: const Text('Keep [↑ / W]'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onPressed: () => _handleDecision(TriageDecision.keep),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.tune),
                    label: const Text('Change [↓ / S]'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onPressed: _showCategoryPicker,
                  ),
                  FilledButton.icon(
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Auto-File [→ / D]'),
                    style: FilledButton.styleFrom(
                      backgroundColor: StudioColors.electricIndigo,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                    onPressed: () => _handleDecision(TriageDecision.autoFile),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Tip: Use keyboard arrows or swipe cards for lightning-fast triage',
                style: TextStyle(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  IconData _iconForCategory(String category) {
    switch (category.toLowerCase()) {
      case 'images':
      case 'photos':
      case 'screenshots':
        return Icons.image_outlined;
      case 'videos':
      case 'footage':
        return Icons.movie_outlined;
      case 'music':
        return Icons.music_note_outlined;
      case 'documents':
      case 'finances':
        return Icons.description_outlined;
      case 'code':
        return Icons.code_outlined;
      case 'archives':
        return Icons.folder_zip_outlined;
      case 'installers':
      case 'programs':
        return Icons.install_desktop_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }
}
