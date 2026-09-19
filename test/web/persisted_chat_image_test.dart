@TestOn('browser')
library;

import 'dart:convert';
import 'package:image/image.dart' as img;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/services/persistent_image_cache_store.dart';
import 'package:webapp/widgets/shared/app_cached_network_image.dart';

void main() {
  testWidgets(
    'network failure displays persisted image after a cold memory cache',
    (tester) async {
      final url =
          'http://127.0.0.1:1/offline-avatar-${DateTime.now().microsecondsSinceEpoch}.png';
      final data =
          'data:image/png;base64,${base64Encode(img.encodePng(img.Image(width: 1, height: 1)))}';
      final store = createPersistentImageCacheStore();
      await tester.runAsync(() async {
        await store.initialize();
        await store.writeString(
          'persistent_image_cache:$url',
          jsonEncode({'data_url': data}),
        );
      });
      addTearDown(
        () =>
            tester.runAsync(() => store.remove('persistent_image_cache:$url')),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: AppCachedNetworkImage(imageUrl: url, width: 40, height: 40),
        ),
      );
      for (var i = 0; i < 40; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
        if (tester
            .widgetList<Image>(find.byType(Image))
            .any(
              (image) =>
                  image.image is MemoryImage ||
                  image.image is ResizeImage &&
                      (image.image as ResizeImage).imageProvider is MemoryImage,
            )) {
          break;
        }
      }
      expect(
        tester
            .widgetList<Image>(find.byType(Image))
            .any(
              (image) =>
                  image.image is MemoryImage ||
                  image.image is ResizeImage &&
                      (image.image as ResizeImage).imageProvider is MemoryImage,
            ),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
