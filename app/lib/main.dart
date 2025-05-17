import 'dart:io';
import 'dart:isolate';
import 'dart:ui';
import 'dart:convert';

import 'package:chessroad/config/local_data.dart';
import 'package:chessroad/engine/hybrid_engine.dart';
import 'package:chessroad/overlay/floating_overlay.dart';
import 'package:chessroad/overlay/simple_floating_widget.dart';
import 'package:chessroad/services/overlay_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:provider/provider.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
// import 'package:wakelock/wakelock.dart';

import 'game/board_state.dart';
import 'game/page_state.dart';
import 'routes/main_menu/main_menu.dart';
import 'services/audios.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  debugPrint('运行模式: $kReleaseMode');

  // 检查是否为悬浮窗模式
  final isOverlayActive = await FlutterOverlayWindow.isActive();

  if (isOverlayActive) {
    // 悬浮窗模式：显示简易悬浮窗组件
    runApp(
      const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: SimpleFloatingWidget(),
      ),
    );
    return;
  }

  // 主应用入口点
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  if (Platform.isAndroid) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);
  }

  if (Platform.isIOS) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.leanBack, overlays: []);
  }

  // 启动应用
  runApp(const ChessRoadApp());
}

// 简易悬浮窗入口点
@pragma("vm:entry-point")
void overlayMain2() {
  WidgetsFlutterBinding.ensureInitialized();

  debugPrint('简易悬浮窗入口点被触发');

  // 运行悬浮窗UI
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: SimpleFloatingWidget(),
    ),
  );
}

// Overlay entry point
@pragma("vm:entry-point")
void overlayMain() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 设置跨Isolate通信
  await _setupOverlayCommunication();

  print('启动悬浮窗应用');
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Material(
      color: Colors.transparent,
      child: FloatingOverlay(),
    ),
  ));
}

// 为悬浮窗设置通信机制
Future<void> _setupOverlayCommunication() async {
  // 先尝试查找主应用的SendPort
  final mainSendPort = IsolateNameServer.lookupPortByName(OverlayConstants.OVERLAY_TO_MAIN_PORT_NAME);

  if (mainSendPort != null) {
    print('悬浮窗找到主应用的SendPort');

    // 发送启动消息
    try {
      mainSendPort.send(jsonEncode({
        'type': 'overlay_starting',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'message': '悬浮窗正在启动'
      }));
    } catch (e) {
      print('发送启动消息失败: $e');
    }
  } else {
    print('悬浮窗未找到主应用的SendPort，将依赖FlutterOverlayWindow通信');

    // 尝试使用FlutterOverlayWindow发送启动消息
    try {
      await FlutterOverlayWindow.shareData(jsonEncode({
        'type': 'overlay_starting',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'message': '悬浮窗正在启动'
      }));
    } catch (e) {
      print('使用FlutterOverlayWindow发送启动消息失败: $e');
    }
  }
}

class ChessRoadApp extends StatefulWidget {
  //
  static final navKey = GlobalKey<NavigatorState>();
  static get context => navKey.currentContext;

  const ChessRoadApp({Key? key}) : super(key: key);

  @override
  ChessRoadAppState createState() => ChessRoadAppState();
}

class ChessRoadAppState extends State<ChessRoadApp>
    with WidgetsBindingObserver {
  //
  @override
  void initState() {
    //
    super.initState();

    WidgetsBinding.instance.addObserver(this);
    // Wakelock.enable();
  }

  @override
  Widget build(BuildContext context) {
    //
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<BoardState>(create: (_) => BoardState()),
        ChangeNotifierProvider<PageState>(create: (_) => PageState()),
      ],
      child: MaterialApp(
        navigatorKey: ChessRoadApp.navKey,
        theme: ThemeData(primarySwatch: Colors.brown),
        home: const Scaffold(body: MainMenu()),
        builder: EasyLoading.init(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    //
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.resumed:
        // Wakelock.enable();
        Audios.loopBgm();
        break;
      case AppLifecycleState.inactive:
        break;
      case AppLifecycleState.paused:
        Audios.stopBgm();
        HybridEngine().stop();
        // Wakelock.disable();
        break;
      case AppLifecycleState.detached:
        Audios.release();
        // Wakelock.disable();
        HybridEngine().shutdown();
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
