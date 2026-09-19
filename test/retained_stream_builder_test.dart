import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/widgets/shared/retained_stream_builder.dart';

void main() {
  testWidgets(
    'typing and stream errors retain messages; empty update and thread switch clear them',
    (tester) async {
      final first = StreamController<List<String>>();
      final second = StreamController<List<String>>();
      addTearDown(first.close);
      addTearDown(second.close);
      var stream = first.stream;
      late StateSetter rebuild;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return Column(
                  children: [
                    RetainedStreamBuilder<List<String>>(
                      stream: stream,
                      builder: (_, snapshot) =>
                          Text((snapshot.data ?? []).join(', ')),
                    ),
                    TextField(onChanged: (_) => setState(() {})),
                  ],
                );
              },
            ),
          ),
        ),
      );
      first.add(['Saved message']);
      await tester.pump();
      first.addError(StateError('Firestore snapshot decode failure'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Offline draft');
      await tester.pump();
      expect(find.text('Saved message'), findsOneWidget);
      expect(find.text('Offline draft'), findsOneWidget);
      first.add([]);
      await tester.pump();
      first.addError(StateError('offline'));
      await tester.pump();
      expect(find.text('Saved message'), findsNothing);
      first.add(['Other saved message']);
      await tester.pump();
      rebuild(() {
        stream = second.stream;
      });
      await tester.pump();
      expect(find.text('Other saved message'), findsNothing);
      second.addError(StateError('offline'));
      await tester.pump();
      expect(find.text('Other saved message'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      expect(first.hasListener, isFalse);
      expect(second.hasListener, isFalse);
    },
  );
}
