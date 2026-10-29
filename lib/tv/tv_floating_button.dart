import 'package:flutter/material.dart';

import 'tv_connection_service.dart';
import 'tv_models.dart';

class TvFloatingButton extends StatelessWidget {
  const TvFloatingButton({
    super.key,
    required this.service,
    required this.onOpenMedia,
    required this.onChoose,
  });
  final TvConnectionService service;
  final ValueChanged<TvMedia> onOpenMedia;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: service,
    builder: (context, _) {
      final media = service.media;
      final active =
          service.remoteSelected &&
          media != null &&
          service.status.sessionId.isNotEmpty;
      final title = service.status.title.isNotEmpty
          ? service.status.title
          : media?.title ?? '';
      return FloatingActionButton.extended(
        heroTag: null,
        onPressed: active ? () => onOpenMedia(media) : onChoose,
        icon: const Icon(Icons.tv),
        label: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 180),
          child: Text(
            active ? title : '播放到电视',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    },
  );
}
