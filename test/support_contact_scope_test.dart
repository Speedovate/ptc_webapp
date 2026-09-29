import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/services/support_contact_scope.dart';

void main() {
  final investor = UserModel(id: '30', role: 'investor');
  test('investor sees main support and own drivers/helpers only', () {
    expect(
      canSeeSupportContact(investor, UserModel(id: '1', role: 'admin')),
      true,
    );
    for (final role in ['driver', 'helper']) {
      expect(
        canSeeSupportContact(
          investor,
          UserModel(id: '40', role: role, parentClientId: '30'),
        ),
        true,
      );
      expect(
        canSeeSupportContact(
          investor,
          UserModel(id: '41', role: role, parentClientId: '31'),
        ),
        false,
      );
      expect(
        canSeeSupportContact(investor, UserModel(id: '42', role: role)),
        false,
      );
    }
    for (final role in ['admin', 'dispatcher', 'client', 'investor']) {
      expect(
        canSeeSupportContact(
          investor,
          UserModel(id: '43', role: role, parentClientId: '30'),
        ),
        false,
      );
    }
    expect(canSeeSupportContact(investor, investor), false);
  });
  test('non investor visibility unchanged', () {
    expect(
      canSeeSupportContact(UserModel(id: '1', role: 'admin'), investor),
      true,
    );
  });
}
