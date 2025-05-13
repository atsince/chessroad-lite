import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

class FloatingOverlay extends StatefulWidget {
  const FloatingOverlay({Key? key}) : super(key: key);

  @override
  State<FloatingOverlay> createState() => _FloatingOverlayState();
}

class _FloatingOverlayState extends State<FloatingOverlay> {
  Color _overlayColor = Colors.brown.withOpacity(0.9);
  IconData _overlayIcon = Icons.wine_bar;
  int _tapCount = 0;

  void _handleTap() {
    setState(() {
      _tapCount++;
      if (_tapCount % 3 == 0) {
        _overlayColor = Colors.brown.withOpacity(0.9);
        _overlayIcon = Icons.wine_bar;
      } else if (_tapCount % 3 == 1) {
        _overlayColor = Colors.red.withOpacity(0.9);
        _overlayIcon = Icons.style;
      } else {
        _overlayColor = Colors.black.withOpacity(0.9);
        _overlayIcon = Icons.casino;
      }
    });

    // Send data to main app
    FlutterOverlayWindow.shareData({'count': _tapCount});
  }

  void _closeOverlay() {
    FlutterOverlayWindow.closeOverlay();
  }

  @override
  void initState() {
    super.initState();

    // Listen for data from main app
    FlutterOverlayWindow.overlayListener.listen((event) {
      if (event is Map && event.containsKey('command')) {
        if (event['command'] == 'close') {
          _closeOverlay();
        } else if (event['command'] == 'change_color' && event.containsKey('color')) {
          setState(() {
            final colorValue = event['color'] as int;
            _overlayColor = Color(colorValue).withOpacity(0.9);
          });
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      onDoubleTap: _closeOverlay,
      child: Container(
        width: 200,
        height: 200,
        decoration: BoxDecoration(
          color: _overlayColor,
          borderRadius: BorderRadius.circular(100),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              spreadRadius: 1,
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _overlayIcon,
              color: Colors.white,
              size: 80,
            ),
            const SizedBox(height: 10),
            Text(
              '点击: $_tapCount',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}