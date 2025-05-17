import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'simple_floating_widget.dart';

// 这是简易悬浮窗的专用入口点
@pragma("vm:entry-point")
void simpleOverlayMain() {
  // 确保初始化完成
  WidgetsFlutterBinding.ensureInitialized();

  // 设置为透明背景
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);

  // 可选：设置方向
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  debugPrint('简易悬浮窗入口点被调用: simpleOverlayMain');

  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: SimpleFloatingWidget(),
    ),
  );
}