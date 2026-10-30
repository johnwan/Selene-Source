import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/widgets.dart';

import 'tv_models.dart';
import 'tv_platform.dart';
import 'tv_transport.dart';

String newTvId() => List.generate(
  24,
  (_) => Random.secure().nextInt(256),
).map((v) => v.toRadixString(16).padLeft(2, '0')).join();

class TvConnectionService extends ChangeNotifier with WidgetsBindingObserver {
  TvConnectionService({
    required this.platform,
    required this.transport,
    this.interval = const Duration(seconds: 1),
  });
  static final instance = TvConnectionService(
    platform: AndroidTvPlatform(),
    transport: HttpsTvTransport(),
  );
  final TvPlatform platform;
  final TvTransport transport;
  final Duration interval;
  Map<String, dynamic> _credentials = {};
  Map<String, dynamic> get _trusted =>
      Map<String, dynamic>.from(_credentials['trusted'] as Map? ?? {});
  Map<String, dynamic> get _pendingPairings =>
      Map<String, dynamic>.from(_credentials['pendingPairings'] as Map? ?? {});
  String get clientId => _credentials['clientId'] as String? ?? '';
  List<TvDevice> devices = [];
  TvDevice? selected;
  TvStatus status = const TvStatus();
  TvMedia? media;
  TvConnectionState state = TvConnectionState.local;
  TvFailure? error;
  bool get remoteSelected => selected != null;
  bool get controlsOwned =>
      status.ownerClientId.isEmpty || status.ownerClientId == clientId;
  int destinationRevision = 0;
  TvDevice? _detachedDevice;
  String? _detachedSession;
  StreamSubscription<List<TvDevice>>? _subscription;
  Timer? _poll;
  Future<void> _playQueue = Future<void>.value();
  int _mutationRevision = 0;
  bool _mediaPending = false;
  bool get mediaRequestPending => _mediaPending;
  int _generation = 0, _mediaGeneration = 0;
  bool _foreground = true,
      _disposed = false,
      _initialized = false,
      _polling = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _credentials = jsonDecode(
      jsonEncode(await platform.readCredentials()),
    ) as Map<String, dynamic>;
    _subscription = platform.devices.listen(
      (values) {
        devices = values;
        // Discovery may reconnect an explicitly selected TV in this process,
        // but must not select the previous destination after an app restart.
        final current = selected?.id;
        final found = values.where((d) => d.id == current).firstOrNull;
        if (_foreground &&
            found != null &&
            _trusted.containsKey(found.id) &&
            (state == TvConnectionState.local ||
                state == TvConnectionState.disconnected ||
                selected?.host != found.host ||
                selected?.port != found.port)) {
          unawaited(select(found, automatic: true));
        }
        _notify();
      },
      onError: (_) {
        error = const TvFailure('discovery_failed', '无法发现电视，请重试或输入电视地址');
        _notify();
      },
    );
    if (_foreground) await platform.startDiscovery();
  }

  Future<void> select(TvDevice device, {bool automatic = false}) async {
    if (!automatic) destinationRevision++;
    final generation = ++_generation;
    _poll?.cancel();
    selected = device;
    state = TvConnectionState.connecting;
    error = null;
    _notify();
    try {
      var trusted = _trusted[device.id] as Map?;
      var pending = _pendingPairings[device.id] as Map?;
      final probe = await transport.probe(
        device,
        certificate:
            (trusted?['certificate'] ?? pending?['certificate']) as String?,
      );
      if (!_current(generation)) return;
      selected = probe.device;
      trusted ??= _trusted[probe.device.id] as Map?;
      pending ??= _pendingPairings[probe.device.id] as Map?;
      if (trusted != null && trusted['certificate'] != probe.certificate) {
        throw const TvFailure('identity_changed', '电视身份已改变，请忘记后重新连接');
      }
      if (pending != null && pending['certificate'] != probe.certificate) {
        throw const TvFailure('identity_changed', '电视身份已改变，请忘记后重新连接');
      }
      String token;
      if (trusted != null) {
        token = trusted['token'] as String;
      } else {
        pending ??= {'certificate': probe.certificate, 'secret': newTvId()};
        final pendingByTv = _pendingPairings;
        pendingByTv[probe.device.id] = pending;
        if (pendingByTv.length > 32) pendingByTv.remove(pendingByTv.keys.first);
        _credentials['pendingPairings'] = pendingByTv;
        await platform.writeCredentials(_credentials);
        if (!_current(generation)) return;
        final secret = pending['secret'] as String;
        final pair = await transport.request(
          probe.device,
          probe.certificate,
          'pair',
          body: {
            'clientId': clientId,
            'name': _credentials['name'] ?? 'Selene phone',
            'requestSecret': secret,
          },
        );
        if (!_current(generation)) return;
        state = pair['state'] == 'allowed'
            ? TvConnectionState.connecting
            : TvConnectionState.awaitingApproval;
        _notify();
        final deadline = DateTime.now().add(const Duration(seconds: 60));
        Map<String, dynamic> result = pair;
        while (result['state'] == 'pending') {
          await Future<void>.delayed(interval);
          if (!_current(generation)) return;
          result = await transport.request(
            probe.device,
            probe.certificate,
            'pair/result',
            body: {'pairId': pair['pairId'], 'requestSecret': secret},
          );
          if (result['state'] != 'pending') break;
          if (DateTime.now().isAfter(deadline)) {
            throw const TvFailure('pairing_expired', '电视确认已超时，请重试');
          }
        }
        if (result['state'] != 'allowed') {
          throw const TvFailure('pairing_declined', '电视未允许此手机连接');
        }
        if (result['tvId'] != probe.device.id) {
          throw const TvFailure('identity_changed', '电视身份已改变');
        }
        token = result['token'] as String;
        if (!_current(generation)) return;
        final all = _trusted;
        all[probe.device.id] = {
          'token': token,
          'certificate': probe.certificate,
          'device': probe.device.toJson(),
        };
        _credentials['trusted'] = all;
        _credentials['pendingPairings'] = _pendingPairings
          ..remove(probe.device.id);
      }
      final result = await transport.request(
        probe.device,
        probe.certificate,
        'connect',
        token: token,
      );
      if (!_current(generation)) return;
      _credentials['lastSelected'] = probe.device.id;
      await platform.writeCredentials(_credentials);
      if (!_current(generation)) return;
      status = TvStatus.fromJson(result);
      state = TvConnectionState.connected;
      _schedulePolling();
      _notify();
    } catch (e) {
      if (_current(generation)) _failed(e);
    }
  }

  Future<void> retry() async {
    final d = selected;
    if (d != null) await select(d, automatic: true);
  }

  Future<void> selectLocal() async {
    destinationRevision++;
    if (selected != null && status.sessionId.isNotEmpty) {
      _detachedDevice = selected;
      _detachedSession = status.sessionId;
    }
    ++_generation;
    ++_mediaGeneration;
    _poll?.cancel();
    selected = null;
    media = null;
    status = const TvStatus();
    error = null;
    state = TvConnectionState.local;
    _credentials.remove('lastSelected');
    _notify();
    if (_initialized) await platform.writeCredentials(_credentials);
  }

  Future<TvHandoff> handoffToLocal() async {
    if (selected == null && _detachedDevice != null) {
      await select(_detachedDevice!, automatic: true);
      if (status.sessionId != _detachedSession) {
        throw const TvFailure('stale_session', '电视已切换视频，请重新连接后操作');
      }
    }
    if (selected == null || state != TvConnectionState.connected) {
      throw const TvFailure('offline', '无法确认电视停止，请重新连接电视');
    }
    final active = status;
    await send('stop');
    if (error != null || status.state != 'idle') {
      throw error ?? const TvFailure('request_failed', '电视尚未停止');
    }
    await selectLocal();
    _detachedDevice = null;
    _detachedSession = null;
    return TvHandoff(active.positionMs, active.episodeIndex);
  }

  Future<bool> waitUntilPlaying() async {
    final request = status.requestId, generation = _generation;
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (_current(generation) && DateTime.now().isBefore(deadline)) {
      await refreshStatus();
      if (status.requestId != request ||
          status.state == 'failed' ||
          error != null) {
        return false;
      }
      if (status.state == 'playing') return true;
      await Future<void>.delayed(interval);
    }
    return false;
  }

  Future<void> forget(String tvId) async {
    final all = _trusted..remove(tvId);
    _credentials['trusted'] = all;
    _credentials['pendingPairings'] = _pendingPairings..remove(tvId);
    if (selected?.id == tvId) await selectLocal();
    await platform.writeCredentials(_credentials);
    _notify();
  }

  Future<void> startMedia(TvMedia value, {bool takeOver = false}) {
    if (!remoteSelected) return Future<void>.value();
    media = value;
    _mediaPending = true;
    ++_mutationRevision;
    final generation = _generation, mediaGeneration = ++_mediaGeneration;
    final task = _playQueue.then(
      (_) => _startMedia(value, takeOver, generation, mediaGeneration),
    );
    _playQueue = task.catchError((Object _) {});
    return task;
  }

  Future<void> _startMedia(
    TvMedia value,
    bool takeOver,
    int generation,
    int mediaGeneration,
  ) async {
    if (!_current(generation) || mediaGeneration != _mediaGeneration) return;
    final revision = ++_mutationRevision;
    try {
      value.validate();
      if (state != TvConnectionState.connected) {
        throw const TvFailure('offline', '电视未连接，请重试连接');
      }
      final mediaJson = value.toJson();
      if (!(selected?.capabilities.contains('coverMetadata') ?? false)) {
        mediaJson.remove('coverUrl');
      }
      final response = await _call(
        'play',
        body: {
          'requestId': newTvId(),
          'mediaId': newTvId(),
          'takeOver': takeOver,
          'media': mediaJson,
        },
      );
      if (!_current(generation) ||
          mediaGeneration != _mediaGeneration ||
          revision != _mutationRevision) {
        return;
      }
      ++_mutationRevision;
      status = TvStatus.fromJson(response);
      error = null;
      _notify();
    } catch (e) {
      if (_current(generation) && mediaGeneration == _mediaGeneration) {
        _failed(
          e,
          disconnect:
              e is! TvFailure ||
              ![
                'controller_busy',
                'invalid_media',
                'invalid_request',
              ].contains(e.code),
        );
      }
    } finally {
      if (mediaGeneration == _mediaGeneration) {
        _mediaPending = false;
        _notify();
      }
    }
  }

  Future<void> send(String action, {int? positionMs, double? rate}) async {
    final generation = _generation;
    final revision = ++_mutationRevision;
    try {
      if (state != TvConnectionState.connected) {
        throw const TvFailure('offline', '电视未连接');
      }
      final response = await _call(
        'command',
        body: {
          'requestId': newTvId(),
          'sessionId': status.sessionId,
          'mediaId': status.mediaId,
          'action': action,
          'positionMs': ?positionMs,
          'rate': ?rate,
        },
      );
      if (_current(generation) && revision == _mutationRevision) {
        ++_mutationRevision;
        status = TvStatus.fromJson(response);
        error = null;
        _notify();
        await refreshStatus();
      }
    } catch (e) {
      if (_current(generation)) {
        _failed(
          e,
          disconnect:
              e is TvFailure &&
              ['offline', 'unauthorized', 'identity_changed'].contains(e.code),
        );
      }
    }
  }

  Future<Map<String, dynamic>> _call(
    String path, {
    Map<String, dynamic>? body,
  }) {
    final d = selected!;
    final t = _trusted[d.id] as Map?;
    if (t == null) throw const TvFailure('unauthorized', '电视尚未授权');
    return transport.request(
      d,
      t['certificate'] as String,
      path,
      token: t['token'] as String,
      body: body,
    );
  }

  Future<void> refreshStatus() async {
    if (!remoteSelected ||
        !_foreground ||
        _polling ||
        state != TvConnectionState.connected) {
      return;
    }
    final generation = _generation;
    _polling = true;
    final revision = _mutationRevision;
    try {
      final value = await _call('status');
      if (_current(generation) &&
          revision == _mutationRevision &&
          !_mediaPending) {
        status = TvStatus.fromJson(value);
        _notify();
      }
    } catch (e) {
      if (_current(generation)) _failed(e);
    } finally {
      _polling = false;
    }
  }

  void _schedulePolling() {
    _poll?.cancel();
    if (_foreground) {
      _poll = Timer.periodic(interval, (_) => unawaited(refreshStatus()));
    }
  }

  void _failed(Object e, {bool disconnect = true}) {
    error = e is TvFailure ? e : const TvFailure('request_failed', '操作失败，请重试');
    if (disconnect) {
      state = TvConnectionState.disconnected;
      _poll?.cancel();
    }
    _notify();
  }

  bool _current(int generation) =>
      !_disposed && _generation == generation && _foreground;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> setForeground(bool foreground) async {
    _foreground = foreground;
    if (!foreground) {
      ++_generation;
      _poll?.cancel();
      await platform.stopDiscovery();
    } else {
      await platform.startDiscovery();
      if (selected != null) await retry();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(setForeground(true));
    if ([
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.detached,
    ].contains(state)) {
      unawaited(setForeground(false));
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _poll?.cancel();
    _subscription?.cancel();
    unawaited(platform.stopDiscovery());
    super.dispose();
  }

  static Future<void> initializeAndroid() async {
    if (!Platform.isAndroid) return;
    WidgetsBinding.instance.addObserver(instance);
    try {
      await instance.initialize();
    } catch (_) {
      /* Local playback remains available. */
    }
  }
}
