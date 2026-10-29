// Isolated device QA entry point. Build with an application-ID suffix; never
// install this fake-account harness over a user's normal Selene installation.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:selene/services/background_audio_service.dart';
import 'package:selene/services/theme_service.dart';
import 'package:selene/services/user_data_service.dart';
import 'package:selene/tv/tv_connection_service.dart';
import 'package:selene/tv/tv_device_picker.dart';
import 'package:selene/tv/tv_models.dart';
import 'package:selene/screens/player_screen.dart';
import 'package:selene/screens/live_player_screen.dart';
import 'package:selene/models/live_channel.dart';
import 'package:selene/models/live_source.dart';

const sample = String.fromEnvironment(
  'TV_QA_MEDIA_URL',
  defaultValue: 'http://10.0.2.2:8765/sample.mp4',
);
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await BackgroundAudioService.initialize();
  await TvConnectionService.initializeAndroid();
  final backend = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  backend.listen((request) async {
    if (request.uri.path == '/api/playrecords' && request.method == 'POST') {
      debugPrint('QA_PHONE_PROGRESS_WRITE');
    }
    request.response.headers.contentType = ContentType.json;
    request.response.write(
      jsonEncode(
        request.uri.path == '/api/detail'
            ? {
                'id': 'bunny',
                'title': 'Big Buck Bunny',
                'poster': '',
                'source': 'qa',
                'source_name': 'Test media',
                'year': '2008',
                'episodes': [sample, sample],
                'episodes_titles': ['Episode 1', 'Episode 2'],
              }
            : <String, dynamic>{},
      ),
    );
    await request.response.close();
  });
  await UserDataService.saveUserData(
    serverUrl: 'http://127.0.0.1:${backend.port}',
    username: 'QA',
    password: '',
    cookies: 'qa=test',
  );
  await UserDataService.savePreferSpeedTest(false);
  Timer.periodic(
    const Duration(seconds: 5),
    (_) => debugPrint(
      'TV_QA state=${TvConnectionService.instance.status.state} localMedia=${BackgroundAudioService.handler?.mediaItem.value?.id}',
    ),
  );
  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeService(),
      child: const MaterialApp(home: QaHome()),
    ),
  );
}

class QaHome extends StatelessWidget {
  const QaHome({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Selene TV device test')),
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: () => showTvDevicePicker(context),
            child: const Text('Choose TV'),
          ),
          TextButton(
            onPressed: () => TvConnectionService.instance.select(
              const TvDevice(
                id: '',
                name: 'Test TV',
                host: String.fromEnvironment(
                  'TV_QA_HOST',
                  defaultValue: '10.0.2.2',
                ),
                port: 45844,
              ),
            ),
            child: const Text('Connect test receiver'),
          ),
          TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const PlayerScreen(
                  source: 'qa',
                  id: 'bunny',
                  title: 'Big Buck Bunny',
                  year: '2008',
                ),
              ),
            ),
            child: const Text('Open actual movie screen'),
          ),
          TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => LivePlayerScreen(
                  channel: LiveChannel(
                    id: 'qa-live',
                    tvgId: '',
                    name: 'QA live stream',
                    logo: '',
                    group: 'Test',
                    url: sample,
                  ),
                  source: LiveSource(
                    key: 'qa',
                    name: 'Test',
                    url: '',
                    ua: 'Selene-QA',
                    epg: '',
                    from: '',
                    disabled: false,
                  ),
                ),
              ),
            ),
            child: const Text('Open actual live screen'),
          ),
        ],
      ),
    ),
  );
}
