/// A FIFO worker queue that serializes file-mutating work.
///
/// Every organize/watch/schedule/undo/trash operation runs through this queue
/// so two operations never touch the file system at the same time. Interactive
/// work enqueues and waits its turn; background jobs use [skipIfBusy] so they
/// are dropped when the queue is busy and retried on their next tick instead
/// of piling up.
library;

import 'dart:async';

class OperationQueue {
  bool _running = false;
  final List<_QueuedOperation> _queue = [];

  /// True when an operation is running or waiting in the queue.
  bool get isBusy => _running || _queue.isNotEmpty;

  /// Enqueue [op]. When [skipIfBusy] is true and the queue is busy, the op is
  /// not run and `false` is returned. Otherwise the op runs (possibly after
  /// waiting) and `true` is returned when it completes.
  ///
  /// Ops are expected to catch their own errors and report them through state;
  /// this queue never lets a thrown error escape.
  Future<bool> run(
    Future<void> Function() op, {
    bool skipIfBusy = false,
  }) async {
    if (skipIfBusy && isBusy) return false;
    final completer = Completer<void>();
    _queue.add(_QueuedOperation(op, completer));
    _pump();
    await completer.future;
    return true;
  }

  void _pump() {
    if (_running || _queue.isEmpty) return;
    _running = true;
    final job = _queue.removeAt(0);
    // Swallow op errors: the pipeline reports failures via state fields, and
    // background callers do not await the returned future.
    unawaited(job.op().then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    ).whenComplete(() {
      _running = false;
      job.completer.complete();
      _pump();
    }));
  }
}

class _QueuedOperation {
  _QueuedOperation(this.op, this.completer);

  final Future<void> Function() op;
  final Completer<void> completer;
}