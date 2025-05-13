import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

class OverlayService {
  static final OverlayService _instance = OverlayService._internal();

  factory OverlayService() => _instance;

  OverlayService._internal() {
    _initListener();
  }

  bool _isListening = false;
  int _tapCount = 0;

  void _initListener() {
    if (!_isListening) {
      FlutterOverlayWindow.overlayListener.listen((event) {
        if (event is Map && event.containsKey('count')) {
          _tapCount = event['count'];
          // You can trigger callbacks or update UI in the main app here
        }
      });
      _isListening = true;
    }
  }

  Future<bool> isPermissionGranted() async {
    return await FlutterOverlayWindow.isPermissionGranted();
  }

  Future<bool> requestPermission() async {
    final result = await FlutterOverlayWindow.requestPermission();
    return result ?? false;
  }

  Future<void> showOverlay() async {
    if (!await isPermissionGranted()) {
      final granted = await requestPermission();
      if (!granted) {
        return;
      }
    }

    await FlutterOverlayWindow.showOverlay(
      height: 200,
      width: 200,
      enableDrag: true,
      flag: OverlayFlag.defaultFlag,
      alignment: OverlayAlignment.centerRight,
      positionGravity: PositionGravity.auto,
      overlayTitle: "象棋棋路悬浮窗",
      overlayContent: "轻松访问象棋功能",
    );
  }

  Future<void> closeOverlay() async {
    await FlutterOverlayWindow.closeOverlay();
  }

  Future<void> shareData(dynamic data) async {
    await FlutterOverlayWindow.shareData(data);
  }

  Future<void> changeOverlayColor() async {
    final random = Random();
    final color = Color.fromRGBO(
      random.nextInt(255),
      random.nextInt(255),
      random.nextInt(255),
      1.0
    );

    await shareData({
      'command': 'change_color',
      'color': color.value,
    });
  }

  int get tapCount => _tapCount;

  Stream get overlayListener => FlutterOverlayWindow.overlayListener;
}