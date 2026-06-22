import 'dart:async';
import 'dart:convert';

import 'package:argosy/features/beacon/beacon_client.dart';
import 'package:argosy/features/beacon/beacon_event.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('BeaconEvent.tryParse', () {
    test('parses a well-formed position payload', () {
      final ev = BeaconEvent.tryParse(
        '{"userId":"u1","itemId":"i1","positionSeconds":123.5,'
        '"durationSeconds":3600,"watched":false,"originDeviceId":"d9",'
        '"updatedAt":"2026-06-21T00:00:00Z"}',
      );
      expect(ev, isNotNull);
      expect(ev!.itemId, 'i1');
      expect(ev.positionSeconds, 123.5);
      expect(ev.durationSeconds, 3600);
      expect(ev.originDeviceId, 'd9');
      expect(ev.watched, isFalse);
    });

    test('returns null on malformed JSON or a missing itemId', () {
      expect(BeaconEvent.tryParse('not json'), isNull);
      expect(BeaconEvent.tryParse('[1,2,3]'), isNull);
      expect(BeaconEvent.tryParse('{"userId":"u1","positionSeconds":1}'), isNull);
    });
  });

  group('BeaconClient', () {
    Uri url() => Uri.parse('http://h:8097/api/v1/beacon?token=t');

    test('emits only position frames, skipping pings and other events', () async {
      final body = StreamController<List<int>>();
      final client = BeaconClient(
        resolveUrl: url,
        httpClient: MockClient.streaming((req, _) async =>
            http.StreamedResponse(body.stream, 200)),
      );
      addTearDown(client.dispose);

      final events = <BeaconEvent>[];
      client.events.listen(events.add);
      client.start();

      body.add(utf8.encode(': ping\n\n'));
      body.add(utf8.encode(
          'event: position\ndata: {"itemId":"i1","positionSeconds":10,"watched":false}\n\n'));
      // A non-position event must be ignored even with a data payload.
      body.add(utf8.encode('event: hello\ndata: {"itemId":"nope"}\n\n'));
      body.add(utf8.encode(
          'event: position\ndata: {"itemId":"i2","positionSeconds":20,"watched":true}\n\n'));
      await pumpEventQueue();

      expect(events.map((e) => e.itemId), ['i1', 'i2']);
      expect(events[1].watched, isTrue);
    });

    test('reconnects after the stream ends', () async {
      var connects = 0;
      StreamController<List<int>>? live;
      final client = BeaconClient(
        resolveUrl: url,
        baseBackoff: const Duration(milliseconds: 5),
        httpClient: MockClient.streaming((req, _) async {
          connects++;
          if (connects == 1) {
            // First connection delivers nothing and closes immediately.
            return http.StreamedResponse(const Stream<List<int>>.empty(), 200);
          }
          live = StreamController<List<int>>();
          return http.StreamedResponse(live!.stream, 200);
        }),
      );
      addTearDown(client.dispose);

      final events = <BeaconEvent>[];
      client.events.listen(events.add);
      client.start();

      // Wait for the backoff + reconnect, then push on the second connection.
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(connects, greaterThanOrEqualTo(2));
      live!.add(utf8.encode(
          'event: position\ndata: {"itemId":"after","positionSeconds":1,"watched":false}\n\n'));
      await pumpEventQueue();

      expect(events.single.itemId, 'after');
    });

    test('does not connect while there is no token', () async {
      var connects = 0;
      final client = BeaconClient(
        resolveUrl: () => Uri.parse('http://h:8097/api/v1/beacon'),
        baseBackoff: const Duration(milliseconds: 5),
        httpClient: MockClient.streaming((req, _) async {
          connects++;
          return http.StreamedResponse(const Stream<List<int>>.empty(), 200);
        }),
      );
      addTearDown(client.dispose);
      client.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(connects, 0);
    });
  });
}
