@TestOn('browser')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/widgets/shared/app_profile_avatar.dart';

// Serve a PNG on another origin without Access-Control-Allow-Origin, then run
// with --dart-define=CORS_TEST_IMAGE_URL=http://127.0.0.1:8783/avatar.png.
const _imageUrl = String.fromEnvironment('CORS_TEST_IMAGE_URL');

void main() {
  testWidgets(
    'profile photo displays when CORS blocks byte fetching',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppProfileAvatar(
              radius: 24,
              photo: _imageUrl,
              fallbackText: 'AC',
            ),
          ),
        ),
      );
      for (var i = 0; i < 60; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
        if (find.byType(HtmlElementView).evaluate().isNotEmpty) break;
      }
      expect(find.byType(HtmlElementView), findsWidgets);
      expect(find.byIcon(Icons.broken_image_rounded), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
    skip: _imageUrl.isEmpty,
  );
}
