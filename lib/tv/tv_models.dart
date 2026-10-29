class TvDevice {
  const TvDevice({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    this.version = 1,
  });
  final String id, name, host;
  final int port, version;
  Uri endpoint(String path) =>
      Uri(scheme: 'https', host: host, port: port, path: '/v1/$path');
  factory TvDevice.fromJson(Map<String, dynamic> j) => TvDevice(
    id: j['id'] as String,
    name: j['name'] as String,
    host: j['host'] as String,
    port: j['port'] as int,
    version: j['version'] as int? ?? 1,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'host': host,
    'port': port,
    'version': version,
  };
}

class TvEpisode {
  const TvEpisode(this.title, this.url);
  final String title, url;
  factory TvEpisode.fromJson(Map<String, dynamic> j) =>
      TvEpisode(j['title'] as String, j['url'] as String);
  Map<String, dynamic> toJson() => {'title': title, 'url': url};
}

class TvMedia {
  const TvMedia({
    required this.title,
    required this.url,
    this.kind = 'vod',
    this.headers = const {},
    this.sourceId = '',
    this.videoId = '',
    this.episodes = const [],
    this.episodeIndex = 0,
    this.startPositionMs = 0,
    this.rate = 1,
    this.liveChannelId = '',
  });
  final String kind, title, url, sourceId, videoId, liveChannelId;
  final Map<String, String> headers;
  final List<TvEpisode> episodes;
  final int episodeIndex, startPositionMs;
  final double rate;
  factory TvMedia.fromJson(Map<String, dynamic> j) => TvMedia(
    title: j['title'] as String,
    url: j['url'] as String,
    kind: j['kind'] as String? ?? 'vod',
    headers: Map<String, String>.from(j['headers'] as Map? ?? {}),
    sourceId: j['sourceId'] as String? ?? '',
    videoId: j['videoId'] as String? ?? '',
    episodes: (j['episodes'] as List? ?? [])
        .map((e) => TvEpisode.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
    episodeIndex: j['episodeIndex'] as int? ?? 0,
    startPositionMs: j['startPositionMs'] as int? ?? 0,
    rate: (j['rate'] as num? ?? 1).toDouble(),
    liveChannelId: j['liveChannelId'] as String? ?? '',
  );
  Map<String, dynamic> toJson() => {
    'kind': kind,
    'title': title,
    'url': url,
    'headers': headers,
    'sourceId': sourceId,
    'videoId': videoId,
    'episodes': episodes.map((e) => e.toJson()).toList(),
    'episodeIndex': episodeIndex,
    'startPositionMs': startPositionMs,
    'rate': rate,
    'liveChannelId': liveChannelId,
  };
  void validate() {
    void checkUrl(String value) {
      final uri = Uri.tryParse(value);
      final host =
          uri?.host.toLowerCase().replaceAll('[', '').replaceAll(']', '') ?? '';
      if (uri == null ||
          !['http', 'https'].contains(uri.scheme) ||
          host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          host == 'localhost' ||
          host.endsWith('.localhost') ||
          host.startsWith('127.') ||
          host == '::1' ||
          host == '0.0.0.0' ||
          host.startsWith('::ffff:127.')) {
        throw const FormatException('TV cannot access this media URL');
      }
    }

    checkUrl(url);
    if (!['vod', 'live'].contains(kind) ||
        title.isEmpty ||
        title.length > 512 ||
        startPositionMs < 0 ||
        startPositionMs > 9007199254740991 ||
        !rate.isFinite ||
        rate < .5 ||
        rate > 2 ||
        episodes.length > 2000 ||
        episodeIndex < 0 ||
        (episodes.isNotEmpty && episodeIndex >= episodes.length) ||
        headers.length > 16) {
      throw const FormatException('Invalid TV media');
    }
    for (final e in episodes) {
      checkUrl(e.url);
    }
    for (final e in headers.entries) {
      if (![
            'user-agent',
            'referer',
            'origin',
            'cookie',
            'authorization',
          ].contains(e.key.toLowerCase()) ||
          e.value.length > 8192 ||
          e.value.contains('\r') ||
          e.value.contains('\n')) {
        throw const FormatException('Invalid media header');
      }
    }
  }
}

class TvStatus {
  const TvStatus({
    this.tvId = '',
    this.ownerClientId = '',
    this.sessionId = '',
    this.mediaId = '',
    this.requestId = '',
    this.state = 'idle',
    this.positionMs = 0,
    this.durationMs = 0,
    this.rate = 1,
    this.capabilities = const [],
    this.error,
  });
  final String tvId, ownerClientId, sessionId, mediaId, requestId, state;
  final int positionMs, durationMs;
  final double rate;
  final List<String> capabilities;
  final String? error;
  factory TvStatus.fromJson(Map<String, dynamic> j) => TvStatus(
    tvId: j['tvId'] as String? ?? '',
    ownerClientId: j['ownerClientId'] as String? ?? '',
    sessionId: j['sessionId'] as String? ?? '',
    mediaId: j['mediaId'] as String? ?? '',
    requestId: j['requestId'] as String? ?? '',
    state: j['state'] as String? ?? 'idle',
    positionMs: j['positionMs'] as int? ?? 0,
    durationMs: j['durationMs'] as int? ?? 0,
    rate: (j['rate'] as num? ?? 1).toDouble(),
    capabilities: List<String>.from(j['capabilities'] as List? ?? []),
    error: j['error'] as String?,
  );
}

enum TvConnectionState {
  local,
  connecting,
  awaitingApproval,
  connected,
  disconnected,
}

class TvFailure implements Exception {
  const TvFailure(this.code, this.message);
  final String code, message;
  @override
  String toString() => message;
}
