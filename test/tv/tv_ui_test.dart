import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selene/tv/tv_device_picker.dart';
import 'package:selene/tv/tv_remote_player.dart';
import 'package:selene/tv/tv_connection_service.dart';
import 'package:selene/tv/tv_models.dart';

import 'tv_connection_service_test.dart' show FakePlatform, FakeTransport, tv;

void main() {
  testWidgets('play after stop starts a new TV session', (tester) async {
    final platform = FakePlatform();
    final transport = FakeTransport();
    platform.saved['trusted'] = {
      'tv1': {'certificate': 'certificate', 'token': 'token'},
    };
    final s = TvConnectionService(platform: platform, transport: transport);
    await s.initialize();
    s.selected = tv;
    s.state = TvConnectionState.connected;
    s.media = const TvMedia(title: 'Movie', url: 'https://example.com/v');
    s.status = const TvStatus(state: 'idle');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TvRemotePlayer(service: s, onPlayHere: () {}),
        ),
      ),
    );
    await tester.tap(find.byTooltip('播放电视视频'));
    await tester.pump();
    expect(transport.plays, 1);
    await tester.pumpWidget(const SizedBox());
    s.dispose();
    await platform.events.close();
  });
  testWidgets('picker lists TVs and selecting calls only the service', (
    tester,
  ) async {
    final platform = FakePlatform();
    final transport = FakeTransport();
    final s = TvConnectionService(
      platform: platform,
      transport: transport,
      interval: const Duration(milliseconds: 1),
    );
    await s.initialize();
    platform.events.add([tv]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TvDevicePicker(service: s)),
      ),
    );
    expect(find.text('在此手机播放'), findsOneWidget);
    expect(find.text('TV'), findsOneWidget);
    await tester.tap(find.text('TV'));
    await tester.pump();
    expect(transport.plays, 0);
    await tester.pump(const Duration(milliseconds: 5));
    await tester.pumpWidget(const SizedBox());
    s.dispose();
    await platform.events.close();
  });
  testWidgets(
    'remote panel shows destination and never contains local player',
    (tester) async {
      final platform = FakePlatform();
      final transport = FakeTransport();
      final s = TvConnectionService(platform: platform, transport: transport);
      s.selected = tv;
      s.state = TvConnectionState.connected;
      s.status = const TvStatus(
        state: 'playing',
        capabilities: ['play', 'pause', 'stop'],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 260,
              child: TvRemotePlayer(service: s, onPlayHere: () {}),
            ),
          ),
        ),
      );
      expect(find.textContaining('TV'), findsWidgets);
      expect(find.byIcon(Icons.pause), findsOneWidget);
      expect(find.byType(AndroidView), findsNothing);
      await tester.pumpWidget(const SizedBox());
      s.dispose();
      await platform.events.close();
    },
  );
}
