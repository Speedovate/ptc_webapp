import 'package:flutter/material.dart';
import 'package:webapp/models/booking.dart';

/// Lets related Admin sections open a booking in the shell's inline view.
class BookingSectionNavigationScope extends InheritedWidget {
  const BookingSectionNavigationScope({
    super.key,
    required this.onOpenBooking,
    required super.child,
  });

  final ValueChanged<Booking> onOpenBooking;

  static BookingSectionNavigationScope? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<BookingSectionNavigationScope>();
  }

  void openBooking(Booking booking) => onOpenBooking(booking);

  @override
  bool updateShouldNotify(BookingSectionNavigationScope oldWidget) {
    return onOpenBooking != oldWidget.onOpenBooking;
  }
}
