import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'tv_connection_service.dart';
import 'tv_models.dart';

class TvFloatingButton extends StatefulWidget {
  const TvFloatingButton({
    super.key,
    required this.service,
    required this.onOpenMedia,
    required this.onChoose,
    this.initialBottom = 82,
  });
  final TvConnectionService service;
  final ValueChanged<TvMedia> onOpenMedia;
  final VoidCallback onChoose;
  final double initialBottom;
  @override
  State<TvFloatingButton> createState() => _TvFloatingButtonState();
}

class _TvFloatingButtonState extends State<TvFloatingButton> {
  static double? _savedRight, _savedBottom;
  double? _right, _bottom;
  bool _expanded = false;
  Timer? _timer;
  Offset? _dragOrigin;

  void _scheduleCollapse() {
    _timer?.cancel();
    if (_expanded) {
      _timer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _expanded = false);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final maxRight = math.max(8.0, constraints.maxWidth - 64);
      final maxBottom = math.max(8.0, constraints.maxHeight - 64);
      final right = (_right ?? _savedRight ?? 16).clamp(8.0, maxRight);
      final bottom = (_bottom ?? _savedBottom ?? widget.initialBottom).clamp(
        8.0,
        maxBottom,
      );
      final expandRight = right > constraints.maxWidth / 2;
      return Stack(
        children: [
          Positioned(
            left: expandRight ? constraints.maxWidth - right - 56 : null,
            right: expandRight ? null : right,
            bottom: bottom,
            child: ListenableBuilder(
              listenable: widget.service,
              builder: (context, _) {
                final media = widget.service.media;
                final active =
                    widget.service.remoteSelected &&
                    media != null &&
                    widget.service.status.sessionId.isNotEmpty;
                final title = widget.service.status.title.isNotEmpty
                    ? widget.service.status.title
                    : media?.title ?? '';
                return Tooltip(
                  message: '播放到电视',
                  child: GestureDetector(
                    onTap: () {
                      if (!_expanded) {
                        setState(() => _expanded = true);
                        _scheduleCollapse();
                      } else {
                        _timer?.cancel();
                        setState(() => _expanded = false);
                        if (active) {
                          widget.onOpenMedia(media);
                        } else {
                          widget.onChoose();
                        }
                      }
                    },
                    onLongPressStart: (_) {
                      _timer?.cancel();
                      _dragOrigin = Offset(right, bottom);
                    },
                    onLongPressMoveUpdate: (details) {
                      final origin = _dragOrigin;
                      if (origin == null) return;
                      setState(() {
                        _right = (origin.dx - details.offsetFromOrigin.dx)
                            .clamp(8.0, maxRight);
                        _bottom = (origin.dy - details.offsetFromOrigin.dy)
                            .clamp(8.0, maxBottom);
                        _savedRight = _right;
                        _savedBottom = _bottom;
                      });
                    },
                    onLongPressEnd: (_) {
                      _dragOrigin = null;
                      _scheduleCollapse();
                    },
                    onLongPressCancel: () {
                      _dragOrigin = null;
                      _scheduleCollapse();
                    },
                    child: Material(
                      elevation: 6,
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(28),
                      child: AnimatedSize(
                        duration: const Duration(milliseconds: 180),
                        child: SizedBox(
                          height: 56,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(width: 16),
                              Icon(
                                Icons.tv,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onPrimaryContainer,
                              ),
                              const SizedBox(width: 16),
                              if (_expanded) ...[
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: math.max(
                                      0,
                                      math.min(
                                        180,
                                        expandRight
                                            ? right - 16
                                            : constraints.maxWidth - right - 72,
                                      ),
                                    ),
                                  ),
                                  child: Text(
                                    active ? title : '播放到电视',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 16),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      );
    },
  );
}
