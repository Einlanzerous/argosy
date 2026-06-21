import 'package:argosy/api/stream_urls.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StreamUrls', () {
    const base = 'http://10.0.0.20:8097';

    test('appends ?token= when a token is present', () {
      final urls = StreamUrls(base, 'abc123');
      expect(
        urls.streamItem('item-1').toString(),
        'http://10.0.0.20:8097/api/v1/items/item-1/stream?token=abc123',
      );
      expect(
        urls.subtitle('item-1', 'track-2').toString(),
        'http://10.0.0.20:8097/api/v1/items/item-1/subtitles/track-2?token=abc123',
      );
      expect(urls.beacon().queryParameters['token'], 'abc123');
      expect(
        urls.transcodeFile('sess-9', 'index.m3u8').toString(),
        'http://10.0.0.20:8097/api/v1/transcode/sess-9/index.m3u8?token=abc123',
      );
    });

    test('omits the token query param when absent or empty', () {
      expect(StreamUrls(base).beacon().toString(), '$base/api/v1/beacon');
      expect(StreamUrls(base, '').beacon().hasQuery, isFalse);
    });
  });
}
