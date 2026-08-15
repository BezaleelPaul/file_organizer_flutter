import 'dart:async';

import 'package:file_organizer/services/operation_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OperationQueue', () {
    test('runs ops in FIFO order', () async {
      final queue = OperationQueue();
      final order = <int>[];
      await queue.run(() async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        order.add(1);
      });
      await queue.run(() async => order.add(2));
      expect(order, [1, 2]);
    });

    test('queues an op behind one already running', () async {
      final queue = OperationQueue();
      final order = <String>[];
      final gate = Completer<void>();
      final first = queue.run(() async {
        await gate.future;
        order.add('a');
      });
      final second = queue.run(() async => order.add('b'));
      gate.complete();
      await first;
      await second;
      expect(order, ['a', 'b']);
    });

    test('skipIfBusy drops work when something is running', () async {
      final queue = OperationQueue();
      final order = <int>[];
      final gate = Completer<void>();
      final first = queue.run(() async {
        await gate.future;
        order.add(1);
      });
      final skipped = await queue.run(() async => order.add(2), skipIfBusy: true);
      expect(skipped, isFalse);
      gate.complete();
      await first;
      expect(order, [1]);
    });

    test('reports isBusy while running', () async {
      final queue = OperationQueue();
      final gate = Completer<void>();
      final first = queue.run(() => gate.future);
      expect(queue.isBusy, isTrue);
      gate.complete();
      await first;
      expect(queue.isBusy, isFalse);
    });

    test('an op that throws does not break the queue', () async {
      final queue = OperationQueue();
      final ran = <int>[];
      final first = queue.run(() async {
        throw StateError('boom');
      });
      await first;
      await queue.run(() async => ran.add(1));
      expect(ran, [1]);
    });
  });
}