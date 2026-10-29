import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:selene/tv/tv_models.dart';
import 'package:selene/tv/tv_platform.dart';
import 'package:selene/tv/tv_transport.dart';
import 'package:selene/tv/tv_connection_service.dart';

class FakePlatform implements TvPlatform {
  Map<String, dynamic> saved = {
    'clientId': 'phone1',
    'name': 'Phone',
    'trusted': <String, dynamic>{},
  };
  final events = StreamController<List<TvDevice>>.broadcast(sync: true);
  int starts = 0, stops = 0;
  @override
  Stream<List<TvDevice>> get devices => events.stream;
  @override
  Future<void> startDiscovery() async {
    starts++;
  }

  @override
  Future<void> stopDiscovery() async {
    stops++;
  }

  @override
  Future<Map<String, dynamic>> readCredentials() async => saved;
  @override
  Future<void> writeCredentials(Map<String, dynamic> value) async {
    saved = value;
  }
}

class FakeTransport implements TvTransport {
  final pairingSecrets = <String, String>{};
  Map<String, dynamic>? statusOverride;
  Completer<Map<String, dynamic>>? delayedStatus;
  Completer<void>? firstPlayGate;
  final playedTitles = <String>[];
  int pairs = 0, plays = 0, connects = 0;
  bool deny = false, fail = false;
  @override
  Future<TvProbe> probe(TvDevice d, {String? certificate}) async =>
      TvProbe(d, certificate ?? 'certificate');
  @override
  Future<Map<String, dynamic>> request(
    TvDevice d,
    String certificate,
    String path, {
    String? token,
    Map<String, dynamic>? body,
  }) async {
    if (path == 'status' && delayedStatus != null) return delayedStatus!.future;
    if ((path == 'status' || path == 'connect') && statusOverride != null) {
      return Map<String, dynamic>.from(statusOverride!);
    }
    if (path == 'command' && body?['action'] == 'stop') {
      statusOverride = {'tvId': d.id, 'state': 'idle'};
      return statusOverride!;
    }
    if (fail) throw const TvFailure('offline', 'TV offline');
    if (path == 'pair') {
      pairingSecrets[d.id] = body!['requestSecret'] as String;
      pairs++;
      return {'pairId': 'p1', 'state': 'pending'};
    }
    if (path == 'pair/result') {
      return {
        'state': deny ? 'declined' : 'allowed',
        'token': 'token',
        'tvId': d.id,
      };
    }
    if (path == 'connect') connects++;
    if (path == 'play') {
      plays++;
      playedTitles.add((body!['media'] as Map)['title'] as String);
      if (plays == 1 && firstPlayGate != null) await firstPlayGate!.future;
      return {
        'tvId': d.id,
        'ownerClientId': 'phone1',
        'sessionId': 's1',
        'mediaId': body['mediaId'],
        'requestId': body['requestId'],
        'state': 'playing',
      };
    }
    return {'tvId': d.id, 'state': 'idle'};
  }
}

const tv = TvDevice(id: 'tv1', name: 'TV', host: '192.168.1.2', port: 1234);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakePlatform platform;
  late FakeTransport transport;
  late TvConnectionService s;
  setUp(() {
    platform = FakePlatform();
    transport = FakeTransport();
    s = TvConnectionService(
      platform: platform,
      transport: transport,
      interval: const Duration(milliseconds: 1),
    );
  });
  tearDown(() {
    s.dispose();
    platform.events.close();
  });
  test('rapid selections serialize sends and latest selection wins', () async {
    await s.initialize();
    await s.select(tv);
    transport.firstPlayGate = Completer<void>();
    final first = s.startMedia(
      const TvMedia(title: 'First', url: 'https://example.com/first'),
    );
    await Future<void>.delayed(Duration.zero);
    final second = s.startMedia(
      const TvMedia(title: 'Second', url: 'https://example.com/second'),
    );
    await Future<void>.delayed(Duration.zero);
    expect(transport.plays, 1);
    transport.firstPlayGate!.complete();
    await first;
    await second;
    expect(transport.playedTitles, ['First', 'Second']);
    expect(s.media!.title, 'Second');
  });
  test(
    'status captured before a new play cannot replace its new session',
    () async {
      await s.initialize();
      await s.select(tv);
      transport.delayedStatus = Completer<Map<String, dynamic>>();
      final poll = s.refreshStatus();
      await s.startMedia(
        const TvMedia(title: 'New movie', url: 'https://example.com/new'),
      );
      final mediaId = s.status.mediaId;
      transport.delayedStatus!.complete({
        'tvId': 'tv1',
        'sessionId': 'old-session',
        'mediaId': 'old-media',
        'requestId': 'old-request',
        'state': 'playing',
      });
      await poll;
      expect(s.status.mediaId, mediaId);
      expect(s.status.sessionId, 's1');
    },
  );
  test('handoff returns the active TV episode with its position', () async {
    await s.initialize();
    await s.select(tv);
    s.status = const TvStatus(
      tvId: 'tv1',
      ownerClientId: 'phone1',
      sessionId: 's1',
      mediaId: 'episode2',
      state: 'playing',
      episodeIndex: 1,
      positionMs: 60000,
    );
    final result = await s.handoffToLocal();
    expect(result.episodeIndex, 1);
    expect(result.positionMs, 60000);
    expect(s.remoteSelected, isFalse);
  });
  test('each TV gets a different private pairing recovery secret', () async {
    await s.initialize();
    await s.select(tv);
    await s.select(
      const TvDevice(
        id: 'tv2',
        name: 'Second TV',
        host: '192.168.1.3',
        port: 1234,
      ),
    );
    expect(
      transport.pairingSecrets['tv1'],
      isNot(transport.pairingSecrets['tv2']),
    );
    expect(transport.pairingSecrets['tv1']!.length, greaterThanOrEqualTo(32));
  });
  test(
    'approves once, persists trust and reconnects without replaying media',
    () async {
      await s.initialize();
      await s.select(tv);
      expect(s.state, TvConnectionState.connected);
      expect(transport.pairs, 1);
      await s.retry();
      expect(transport.pairs, 1);
      expect(transport.plays, 0);
      expect((platform.saved['trusted'] as Map)['tv1']['token'], 'token');
    },
  );
  test('decline creates no stored trust', () async {
    transport.deny = true;
    await s.initialize();
    await s.select(tv);
    expect((platform.saved['trusted'] as Map).isEmpty, isTrue);
    expect(s.state, TvConnectionState.disconnected);
  });
  test(
    'new TV is never selected automatically and local selection clears routing',
    () async {
      await s.initialize();
      platform.events.add([tv]);
      await Future<void>.delayed(Duration.zero);
      expect(s.remoteSelected, isFalse);
      await s.select(tv);
      await s.selectLocal();
      expect(s.remoteSelected, isFalse);
      expect(transport.plays, 0);
    },
  );
  test('disconnect during remote play never calls local fallback', () async {
    await s.initialize();
    await s.select(tv);
    transport.fail = true;
    await s.startMedia(
      const TvMedia(title: 'Movie', url: 'https://example.com/v'),
    );
    expect(s.remoteSelected, isTrue);
    expect(s.state, TvConnectionState.disconnected);
    expect(s.error, isNotNull);
  });
}
