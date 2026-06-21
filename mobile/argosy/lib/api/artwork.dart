import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_providers.dart';

/// Resolves the server's *relative* artwork paths (`/artwork/...`, served
/// unauthenticated by the static file handler) into fully-qualified URLs the
/// Flutter `Image.network` loader can fetch. Pass-through for anything already
/// absolute, and null for empty/missing artwork so callers fall back to the
/// hatch placeholder.
class ArtworkResolver {
  const ArtworkResolver(this._baseUrl);

  final String _baseUrl;

  String? call(String? url) {
    if (url == null || url.isEmpty) return null;
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    final base = _baseUrl.endsWith('/')
        ? _baseUrl.substring(0, _baseUrl.length - 1)
        : _baseUrl;
    return url.startsWith('/') ? '$base$url' : '$base/$url';
  }
}

/// Rebuilds when the server address changes (e.g. after pairing).
final artworkResolverProvider = Provider<ArtworkResolver>(
  (ref) => ArtworkResolver(ref.watch(baseUrlProvider)),
);
