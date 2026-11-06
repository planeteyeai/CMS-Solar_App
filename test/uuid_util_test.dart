import 'package:cms_site_manager/services/uuid_util.dart';
import 'package:flutter_test/flutter_test.dart';

// Run with:  flutter test test/uuid_util_test.dart
void main() {
  test('client_uuid is a valid v4 UUID, within the server limit of 64 chars', () {
    final re = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
    final seen = <String>{};
    for (var i = 0; i < 500; i++) {
      final u = newUuidV4();
      expect(re.hasMatch(u), isTrue, reason: u);
      expect(u.length, lessThanOrEqualTo(64));
      seen.add(u);
    }
    expect(seen.length, 500); // no collisions
  });
}
