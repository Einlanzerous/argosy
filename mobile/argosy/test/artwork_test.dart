import 'package:argosy/api/artwork.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ArtworkResolver', () {
    const base = 'http://10.0.0.20:8097';

    test('prepends the base URL to a relative artwork path', () {
      expect(const ArtworkResolver(base)('/artwork/a/b.jpg'),
          'http://10.0.0.20:8097/artwork/a/b.jpg');
    });

    test('joins a base-with-trailing-slash and a bare path cleanly', () {
      expect(const ArtworkResolver('$base/')('artwork/x.jpg'),
          'http://10.0.0.20:8097/artwork/x.jpg');
    });

    test('passes absolute URLs through unchanged', () {
      expect(const ArtworkResolver(base)('https://cdn/x.jpg'),
          'https://cdn/x.jpg');
    });

    test('null/empty → null so callers fall back to the placeholder', () {
      expect(const ArtworkResolver(base)(null), isNull);
      expect(const ArtworkResolver(base)(''), isNull);
    });
  });
}
