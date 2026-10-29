import 'package:flutter/material.dart';

import 'tv_connection_service.dart';
import 'tv_device_picker.dart';
import 'tv_models.dart';

class TvRemotePlayer extends StatelessWidget {
  const TvRemotePlayer({
    super.key,
    required this.service,
    required this.onPlayHere,
  });
  final TvConnectionService service;
  final VoidCallback onPlayHere;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: service,
    builder: (context, _) {
      final status = service.status;
      final connected = service.state == TvConnectionState.connected;
      final owned = service.controlsOwned;
      return ColoredBox(
        color: const Color(0xFF101820),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.tv, color: Colors.white),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        service.selected?.name ?? 'Selene-TV',
                        style: const TextStyle(color: Colors.white),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      tooltip: '选择播放设备',
                      onPressed: () =>
                          showTvDevicePicker(context, service: service),
                      icon: const Icon(Icons.expand_more, color: Colors.white),
                    ),
                  ],
                ),
                if (service.media != null)
                  Text(
                    status.title.isNotEmpty
                        ? status.title
                        : service.media!.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70),
                  ),
                if (status.state == 'loading' && connected)
                  const Padding(
                    padding: EdgeInsets.all(4),
                    child: Text(
                      '电视正在加载…',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                if (status.error != null)
                  const Text(
                    '电视无法播放此视频，请选择其他源或重试',
                    style: TextStyle(color: Colors.orange),
                  ),
                if (service.error != null)
                  Text(
                    service.error!.message,
                    style: const TextStyle(color: Colors.orange),
                    textAlign: TextAlign.center,
                  ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      tooltip: status.state == 'playing' ? '暂停电视播放' : '播放电视视频',
                      onPressed: connected && owned
                          ? () {
                              if (status.state == 'idle' &&
                                  service.media != null) {
                                service.startMedia(service.media!);
                              } else {
                                service.send(
                                  status.state == 'playing' ? 'pause' : 'play',
                                );
                              }
                            }
                          : null,
                      icon: Icon(
                        status.state == 'playing'
                            ? Icons.pause
                            : Icons.play_arrow,
                        color: Colors.white,
                      ),
                    ),
                    IconButton(
                      tooltip: '停止电视播放',
                      onPressed: connected && owned
                          ? () => service.send('stop')
                          : null,
                      icon: const Icon(Icons.stop, color: Colors.white),
                    ),
                    TextButton(
                      onPressed: onPlayHere,
                      child: const Text('在手机播放'),
                    ),
                  ],
                ),
                if (connected &&
                    owned &&
                    status.capabilities.contains('seek') &&
                    status.durationMs > 0)
                  Slider(
                    value: status.positionMs
                        .clamp(0, status.durationMs)
                        .toDouble(),
                    min: 0,
                    max: status.durationMs.toDouble(),
                    onChanged: (_) {},
                    onChangeEnd: (value) =>
                        service.send('seek', positionMs: value.round()),
                  ),
                if (connected && !owned)
                  TextButton(
                    onPressed: () async {
                      final allow = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: const Text('接管电视播放？'),
                          content: const Text('另一台手机正在控制电视。继续将播放你选择的视频。'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(c, false),
                              child: const Text('取消'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(c, true),
                              child: const Text('接管'),
                            ),
                          ],
                        ),
                      );
                      if (allow == true && service.media != null) {
                        await service.startMedia(
                          service.media!,
                          takeOver: true,
                        );
                      }
                    },
                    child: const Text('接管控制'),
                  ),
                if (!connected || status.state == 'failed')
                  TextButton(
                    onPressed: () async {
                      await service.retry();
                      if (service.state == TvConnectionState.connected &&
                          service.media != null) {
                        await service.startMedia(service.media!);
                      }
                    },
                    child: const Text('重试'),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
