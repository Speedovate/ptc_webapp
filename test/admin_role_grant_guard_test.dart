import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/repositories/interfaces/auth_repository.dart';
import 'package:webapp/view_models/admin/admin_users.vm.dart';

/// A dispatcher holds users.update by default, so editing a user used to be a
/// path straight to admin: the dropdown listed every role while editing, the
/// submit guard only ran on the create path, and the view model never checked
/// the role at all. All three had to close, because any one of them open is
/// still an escalation.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(AdminUsersViewModel.clearCachedState);
  tearDown(AdminUsersViewModel.clearCachedState);

  AdminUsersViewModel editorAs(String role) => AdminUsersViewModel(
    fallbackCurrentUser: UserModel(id: '8', role: role),
  );

  test('an editor without admin cannot grant the admin role', () {
    final vm = editorAs('dispatcher');

    expect(vm.canUpdateUsers, isTrue, reason: 'dispatchers do edit users');
    expect(vm.canCreateAdminUsers, isFalse);
    expect(vm.canGrantRole('driver'), isTrue);
    expect(vm.canGrantRole('dispatcher'), isTrue);
    expect(vm.canGrantRole('admin'), isFalse);
    expect(
      vm.canGrantRole('ADMIN'),
      isFalse,
      reason: 'case must not slip past',
    );
    expect(vm.canGrantRole(null), isTrue);
  });

  test('an admin can grant every role', () {
    final vm = editorAs('admin');

    expect(vm.canCreateAdminUsers, isTrue);
    for (final role in ['admin', 'manager', 'dispatcher', 'driver', 'helper']) {
      expect(vm.canGrantRole(role), isTrue, reason: role);
    }
  });

  test('promoting a user to admin is refused on the update path', () async {
    final vm = editorAs('dispatcher');

    // This is the escalation itself: a plain edit that hands over admin.
    // Matched on our own message on purpose. A bare throwsA(isA<Exception>())
    // also passes when the repository blows up on something unrelated, which
    // would leave this test green with the guard removed.
    await expectLater(
      vm.updateUser(const UserModel(id: '12', role: 'admin', name: 'Ben')),
      throwsA(
        isA<AuthFailure>().having(
          (failure) => failure.message,
          'message',
          contains('Only admin users can change'),
        ),
      ),
    );
  });

  test('an ordinary edit by a dispatcher is still allowed', () {
    final vm = editorAs('dispatcher');

    // The guard must reject only the escalation, not the office's daily work.
    expect(vm.canGrantRole('helper'), isTrue);
    expect(vm.canGrantRole('client'), isTrue);
    expect(vm.canGrantRole('dispatcher'), isTrue);
  });
}
