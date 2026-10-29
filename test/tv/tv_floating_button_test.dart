import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selene/tv/tv_connection_service.dart';
import 'package:selene/tv/tv_floating_button.dart';
import 'package:selene/tv/tv_models.dart';

import 'tv_connection_service_test.dart' show FakePlatform, FakeTransport, tv;

void main() {
  testWidgets('without an active session the button opens the TV picker', (
    tester,
  ) async {
    final platform = FakePlatform();
    final service = TvConnectionService(
      platform: platform,
      transport: FakeTransport(),
    );
    var chosen = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TvFloatingButton(
            service: service,
            onOpenMedia: (_) {},
            onChoose: () => chosen = true,
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('播放到电视'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('播放到电视'));
    expect(chosen, isTrue);
    await tester.pumpWidget(const SizedBox());
    service.dispose();
    await platform.events.close();
  });
  testWidgets('shows the TV title and opens the existing media', (
    tester,
  ) async {
    final platform = FakePlatform();
    final service = TvConnectionService(
      platform: platform,
      transport: FakeTransport(),
    );
    service.selected = tv;
    service.media = const TvMedia(
      title: 'Movie',
      url: 'https://example.com/movie',
    );
    service.status = const TvStatus(
      sessionId: 'active',
      state: 'playing',
      title: 'Episode 2',
    );
    TvMedia? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TvFloatingButton(
            service: service,
            onOpenMedia: (media) => opened = media,
            onChoose: () {},
          ),
        ),
      ),
    );
    expect(find.text('Episode 2'), findsNothing);
    await tester.tap(find.byTooltip('播放到电视'));
    await tester.pumpAndSettle();
    expect(find.text('Episode 2'), findsOneWidget);
    await tester.tap(find.text('Episode 2'));
    expect(opened?.title, 'Movie');
    await tester.pumpWidget(const SizedBox());
    service.dispose();
    await platform.events.close();
  });
  testWidgets('expands, collapses after three seconds and can be dragged', (
    tester,
  ) async {
    final platform = FakePlatform();
    final service = TvConnectionService(
      platform: platform,
      transport: FakeTransport(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TvFloatingButton(
            service: service,
            onOpenMedia: (_) {},
            onChoose: () {},
          ),
        ),
      ),
    );
    final button = find.byTooltip('播放到电视');
    final before = tester.getCenter(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('播放到电视'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('播放到电视'), findsNothing);
    final gesture = await tester.startGesture(tester.getCenter(button));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(-150, -100));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.getCenter(button).dx, lessThan(before.dx - 100));
    expect(tester.getCenter(button).dy, lessThan(before.dy - 50));
    final edgeGesture = await tester.startGesture(tester.getCenter(button));
    await tester.pump(const Duration(milliseconds: 600));
    await edgeGesture.moveBy(const Offset(-1000, 0));
    await tester.pump();
    await edgeGesture.up();
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('播放到电视'), findsOneWidget);
    expect(tester.getSize(find.text('播放到电视')).width, greaterThan(50));
    await tester.pumpWidget(const SizedBox());
    service.dispose();
    await platform.events.close();
  });
}
