import 'package:cloud_firestore/cloud_firestore.dart';

bool isBoxedTransactionError(String message) => message.toLowerCase().contains(
  'dart exception thrown from converted future',
);

/// Preserve callback errors before Flutter Web turns the rejected Future into
/// a JS error. Do not replace commit/network failures with a prior retry error.
Future<T> runTransactionWithOriginalErrors<T>(
  FirebaseFirestore firestore,
  Future<T> Function(Transaction) action, {
  Duration timeout = const Duration(seconds: 30),
  int maxAttempts = 5,
}) async {
  Object? callbackError;
  StackTrace? callbackStack;
  try {
    return await firestore.runTransaction<T>(
      (transaction) async {
        callbackError = null;
        callbackStack = null;
        try {
          return await action(transaction);
        } catch (error, stack) {
          callbackError = error;
          callbackStack = stack;
          rethrow;
        }
      },
      timeout: timeout,
      maxAttempts: maxAttempts,
    );
  } catch (error) {
    if (callbackError != null && isBoxedTransactionError(error.toString())) {
      Error.throwWithStackTrace(callbackError!, callbackStack!);
    }
    rethrow;
  }
}
