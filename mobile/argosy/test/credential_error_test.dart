import 'package:argosy/features/auth/auth_controller.dart';
import 'package:argosy_api/api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a 401 from a credential endpoint is a wrong password, not an expiry', () {
    final failure = AuthController.mapCredentialError(
      ApiException(401, 'invalid credentials'),
    );
    expect(failure.message, 'Incorrect email or password.');
    expect(failure.statusCode, 401);
  });

  test('other failures keep the generic mapping', () {
    final failure = AuthController.mapCredentialError(ApiException(500, 'x'));
    expect(failure.message, 'The server had a problem. Try again shortly.');
  });
}
