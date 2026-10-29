import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selene/tv/tv_device_picker.dart';
import 'package:selene/tv/tv_remote_player.dart';
import 'package:selene/tv/tv_connection_service.dart';
import 'package:selene/tv/tv_models.dart';

import 'tv_connection_service_test.dart' show FakePlatform, FakeTransport, tv;

void main() {
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
