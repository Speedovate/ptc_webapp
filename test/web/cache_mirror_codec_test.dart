@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/requests/cache_mirror_codec.dart';

void main() {
  test(
    'large cache encoding leaves browser events running and remains gzip compatible',
    () async {
      final data = jsonEncode(
        List.generate(
          25000,
          (i) => {'id': '$i', 'notes': 'Booking $i offline action'},
        ),
      );
      var ticks = 0;
      final timer = Timer.periodic(
        const Duration(milliseconds: 1),
        (_) => ticks++,
      );
      try {
        final encoded = await encodeCacheMirror(data);
        expect(ticks, greaterThan(0));
        expect(encoded, startsWith('gzip:'));
        // Older releases can still read mirrors written by the native worker.
        expect(
          utf8.decode(
            GZipDecoder().decodeBytes(base64Decode(encoded.substring(5))),
          ),
          data,
        );
        expect(await decodeCacheMirror(encoded), data);
      } finally {
        timer.cancel();
      }
    },
  );
}
