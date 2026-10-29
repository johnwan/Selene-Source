import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:selene/tv/tv_models.dart';
import 'package:selene/tv/tv_transport.dart';

void main() {
  late Directory folder;
  late HttpServer server;
  late TvDevice device;
  final transport = HttpsTvTransport();
  String? observedToken;
  setUpAll(() async {
    folder = await Directory.systemTemp.createTemp('selene-tls-test-');
    final openssl = Platform.isWindows
        ? r'C:\Program Files\Git\usr\bin\openssl.exe'
        : 'openssl';
    final generated = await Process.run(openssl, [
      'req',
      '-x509',
      '-newkey',
      'rsa:2048',
      '-nodes',
      '-keyout',
      '${folder.path}/key.pem',
      '-out',
      '${folder.path}/cert.pem',
      '-days',
      '1',
      '-subj',
      '/CN=Selene-TV-test',
    ]);
    expect(generated.exitCode, 0);
    final context = SecurityContext()
      ..useCertificateChain('${folder.path}/cert.pem')
      ..usePrivateKey('${folder.path}/key.pem');
    server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      context,
    );
    device = TvDevice(
      id: 'test-tv',
      name: 'Test TV',
      host: '127.0.0.1',
      port: server.port,
    );
    server.listen((request) async {
      observedToken = request.headers.value(HttpHeaders.authorizationHeader);
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path.endsWith('/info')) {
        request.response.write(
          jsonEncode({'version': 1, 'tvId': 'test-tv', 'name': 'Test TV'}),
        );
      } else if (request.uri.path.endsWith('/status')) {
        request.response.statusCode = 302;
        request.response.headers.set('location', 'https://example.com/stolen');
        request.response.write('{"code":"redirect_refused"}');
      } else {
        request.response.write('{"state":"idle"}');
      }
      await request.response.close();
    });
  });
  tearDownAll(() async {
    await server.close(force: true);
    for (final file in folder.listSync()) {
      await file.delete();
    }
    await folder.delete();
  });
  test(
    'TOFU probe obtains a certificate and pinned requests authenticate',
    () async {
      final probe = await transport.probe(device);
      expect(probe.certificate, isNotEmpty);
      await transport.request(
        device,
        probe.certificate,
        'connect',
        token: 'test-token',
      );
      expect(observedToken, 'Bearer test-token');
    },
  );
  test('wrong pin is rejected before an authorization token is sent', () async {
    observedToken = null;
    await expectLater(
      transport.request(device, 'wrong-pin', 'connect', token: 'must-not-leak'),
      throwsA(
        isA<TvFailure>().having((e) => e.code, 'code', 'identity_changed'),
      ),
    );
    expect(observedToken, isNull);
  });
  test('authenticated redirects are never followed', () async {
    final probe = await transport.probe(device);
    await expectLater(
      transport.request(
        device,
        probe.certificate,
        'status',
        token: 'test-token',
      ),
      throwsA(
        isA<TvFailure>().having((e) => e.code, 'code', 'redirect_refused'),
      ),
    );
  });
}
