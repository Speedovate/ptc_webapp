import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/services/booking_photo_marker_match.dart';

void main() {
  test('pending recovery requires real image bytes and complete metadata', () {
    final original = {
      'pending_upload_id': 'old-upload',
      'pending_upload': true,
      'name': 'image.png',
      'size': 3,
      'mime_type': 'image/png',
      'download_url': 'data:image/png;base64,AQID',
    };
    bool matches(Object? value) => bookingPendingPhotoMatchesBytes(
      photo: value,
      fileName: 'image.png',
      size: 3,
      mimeType: 'image/png',
      bytesBase64: 'AQID',
    );
    expect(matches(original), isTrue);
    for (final key in original.keys) {
      expect(matches({...original, key: null}), isFalse, reason: key);
    }
    for (final url in [
      '[INLINE MEDIA OMITTED: image/png; encoded_chars=4]',
      'https://example.test/photo',
      'data:image/png;base64,invalid!',
      'data:image/jpeg;base64,AQID',
      'data:image/png;base64,AQIE',
      'data:image/png;base64,AQIDBA==',
    ]) {
      expect(matches({...original, 'download_url': url}), isFalse);
    }
  });

  final photo = {
    'pending_upload_id': 'upload1',
    'pending_upload': true,
    'name': 'delivery.jpg',
    'size': 123,
    'mime_type': 'image/jpeg',
  };
  Map<String, dynamic> section(Object value) => {
    'fields': {'delivery_form_photo': value},
  };
  String? match(Map<String, dynamic> outputs) => matchingBookingPhotoStatus(
    booking: {'status_outputs': outputs},
    uploadId: 'upload1',
    fieldKey: 'delivery_form_photo',
    fileName: 'delivery.jpg',
    size: 123,
    mimeType: 'image/jpeg',
  );
  test('finds unique original upload even under a different history key', () {
    expect(match({'new-key': section(photo)}), 'new-key');
  });
  test(
    'missing, duplicate, replacement and mismatched metadata cannot rebind',
    () {
      expect(match({}), isNull);
      expect(match({'a': section(photo), 'b': section(photo)}), isNull);
      expect(
        match({
          'a': section({...photo, 'pending_upload_id': 'other'}),
        }),
        isNull,
      );
      for (final field in ['name', 'size', 'mime_type', 'pending_upload']) {
        expect(
          match({
            'a': section({...photo, field: null}),
          }),
          isNull,
        );
      }
    },
  );

  test(
    'uploaded history accepts sanitized filename but rejects ambiguous objects',
    () {
      Map<String, dynamic> uploaded(String status, {int size = 123}) => {
        'name': 'Screenshot_2026-10-08.png',
        'size': size,
        'mime_type': 'image/png',
        'download_url': 'https://example.test/photo',
        'storage_path':
            'bookings/147/status_outputs/$status/delivery_form_photo/photo.png',
      };
      bool confirmed(Map<String, dynamic> outputs) =>
          bookingPhotoAlreadyUploadedInHistory(
            booking: {'status_outputs': outputs},
            bookingId: '147',
            fieldKey: 'delivery_form_photo',
            fileName: 'Screenshot 2026-10-08.png',
            size: 123,
            mimeType: 'image/png',
          );
      expect(confirmed({'a': section(uploaded('a'))}), isTrue);
      expect(confirmed({'a': section(uploaded('a', size: 124))}), isFalse);
      expect(
        confirmed({
          'a': section({...uploaded('a'), 'mime_type': 'image/jpeg'}),
        }),
        isFalse,
      );
      expect(
        confirmed({
          'a': section({...uploaded('a'), 'pending_upload': true}),
        }),
        isFalse,
      );
      expect(
        confirmed({
          'a': section({
            ...uploaded('a'),
            'storage_path':
                'bookings/other/status_outputs/a/delivery_form_photo/photo.png',
          }),
        }),
        isFalse,
      );
      expect(
        confirmed({'a': section(uploaded('a')), 'b': section(uploaded('b'))}),
        isFalse,
      );
    },
  );
}
