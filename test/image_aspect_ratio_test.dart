import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:webapp/widgets/shared/app_profile_avatar.dart';

void main() {
  for (final dimensions in [(400, 200), (200, 400)]) {
    testWidgets(
      'avatar decode preserves ${dimensions.$1}:${dimensions.$2} and cover crops',
      (tester) async {
        final bytes = img.encodePng(
          img.Image(width: dimensions.$1, height: dimensions.$2),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: AppProfileAvatar(radius: 25, memoryBytes: bytes),
            ),
          ),
        );
        final widget = tester.widget<Image>(find.byType(Image));
        expect(widget.fit, BoxFit.cover);
        final provider = widget.image as ResizeImage;
        final info = await tester.runAsync(() async {
          // Evict the widget's pending fake-async decode before real IO decoding.
          await provider.evict();
          final stream = provider.resolve(ImageConfiguration.empty);
          final completed = Completer<ImageInfo>();
          final listener = ImageStreamListener((info, _) {
            if (!completed.isCompleted) completed.complete(info);
          }, onError: (Object e, StackTrace? s) => completed.completeError(e, s));
          stream.addListener(listener);
          try {
            return await completed.future.timeout(const Duration(seconds: 5));
          } finally {
            stream.removeListener(listener);
          }
        });
        expect(
          info!.image.width / info.image.height,
          dimensions.$1 / dimensions.$2,
        );
        expect(info.image.width, lessThanOrEqualTo(provider.width!));
        expect(info.image.height, lessThanOrEqualTo(provider.height!));
        info.dispose();
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
