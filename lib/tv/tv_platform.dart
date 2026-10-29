import 'package:flutter/services.dart';

import 'tv_models.dart';

abstract interface class TvPlatform {
  Stream<List<TvDevice>> get devices;
  Future<void> startDiscovery();
  Future<void> stopDiscovery();
  Future<Map<String, dynamic>> readCredentials();
  Future<void> writeCredentials(Map<String, dynamic> value);
}

class AndroidTvPlatform implements TvPlatform {
  static const _methods = MethodChannel('org.moontechlab.selene/tv');
  static const _events = EventChannel('org.moontechlab.selene/tv_devices');
  @override
  Stream<List<TvDevice>> get devices => _events.receiveBroadcastStream().map(
    (event) => (event as List)
        .map((e) => TvDevice.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
  );
  @override
  Future<void> startDiscovery() => _methods.invokeMethod<void>('start');
  @override
  Future<void> stopDiscovery() => _methods.invokeMethod<void>('stop');
  @override
  Future<Map<String, dynamic>> readCredentials() async =>
      Map<String, dynamic>.from(
        (await _methods.invokeMapMethod<String, dynamic>('read'))!,
      );
  @override
  Future<void> writeCredentials(Map<String, dynamic> value) =>
      _methods.invokeMethod<void>('write', value);
}
