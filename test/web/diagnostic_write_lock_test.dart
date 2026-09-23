@TestOn('browser')
library;

// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/services/diagnostic_write_lock.dart';

void main() {
  test(
    'diagnostic writes wait for a lock held by another browser context',
    () async {
      final held = Completer<void>();
      final messages = html.window.onMessage.listen((event) {
        if (event.data == 'diagnostic-test-lock-held' && !held.isCompleted) {
          held.complete();
        }
      });
      final frame = html.IFrameElement();
      frame.srcdoc = '''<script>
      navigator.locks.request('paltranco_sync_diagnostic_outbox_v2', async () => {
        await new Promise(resolve => {
          addEventListener('message', event => {
            if (event.data === 'diagnostic-test-release') resolve();
          }, {once: true});
          parent.postMessage('diagnostic-test-lock-held', '*');
        });
      });
    </script>''';
      html.document.body!.append(frame);
      addTearDown(() async {
        frame.contentWindow?.postMessage('diagnostic-test-release', '*');
        frame.remove();
        await messages.cancel();
      });
      await held.future.timeout(const Duration(seconds: 5));
      var entered = false;
      final pending = withDiagnosticWriteLock(() async {
        entered = true;
      });
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(entered, isFalse);
      frame.contentWindow!.postMessage('diagnostic-test-release', '*');
      await pending.timeout(const Duration(seconds: 5));
      expect(entered, isTrue);
    },
  );

  test('failed diagnostic write releases the browser lock', () async {
    await expectLater(
      withDiagnosticWriteLock(() async {
        throw StateError('injected failure');
      }),
      throwsA(anything),
    );
    var recovered = false;
    await withDiagnosticWriteLock(() async {
      recovered = true;
    }).timeout(const Duration(seconds: 5));
    expect(recovered, isTrue);
  });
}
