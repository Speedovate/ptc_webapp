import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/services/booking_photo_marker_match.dart';

void main() {
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
}
