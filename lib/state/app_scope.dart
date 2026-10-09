/// InheritedWidget providing scoped access to all controllers across the widget tree.
library;

import 'package:file_organizer/state/app_state.dart';
import 'package:flutter/widgets.dart';

class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.state,
    required super.child,
  });

  final AppState state;

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'No AppScope found in context');
    return scope!.state;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => state != oldWidget.state;
}
