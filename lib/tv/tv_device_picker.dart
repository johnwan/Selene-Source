import 'package:flutter/material.dart';

import 'tv_connection_service.dart';
import 'tv_models.dart';

Future<void> showTvDevicePicker(
  BuildContext context, {
  TvConnectionService? service,
}) => showDialog<void>(
  context: context,
  builder: (_) =>
      TvDevicePicker(service: service ?? TvConnectionService.instance),
);

/// Presentation only: changing this picker does not change pairing or routing.
class TvDevicePicker extends StatelessWidget {
  const TvDevicePicker({super.key, required this.service});
  final TvConnectionService service;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: service,
    builder: (context, _) => AlertDialog(
      title: const Text('播放到电视'),
      content: SizedBox(
        width: 380,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.smartphone),
                  title: const Text('在此手机播放'),
                  selected: !service.remoteSelected,
                  onTap: () => service.selectLocal(),
                ),
                for (final tv in service.devices)
                  ListTile(
                    leading: const Icon(Icons.tv),
                    title: Text(tv.name),
                    selected: service.selected?.id == tv.id,
                    onTap: () => service.select(tv),
                    trailing: service.selected?.id == tv.id
                        ? IconButton(
                            tooltip: '忘记电视',
                            icon: const Icon(Icons.link_off),
                            onPressed: () => service.forget(tv.id),
                          )
                        : null,
                  ),
                if (service.devices.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('正在查找电视…\n请在同一网络的电视上打开 Selene-TV。'),
                  ),
                if (service.selected != null)
                  Text('已选择：${service.selected!.name}'),
                if (service.state == TvConnectionState.awaitingApproval)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('请在电视上选择“允许”。只需首次确认。'),
                  ),
                if (service.state == TvConnectionState.connecting)
                  const LinearProgressIndicator(),
                if (service.state == TvConnectionState.connected)
                  const Text('已连接，播放将在电视上开始'),
                if (service.error != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      service.error!.message,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                TextButton.icon(
                  onPressed: () => _manual(context),
                  icon: const Icon(Icons.edit),
                  label: const Text('输入电视地址'),
                ),
                if (service.selected != null &&
                    service.state == TvConnectionState.disconnected)
                  TextButton(
                    onPressed: service.retry,
                    child: const Text('重试连接'),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('完成'),
        ),
      ],
    ),
  );
  Future<void> _manual(BuildContext context) async {
    final controller = TextEditingController();
    final input = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('电视地址'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '192.168.1.10:端口',
            helperText: '端口可在电视“已信任的手机”中查看',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('连接'),
          ),
        ],
      ),
    );
    // Dialog exit animation may still read the controller in this frame.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    controller.dispose();
    if (input == null || input.trim().isEmpty || !context.mounted) return;
    final value = input.trim();
    final uri = Uri.tryParse(value.contains('://') ? value : 'https://$value');
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        !uri.hasPort ||
        uri.port < 1 ||
        uri.port > 65535 ||
        uri.userInfo.isNotEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请输入电视 IP 和端口')));
      return;
    }
    await service.select(
      TvDevice(id: '', name: 'Selene-TV', host: uri.host, port: uri.port),
    );
  }
}
