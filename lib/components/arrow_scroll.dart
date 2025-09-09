import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ArrowScroll extends StatefulWidget {
  const ArrowScroll({
    super.key,
    required this.child,
    required this.scrollController,
  });

  final Widget child;
  final ScrollController scrollController;

  @override
  State<ArrowScroll> createState() => _ArrowScrollState();
}

class _ArrowScrollState extends State<ArrowScroll> {
  Timer? _scrollTimer;
  final double _scrollSpeed = 20.0;

  @override
  void dispose() {
    _scrollTimer?.cancel();
    super.dispose();
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      if (_scrollTimer != null) {
        return;
      }

      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        _scrollTimer = Timer.periodic(const Duration(milliseconds: 10), (
          timer,
        ) {
          if (widget.scrollController.hasClients) {
            final double newOffset =
                widget.scrollController.offset + _scrollSpeed;
            widget.scrollController.jumpTo(newOffset);
          }
        });
      } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        _scrollTimer = Timer.periodic(const Duration(milliseconds: 10), (
          timer,
        ) {
          if (widget.scrollController.hasClients) {
            final double newOffset =
                widget.scrollController.offset - _scrollSpeed;
            widget.scrollController.jumpTo(newOffset);
          }
        });
      }
    } else if (event is KeyUpEvent) {
      _scrollTimer?.cancel();
      _scrollTimer = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (FocusNode node, KeyEvent event) {
        // Only intercept arrow up/down; let other keys (text input, shortcuts) bubble.
        final isArrow = event.logicalKey == LogicalKeyboardKey.arrowDown ||
            event.logicalKey == LogicalKeyboardKey.arrowUp;
        if (isArrow) {
          _handleKeyEvent(event);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: widget.child,
    );
  }
}
