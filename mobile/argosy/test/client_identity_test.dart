import 'package:argosy/api/client_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formats the X-Argosy-Client string (ARGY-262)', () {
    expect(
      formatClientIdentity(
        app: 'android',
        version: '0.32.0',
        build: '78',
        model: 'Pixel 9',
        os: 'Android 36',
      ),
      'argosy-android/0.32.0+78 (Pixel 9; Android 36)',
    );
    expect(
      formatClientIdentity(app: 'tv', version: '0.32.0'),
      'argosy-tv/0.32.0',
    );
  });

  test('the shared header map carries the identity', () {
    ClientIdentity.debugSet('argosy-ios/1.0.0+1 (iPhone15,2; iOS 18.0)');
    expect(ClientIdentity.header, {
      clientHeaderName: 'argosy-ios/1.0.0+1 (iPhone15,2; iOS 18.0)',
    });
  });
}
