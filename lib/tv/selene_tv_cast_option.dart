import 'package:flutter/material.dart';

/// Keep Selene's native receiver distinct from generic DLNA renderers.
class SeleneTvCastOption extends StatelessWidget {
  const SeleneTvCastOption({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.primaryContainer,
    margin: EdgeInsets.zero,
    child: ListTile(
      leading: const Icon(Icons.tv),
      title: const Text('Selene TV'),
      subtitle: const Text('局域网直连 · 继承当前播放进度'),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    ),
  );
}
