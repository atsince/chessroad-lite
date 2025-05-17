import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:isolate';
import 'dart:ui';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:media_projection_screenshot/media_projection_screenshot.dart';
import 'package:media_projection_screenshot/captured_image.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import '../services/board_recognition_service.dart';

// 定义通信常量
class OverlayConstants {
  // 接收端口名称
  static const String MAIN_TO_OVERLAY_PORT_NAME = 'main_to_overlay_port';
  static const String OVERLAY_TO_MAIN_PORT_NAME = 'overlay_to_main_port';

  // 命令类型
  static const String CMD_CLOSE = 'close';
  static const String CMD_START_CAPTURE = 'start_capture';
  static const String CMD_STOP_CAPTURE = 'stop_capture';
  static const String CMD_UPDATE_BOARD = 'update_board';
  static const String CMD_SHOW_ERROR = 'show_error';
  static const String CMD_REQUEST_HINT = 'request_hint';
  static const String CMD_TEST_CONNECTION = 'test_connection';

  // 数据类型
  static const String TYPE_ANALYSIS_RESULT = 'analysis_result';
  static const String TYPE_STATUS = 'status';
  static const String TYPE_ERROR = 'error';
  static const String TYPE_TOGGLE_CAPTURE = 'toggle_capture';
}

class OverlayService {
  static final OverlayService _instance = OverlayService._internal();

  factory OverlayService() => _instance;

  bool _isOverlayActive = false;
  bool _isCapturing = false;
  String _apiUrl = "http://49.233.44.201:39009/api/chess/detect";
  var screenShot2 = MediaProjectionScreenshot();
  StreamSubscription? _captureStreamSubscription;
  DateTime? _lastCaptureTime;

  final StreamController<Map<String, dynamic>> _dataController = StreamController<Map<String, dynamic>>.broadcast();

  ReceivePort? _mainReceivePort;
  SendPort? _overlaySendPort;

  // 获取数据流，用于监听从悬浮窗接收到的数据
  Stream<Map<String, dynamic>> get dataStream => _dataController.stream;

  OverlayService._internal() {
    _setupMainIsolateReceiver();
  }

  // 设置主应用的接收端口
  void _setupMainIsolateReceiver() {
    // 注销任何已存在的端口名称
    IsolateNameServer.removePortNameMapping(OverlayConstants.OVERLAY_TO_MAIN_PORT_NAME);

    // 创建新的接收端口
    _mainReceivePort = ReceivePort();

    // 注册接收端口
    final registered = IsolateNameServer.registerPortWithName(
      _mainReceivePort!.sendPort,
      OverlayConstants.OVERLAY_TO_MAIN_PORT_NAME
    );

    if (registered) {
      print('主应用接收端口注册成功');

      // 监听从悬浮窗接收的消息
      _mainReceivePort!.listen((message) {
        print('[Kevin 666 ${Isolate.current.debugName }] 主应用收到消息: $message');
        if (message is String) {
          try {
            final data = jsonDecode(message);
            if (data is Map) {
              _handleIncomingMessage(Map<String, dynamic>.from(data));
            }
          } catch (e) {
            print('解析悬浮窗消息失败: $e');
          }
        } else if (message is Map) {
          _handleIncomingMessage(Map<String, dynamic>.from(message));
        }
      });
    } else {
      print('主应用接收端口注册失败');
    }
  }

  // 处理接收到的消息
  void _handleIncomingMessage(Map<String, dynamic> data) {
    // 首先将消息发送到数据流中
    _dataController.add(data);

    // 然后处理需要本地执行的命令
    if (data.containsKey('command')) {
      _executeCommand(data['command'], data);
    } else if (data.containsKey('type')) {
      _handleMessageType(data['type'], data);
    }
  }

  // 执行收到的命令
  void _executeCommand(String command, Map<String, dynamic> data) {
    print('执行命令: $command');
    switch (command) {
      case OverlayConstants.CMD_START_CAPTURE:
        startCapturing();
        break;

      case OverlayConstants.CMD_STOP_CAPTURE:
        stopCapturing();
        break;

      case OverlayConstants.CMD_CLOSE:
        closeOverlay();
        break;

      case OverlayConstants.CMD_REQUEST_HINT:
        // 通知UI请求引擎提示
        _dataController.add({
          'type': 'request_engine_hint',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
        break;

      default:
        print('未知命令: $command');
        break;
    }
  }

  // 处理收到的消息类型
  void _handleMessageType(String type, Map<String, dynamic> data) {
    print('处理消息类型: $type');
    switch(type) {
      case OverlayConstants.TYPE_TOGGLE_CAPTURE:
        // 切换捕获状态
        if (data.containsKey('isCapturing')) {
          // 使用消息中的明确状态
          bool requestedState = data['isCapturing'];
          if (requestedState && !_isCapturing) {
            startCapturing();
          } else if (!requestedState && _isCapturing) {
            stopCapturing();
          }
        } else {
          // 老方式：直接切换状态
          if (_isCapturing) {
            stopCapturing();
          } else {
            startCapturing();
          }
        }
        break;

      // 其他消息类型的处理...
    }
  }

  // 屏幕捕获相关方法
  Future<bool> requestScreenCapturePermission() async {
    try {
      // 请求截屏权限
      final permissionResult = await screenShot2.requestPermission();
      return permissionResult == 0; // 0表示成功
    } catch (e) {
      debugPrint('请求截屏权限失败: $e');
      return false;
    }
  }

  Future<void> startCapturing({int intervalSeconds = 5}) async {
    if (_isCapturing) return;

    final hasPermission = await requestScreenCapturePermission();
    if (!hasPermission) {
      await showError('无法获取截屏权限');
      return;
    }

    _isCapturing = true;
    _lastCaptureTime = null; // 重置上次捕获时间

    // 发送捕获开始状态消息
    _dataController.add({
      'type': 'capture_started',
      'timestamp': DateTime.now().millisecondsSinceEpoch
    });

    await sendCommand(OverlayConstants.CMD_SHOW_ERROR, {
      'message': '开始识别中...',
    });

    try {
      // 使用流式截屏持续捕获
      final stream = await screenShot2.startCapture(fps:1);
      if (stream != null) {
        _captureStreamSubscription = stream.listen(
          (data) async {
            if (data != null && _isCapturing) {
              final now = DateTime.now();
              // 检查是否已过间隔时间
              if (_lastCaptureTime == null || now.difference(_lastCaptureTime!).inSeconds >= intervalSeconds) {
                _lastCaptureTime = now; // 更新上次捕获时间

                try {
                  final capturedImage = CapturedImage.fromMap(Map<String, dynamic>.from(data));
                  if (capturedImage.bytes != null) {
                    debugPrint('处理截屏数据 - ${now.toIso8601String()}');
                    // 保存截屏到临时文件
                    final tempFile = await _saveScreenshotToTemp(capturedImage.bytes);
                    // 上传截屏到棋盘识别服务
                    await _recognizeBoard(tempFile);
                  }
                } catch (e) {
                  debugPrint('处理截屏数据失败: $e');
                }
              } else {
                // 跳过这一帧，因为还没到处理间隔
                debugPrint('跳过帧 - 距离上次处理: ${now.difference(_lastCaptureTime!).inSeconds}秒');
              }
            }
          },
          onError: (e) {
            debugPrint('截屏流出错: $e');
            showError('截屏出错: $e');
          },
          onDone: () {
            debugPrint('截屏流结束');
            if (_isCapturing) {
              // 如果仍然处于捕获状态，但流结束了，尝试重新启动
              startCapturing(intervalSeconds: intervalSeconds);
            }
          },
        );
      } else {
        await showError('无法启动截屏流');
        _isCapturing = false;
      }
    } catch (e) {
      await showError('启动截屏出错: $e');
      _isCapturing = false;
    }
  }

  Future<void> stopCapturing() async {
    _captureStreamSubscription?.cancel();
    _captureStreamSubscription = null;
    _isCapturing = false;
    _lastCaptureTime = null;

    // 停止屏幕捕获
    try {
      await screenShot2.stopCapture();
    } catch (e) {
      debugPrint('停止屏幕捕获时出错: $e');
    }

    // 发送捕获停止状态消息
    _dataController.add({
      'type': 'capture_stopped',
      'timestamp': DateTime.now().millisecondsSinceEpoch
    });

    await sendCommand(OverlayConstants.CMD_SHOW_ERROR, {
      'message': '识别已暂停',
    });
  }

  Uint8List _createMockScreenshot() {
    // 创建一个模拟的屏幕截图
    final fakeData = List<int>.filled(1024 * 768 * 4, 255); // 白色图像
    return Uint8List.fromList(fakeData);
  }

  Future<File> _saveScreenshotToTemp(Uint8List bytes) async {
    final tempDir = await getDownloadsDirectory();
    final file = File('${tempDir?.path}/screenshot_${DateTime.now().millisecondsSinceEpoch}.jpg');
    print("Kevin 666 ${file.absolute}");

    // 压缩图片尺寸到最大1500像素
    final image = img.decodeImage(bytes);
    if (image != null) {
      final int maxDimension = 1500;
      if (image.width > maxDimension || image.height > maxDimension) {
        double ratio = maxDimension / max(image.width, image.height);
        int newWidth = (image.width * ratio).round();
        int newHeight = (image.height * ratio).round();
        final resized = img.copyResize(image, width: newWidth, height: newHeight);
        bytes = Uint8List.fromList(img.encodeJpg(resized));
      }
    }

    await file.writeAsBytes(bytes);
    return file;
  }

  Future<void> _recognizeBoard(File imageFile) async {
    try {
      await sendStatusUpdate('正在识别棋盘...');

      final initBoard = '4k4/4a4/2P1ba3/2p4r1/3P2R2/9/9/4B4/4A4/2BAK4 w - - 0 1';
       await updateBoard(initBoard, 'black');
      // // 上传识别棋盘
      // final result = await BoardRecognitionService.recognizeBoard(
      //   imageFile,
      //   _apiUrl,
      // );

      // if (result.success && result.fen != null && result.fen!.isNotEmpty) {
      //   // 成功识别棋盘
      //   await sendStatusUpdate('棋盘识别成功，正在分析...');

      //   // 更新当前FEN和走棋方
      //   final parts = result.fen!.split(' ');
      //   final String sideToMove = parts.length > 1 ? parts[1] : 'w';
      //   final currentPlayer = sideToMove == 'w' ? 'red' : 'black';
      //   print('FEN parts: $parts');
      //   print('Side to move: $sideToMove');
      //   print('Current player: $currentPlayer');

      //   // // 更新棋盘状态
      //   await updateBoard(result.fen!, currentPlayer);

      //   // // 通知主应用请求引擎分析
      //   // await requestEngineHint();
      // } else {
      //   await showError(result.message ?? '棋盘识别失败');
      // }
    } catch (e) {
      await showError('棋盘识别过程出错: $e');
    }
  }

  // 发送状态更新到主应用或悬浮窗
  Future<void> sendStatusUpdate(String status, [bool isError = false]) async {
    final data = {
      'type': isError ? OverlayConstants.TYPE_ERROR : OverlayConstants.TYPE_STATUS,
      'message': status,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    await shareData(data);
  }

  Future<bool> isPermissionGranted() async {
    return await FlutterOverlayWindow.isPermissionGranted();
  }

  Future<bool> requestPermission() async {
    final result = await FlutterOverlayWindow.requestPermission();
    return result ?? false;
  }

  Future<bool> showOverlay() async {
    if (!await isPermissionGranted()) {
      final granted = await requestPermission();
      if (!granted) {
        return false;
      }
    }

    try {
      await FlutterOverlayWindow.showOverlay(
        height: 1000,
        width: 500,
        alignment: OverlayAlignment.centerRight,
        flag: OverlayFlag.defaultFlag,
        visibility: NotificationVisibility.visibilityPrivate,
        enableDrag: true,
        positionGravity: PositionGravity.auto,
        overlayTitle: "象棋棋路悬浮窗",
        overlayContent: "迷你棋谱实时识别",
      );

      _isOverlayActive = true;
      return true;
    } catch (e) {
      debugPrint('显示悬浮窗失败: $e');
      return false;
    }
  }

  Future<void> closeOverlay() async {
    await FlutterOverlayWindow.closeOverlay();
    _isOverlayActive = false;
  }

  // 发送命令到悬浮窗
  Future<void> sendCommand(String command, [Map<String, dynamic>? data]) async {
    final Map<String, dynamic> message = {
      'command': command,
    };

    if (data != null) {
      message.addAll(data);
    }

    await _sendMessageToOverlay(message);
  }

  // 发送棋盘数据到悬浮窗
  Future<void> updateBoard(String fen, String player) async {
    await sendCommand(OverlayConstants.CMD_UPDATE_BOARD, {
      'fen': fen,
      'player': player,
    });
  }

  // 发送错误消息到悬浮窗
  Future<void> showError(String errorMessage) async {
    await sendCommand(OverlayConstants.CMD_SHOW_ERROR, {
      'message': errorMessage,
    });
  }

  // 请求引擎提示
  Future<void> requestEngineHint() async {
    await sendCommand(OverlayConstants.CMD_REQUEST_HINT);
  }

  // 开始捕获
  Future<void> startCapture() async {
    await sendCommand(OverlayConstants.CMD_START_CAPTURE);
  }

  // 停止捕获
  Future<void> stopCapture() async {
    await sendCommand(OverlayConstants.CMD_STOP_CAPTURE);
  }

  // 使用IsolateNameServer发送消息到悬浮窗
  Future<void> _sendMessageToOverlay(dynamic data) async {
    final jsonData = data is Map ? jsonEncode(data) : data.toString();

    // 通过IsolateNameServer获取悬浮窗的SendPort
    final sendPort = IsolateNameServer.lookupPortByName(OverlayConstants.MAIN_TO_OVERLAY_PORT_NAME);

    if (sendPort != null) {
      sendPort.send(jsonData);
      print('发送消息到悬浮窗: $jsonData');
    } else {
      // 回退方案：使用FlutterOverlayWindow.shareData
      await FlutterOverlayWindow.shareData(jsonData);
      print('使用shareData发送消息到悬浮窗: $jsonData');
    }
  }

  // 老方法保留用于向后兼容
  Future<void> shareData(dynamic data) async {
    if (data is Map) {
      await _sendMessageToOverlay(data);
    } else {
      await _sendMessageToOverlay(data);
    }
  }

  Stream get overlayListener => FlutterOverlayWindow.overlayListener;

  void dispose() {
    stopCapturing();
    closeOverlay();
    _mainReceivePort?.close();
    IsolateNameServer.removePortNameMapping(OverlayConstants.OVERLAY_TO_MAIN_PORT_NAME);
    _dataController.close();
  }
}