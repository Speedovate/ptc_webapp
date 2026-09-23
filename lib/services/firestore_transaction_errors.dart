import 'package:cloud_firestore/cloud_firestore.dart';

bool isBoxedTransactionError(String message) => message.toLowerCase().contains(
  'dart exception thrown from converted future',
);

/// Preserve callback errors before Flutter Web turns the rejected Future into
/// a JS error. Do not replace commit/network failures with a prior retry error.
Future<void> runTransactionWithOriginalErrors(
  FirebaseFirestore firestore,
  Future<void> Function(Transaction) action,
) async {
  Object? callbackError;
  StackTrace? callbackStack;
  try {
    await firestore.runTransaction<void>((transaction) async {
      callbackError = null;
      callbackStack = null;
      try {
        await action(transaction);
      } catch (error, stack) {
        callbackError = error;
        callbackStack = stack;
        rethrow;
      }
    });
  } catch (error) {
    if (callbackError != null && isBoxedTransactionError(error.toString())) {
      Error.throwWithStackTrace(callbackError!, callbackStack!);
    }
    rethrow;
  }
}
