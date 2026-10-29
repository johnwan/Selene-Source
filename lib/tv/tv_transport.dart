import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'tv_models.dart';

class TvProbe {
  const TvProbe(this.device, this.certificate);
  final TvDevice device;
  final String certificate;
}

abstract interface class TvTransport {
  Future<TvProbe> probe(TvDevice device, {String? certificate});
  Future<Map<String, dynamic>> request(
    TvDevice device,
    String certificate,
    String path, {
    String? token,
    Map<String, dynamic>? body,
  });
}

class HttpsTvTransport implements TvTransport {
  @override
  Future<TvProbe> probe(TvDevice device, {String? certificate}) async {
    String? observed;
    final info = await _request(
      device,
      certificate,
      'info',
      observe: (value) => observed = value,
    );
    if (info['version'] != 1) {
      throw const TvFailure('update_required', '请更新 Selene-TV 后重试');
    }
    final id = info['tvId'] as String;
    if (device.id.isNotEmpty && id != device.id) {
      throw const TvFailure('identity_changed', '电视身份已改变，请重新选择电视');
    }
    if (observed == null) throw const TvFailure('identity_changed', '无法验证电视身份');
    return TvProbe(
      TvDevice(
        id: id,
        name: info['name'] as String,
        host: device.host,
        port: device.port,
      ),
      observed!,
    );
  }

  @override
  Future<Map<String, dynamic>> request(
    TvDevice device,
    String certificate,
    String path, {
    String? token,
    Map<String, dynamic>? body,
  }) => _request(device, certificate, path, token: token, body: body);

  Future<Map<String, dynamic>> _request(
    TvDevice device,
    String? certificate,
    String path, {
    String? token,
    Map<String, dynamic>? body,
    void Function(String)? observe,
  }) async {
    // An empty root store guarantees every peer is checked by the pin callback,
    // including publicly trusted certificates. Initial TOFU is info-only.
    if (certificate == null && path != 'info') {
      throw const TvFailure('identity_changed', '缺少电视身份');
    }
    final context = SecurityContext(withTrustedRoots: false);
    final client = HttpClient(context: context)
      ..connectionTimeout = const Duration(seconds: 5)
      ..findProxy = (_) => 'DIRECT';
    String? initialCertificate;
    bool verifyCertificate(X509Certificate cert, String host, int port) {
      final value = base64Encode(cert.der);
      if (host != device.host || port != device.port) return false;
      if (certificate != null && value != certificate) return false;
      if (initialCertificate != null && initialCertificate != value) {
        return false;
      }
      initialCertificate = value;
      observe?.call(value);
      return true;
    }

    // Android's Netty TLS provider requires an explicit ALPN offer. HttpClient
    // otherwise offers none. Its socket factory keeps pinning intact and
    // negotiates only the HTTP version this protocol actually uses.
    client.connectionFactory = (uri, proxyHost, proxyPort) =>
        SecureSocket.startConnect(
          device.host,
          device.port,
          context: context,
          supportedProtocols: const ['http/1.1'],
          onBadCertificate: (cert) =>
              verifyCertificate(cert, device.host, device.port),
        );
    try {
      return await (() async {
        if (![
          'info',
          'pair',
          'pair/result',
          'connect',
          'status',
          'play',
          'command',
        ].contains(path)) {
          throw const TvFailure('invalid_request', '无效的操作');
        }
        final get = path == 'info' || path == 'status';
        final request = await client.openUrl(
          get ? 'GET' : 'POST',
          device.endpoint(path),
        );
        request.followRedirects = false;
        request.headers.contentType = ContentType.json;
        if (token != null) {
          request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
        }
        if (!get) {
          final bytes = utf8.encode(jsonEncode(body ?? {}));
          if (bytes.length > 262144) {
            throw const TvFailure('payload_too_large', '播放列表过大');
          }
          request.add(bytes);
        }
        final response = await request.close();
        final chunks = <int>[];
        await for (final chunk in response) {
          if (chunks.length + chunk.length > 262144) {
            throw const TvFailure('payload_too_large', '电视响应过大');
          }
          chunks.addAll(chunk);
        }
        Map<String, dynamic> json;
        try {
          json = Map<String, dynamic>.from(jsonDecode(utf8.decode(chunks)));
        } catch (_) {
          throw const TvFailure('update_required', '电视响应无效，请更新 Selene-TV');
        }
        if (response.statusCode != 200) {
          final code = json['code'] as String? ?? 'request_failed';
          throw TvFailure(code, errorMessage(code));
        }
        return json;
      })().timeout(const Duration(seconds: 12));
    } on TvFailure {
      rethrow;
    } on HandshakeException {
      throw const TvFailure('identity_changed', '电视身份验证失败，请先忘记电视再重新连接');
    } on TimeoutException {
      throw const TvFailure('offline', '连接电视超时，请重试');
    } catch (_) {
      throw const TvFailure('offline', '无法连接电视，请检查同一网络和 Selene-TV 是否打开');
    } finally {
      client.close(force: true);
    }
  }

  static String errorMessage(String code) => switch (code) {
    'unauthorized' => '连接授权已失效，请忘记电视并重新连接',
    'controller_busy' => '其他手机正在控制此电视',
    'tv_not_ready' => '请在电视上打开 Selene-TV',
    'pairing_busy' => '电视正在处理另一台手机的请求',
    'rate_limited' => '连接请求过于频繁，请稍后再试',
    'stale_session' => '电视已切换视频，请刷新播放状态',
    'invalid_media' => '此视频地址无法在电视上播放',
    _ => '电视未能完成操作，请重试',
  };
}
