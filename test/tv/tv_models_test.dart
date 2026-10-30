import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:selene/tv/tv_models.dart';

void main() {
  test(
    'remote media carries cover metadata without altering legacy payloads',
    () {
      const media = TvMedia(
        title: 'Movie',
        url: 'https://example.com/v',
        coverUrl: 'https://images.example.com/poster.jpg',
      );
      expect(
        TvMedia.fromJson(media.toJson()).coverUrl,
        'https://images.example.com/poster.jpg',
      );
      expect(
        const TvMedia(
          title: 'Movie',
          url: 'https://example.com/v',
        ).toJson().containsKey('coverUrl'),
        isFalse,
      );
    },
  );
  test('shared movie fixture preserves selected position and episode', () {
    final json = jsonDecode(
      File('test/fixtures/tv_protocol/movie.json').readAsStringSync(),
    );
    final media = TvMedia.fromJson(json['media']);
    expect(media.startPositionMs, 42000);
    expect(media.episodes.length, 2);
    expect(media.toJson(), json['media']);
  });
  test('live capabilities do not advertise seeking', () {
    final status = TvStatus.fromJson(
      jsonDecode(
        File('test/fixtures/tv_protocol/live-status.json').readAsStringSync(),
      ),
    );
    expect(status.capabilities.contains('seek'), isFalse);
    expect(status.state, 'playing');
  });
  test('rejects local files, loopback, invalid positions and rates', () {
    for (final url in [
      'file:///private/video',
      'http://127.0.0.1/a',
      'http://localhost/a',
      'http://[::1]/a',
    ]) {
      expect(
        () => TvMedia(title: 'test', url: url).validate(),
        throwsFormatException,
      );
    }
    expect(
      () => TvMedia(
        title: 'test',
        url: 'https://example.com/a',
        startPositionMs: -1,
      ).validate(),
      throwsFormatException,
    );
    expect(
      () => TvMedia(
        title: 'test',
        url: 'https://example.com/a',
        rate: 9,
      ).validate(),
      throwsFormatException,
    );
  });
}
