import 'dart:typed_data';

import 'package:webapp/models/booking.dart';

/// Retains one immutable submission across failed saves, without reusing its
/// identity for a different form payload. No listeners or background retries.
class PendingBookingSubmission {
  Map<String, dynamic>? _inputs;
  Map<String, dynamic>? _booking;
  final _frozenBytes = Set<Uint8List>.identity();

  Booking resolve(Map<String, dynamic> inputs, Booking Function() create) {
    if (_booking == null || !_equal(_inputs, inputs)) {
      final booking = create();
      _frozenBytes.clear();
      final photoCopies = Map<Uint8List, Uint8List>.identity();
      _inputs = _copy(inputs, photoCopies) as Map<String, dynamic>;
      _booking = _copy(booking.toMap(), photoCopies) as Map<String, dynamic>;
    }
    return Booking.fromMap(_copy(_booking!) as Map<String, dynamic>);
  }

  void clear() {
    _inputs = null;
    _booking = null;
    _frozenBytes.clear();
  }

  dynamic _copy(dynamic value, [Map<Uint8List, Uint8List>? photoCopies]) {
    if (value is Map) {
      return value.map<String, dynamic>(
        (key, item) => MapEntry(key.toString(), _copy(item, photoCopies)),
      );
    }
    if (value is Uint8List) {
      if (_frozenBytes.contains(value)) {
        return value;
      }
      final frozen =
          photoCopies?.putIfAbsent(
            value,
            () => Uint8List.fromList(value).asUnmodifiableView(),
          ) ??
          Uint8List.fromList(value).asUnmodifiableView();
      _frozenBytes.add(frozen);
      return frozen;
    }
    if (value is List<int>) {
      return List<int>.from(value);
    }
    if (value is List) {
      return value.map((item) => _copy(item, photoCopies)).toList();
    }
    return value;
  }

  static bool _equal(dynamic left, dynamic right) {
    if (left is Map && right is Map) {
      return left.length == right.length &&
          left.keys.every(
            (key) => right.containsKey(key) && _equal(left[key], right[key]),
          );
    }
    if (left is List && right is List) {
      if (left.length != right.length) {
        return false;
      }
      for (var index = 0; index < left.length; index++) {
        if (!_equal(left[index], right[index])) {
          return false;
        }
      }
      return true;
    }
    return left == right;
  }
}
