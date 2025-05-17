import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:matrix_gesture_detector/matrix_gesture_detector.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:isolate';
import 'dart:ui';
import 'package:flutter/services.dart';
import '../game/game.dart';
import '../game/board_state.dart';
import '../ui/build_utils.dart';
import '../ui/ruler.dart';
import '../cchess/cc_fen.dart';
import '../cchess/move_name.dart';
import '../engine/engine.dart';
import '../cchess/cc_base.dart';
import '../config/local_data.dart';
import '../engine/hybrid_engine.dart'; // 添加引擎导入
import '../services/overlay_service.dart'; // 导入常量定义

class FloatingOverlay extends StatefulWidget {
  const FloatingOverlay({Key? key}) : super(key: key);

  @override
  State<FloatingOverlay> createState() => _FloatingOverlayState();
}

class _FloatingOverlayState extends State<FloatingOverlay> {
  String _currentPlayer = 'red'; // 'red' or 'black'
  bool _isCapturing = false;
  // String _boardFen = 'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w - - 0 1';
  String _boardFen = '4k4/4a4/2P1ba3/2p4r1/3P2R2/9/9/4B4/4A4/2BAK4 w - - 0 1';
  // String _boardFen = '9/9/9/6p1p/9/9/9/9/9/9 w - - 0 1';
  double _currentScale = 1.0;
  final double _minScale = 0.5;
  final double _maxScale = 2.0;
  final Matrix4 _matrix = Matrix4.identity();
  final ValueNotifier<Matrix4> _notifier = ValueNotifier(Matrix4.identity());

  // 添加通信相关变量
  ReceivePort? _overlayReceivePort;
  SendPort? _mainSendPort;

  // 添加BoardState以支持棋盘绘制
  late BoardState _boardState;

  // 基础尺寸，缩放基于此尺寸
  final double _baseWidth = 500.0;
  final double _baseHeight = 800.0;

  double get _currentWidth => _baseWidth * _currentScale;
  double get _currentHeight => _baseHeight * _currentScale;

  // 状态信息
  String _statusMessage = '等待开始识别';
  DateTime? _lastCaptureTime;
  String? _engineHint;
  bool _isEngineThinking = false;
  bool _showEngineArrows = true;  // 添加一个属性控制是否显示引擎箭头

  // 存储引擎分析的走法数组
  List<Move> _engineMoves = [];

  // 添加防抖相关变量
  DateTime _lastUpdateTime = DateTime.now();
  Timer? _stabilizeTimer;
  bool _isDragging = false;

  // 位置追踪相关
  Timer? _positionReportTimer;

  // 引用OverlayService
  // final OverlayService _overlayService = OverlayService();

  @override
  void initState() {
    super.initState();
    LocalData().load();
    // 初始化BoardState
    _boardState = BoardState();
    _boardState.load(_boardFen, notify: true);

    // 初始化引擎 - 使用Future.delayed确保UI初始化完成后再启动引擎
    Future.delayed(Duration(milliseconds: 300), () async {
      try {
        await HybridEngine().startup();
        await HybridEngine().newGame();
      } catch (e) {
        print('引擎初始化失败: $e');
      }
    });

    // 设置跨Isolate通信
    _setupOverlayIsolateReceiver();

    // 监听FlutterOverlayWindow消息（作为备用通道）
    _setupFlutterOverlayListener();

    // 发送初始化完成的消息到主应用
    Future.delayed(const Duration(milliseconds: 500), () {
      _sendMessageToMain({
        'type': 'overlay_initialized',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'message': '悬浮窗初始化完成'
      });
    });

    // 开始定期报告位置
    _startPositionReporting();
  }

  // 设置悬浮窗接收端口
  void _setupOverlayIsolateReceiver() {
    // 注销之前的端口（如果有）
    IsolateNameServer.removePortNameMapping(OverlayConstants.MAIN_TO_OVERLAY_PORT_NAME);

    // 创建新的接收端口
    _overlayReceivePort = ReceivePort();

    // 注册接收端口
    final registered = IsolateNameServer.registerPortWithName(
      _overlayReceivePort!.sendPort,
      OverlayConstants.MAIN_TO_OVERLAY_PORT_NAME
    );

    if (registered) {
      print('悬浮窗接收端口注册成功');

      // 监听接收的消息
      _overlayReceivePort!.listen((message) {
        print('悬浮窗收到消息: $message');

        if (message is String) {
          try {
            final data = jsonDecode(message);
            if (data is Map) {
              _handleOverlayEvent(Map<String, dynamic>.from(data));
            }
          } catch (e) {
            print('解析主应用消息失败: $e');
          }
        } else if (message is Map) {
          _handleOverlayEvent(Map<String, dynamic>.from(message));
        }
      });
    } else {
      print('悬浮窗接收端口注册失败');
    }

    // 查找主应用的SendPort
    _findMainSendPort();
  }

  // 查找主应用的SendPort
  void _findMainSendPort() {
    _mainSendPort = IsolateNameServer.lookupPortByName(OverlayConstants.OVERLAY_TO_MAIN_PORT_NAME);

    if (_mainSendPort != null) {
      print('找到主应用的SendPort');
    } else {
      print('未找到主应用的SendPort，将使用FlutterOverlayWindow.shareData作为备用');

      // 5秒后重试一次
      Future.delayed(const Duration(seconds: 5), () {
        _mainSendPort = IsolateNameServer.lookupPortByName(OverlayConstants.OVERLAY_TO_MAIN_PORT_NAME);
        if (_mainSendPort != null) {
          print('重试后找到主应用的SendPort');
        }
      });
    }
  }

  // 设置FlutterOverlayWindow监听器（作为备用通道）
  void _setupFlutterOverlayListener() {
    FlutterOverlayWindow.overlayListener.listen((event) {
      print("收到FlutterOverlayWindow消息: $event");

      if (event == null) return;

      try {
        // 处理字符串类型的JSON数据
        if (event is String) {
          try {
            final data = jsonDecode(event);
            _handleOverlayEvent(data);
          } catch (e) {
            print("解析JSON数据失败: $e");
            // 可能是普通字符串消息
            _handleOverlayEvent({"message": event});
          }
        }
        // 处理Map类型数据
        else if (event is Map) {
          _handleOverlayEvent(Map<String, dynamic>.from(event));
        }
      } catch (e) {
        print("处理FlutterOverlayWindow消息出错: $e");
      }
    });
  }

  // 处理来自主应用的事件
  void _handleOverlayEvent(Map<String, dynamic> event) {
    if (event.containsKey('command')) {
      final command = event['command'];

      switch (command) {
        case OverlayConstants.CMD_CLOSE:
          _closeOverlay();
          break;

        case OverlayConstants.CMD_START_CAPTURE:
          _startCapturing();
          break;

        case OverlayConstants.CMD_STOP_CAPTURE:
          _stopCapturing();
          break;

        case OverlayConstants.CMD_UPDATE_BOARD:
          if (event.containsKey('fen') && event.containsKey('player')) {
            setState(() {
              _boardFen = event['fen'];
              _currentPlayer = event['player'];
              _lastCaptureTime = DateTime.now();

              // 更新BoardState
              _boardState.load(_boardFen, notify: true);

              // 如果有引擎思考状态，更新
              if (event.containsKey('isEngineThinking')) {
                _isEngineThinking = event['isEngineThinking'];
              }

              // 如果有引擎提示，也更新
              if (event.containsKey('engineHint')) {
                _engineHint = event['engineHint'];
                _isEngineThinking = false;
              }

              // 更新引擎走法箭头
              if (event.containsKey('enginePV')) {
                _updateEnginePV(event['enginePV']);
              } else {
                // 自动请求引擎提示
                print("Kevin 666 CMD_UPDATE_BOARD request hint");
                _requestEngineHint();
              }

              _statusMessage = '最近识别: ${_formatTime(_lastCaptureTime!)}';
            });
          }
          break;

        case OverlayConstants.CMD_SHOW_ERROR:
          if (event.containsKey('message')) {
            setState(() {
              _statusMessage = '错误: ${event['message']}';
            });
          }
          break;

        case OverlayConstants.CMD_REQUEST_HINT:
          _requestEngineHint();
          break;

        case OverlayConstants.CMD_TEST_CONNECTION:
          // 接收到测试连接的消息，回复确认
          _sendMessageToMain({
            'type': 'connection_confirmed',
            'timestamp': DateTime.now().millisecondsSinceEpoch,
            'message': '悬浮窗确认连接'
          });
          break;

        default:
          print("未知命令: $command");
          break;
      }
    }
  }

  // 发送数据回主应用
  Future<void> _sendMessageToMain(Map<String, dynamic> data) async {
    try {
      final jsonData = jsonEncode(data);

      // 首先尝试使用IsolateNameServer发送
      if (_mainSendPort != null) {
        _mainSendPort!.send(jsonData);
        print('使用IsolateNameServer发送消息到主应用: $jsonData');
        return;
      }

      // 如果IsolateNameServer不可用，尝试重新获取SendPort
      _mainSendPort = IsolateNameServer.lookupPortByName(OverlayConstants.OVERLAY_TO_MAIN_PORT_NAME);
      if (_mainSendPort != null) {
        _mainSendPort!.send(jsonData);
        print('使用刷新后的IsolateNameServer发送消息到主应用: $jsonData');
        return;
      }

      // 最后回退到FlutterOverlayWindow.shareData
      await FlutterOverlayWindow.shareData(jsonData);
      print('使用FlutterOverlayWindow.shareData发送消息到主应用: $jsonData');
    } catch (e) {
      print("发送消息到主应用失败: $e");

      // 最终尝试使用FlutterOverlayWindow.shareData
      try {
        await FlutterOverlayWindow.shareData(jsonEncode({
          'type': 'error',
          'message': '发送消息失败: $e',
          'timestamp': DateTime.now().millisecondsSinceEpoch
        }));
      } catch (_) {
        // 忽略
      }
    }
  }

  // 发送截图分析结果到主应用
  Future<void> _sendAnalysisResult(String fen, String currentPlayer, [String? engineHint]) async {
    final data = {
      'type': OverlayConstants.TYPE_ANALYSIS_RESULT,
      'fen': fen,
      'player': currentPlayer,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    if (engineHint != null) {
      data['engineHint'] = engineHint;
    }

    await _sendMessageToMain(data);
  }

  // 发送状态更新到主应用
  Future<void> _sendStatusUpdate(String status, [bool isError = false]) async {
    final data = {
      'type': isError ? OverlayConstants.TYPE_ERROR : OverlayConstants.TYPE_STATUS,
      'message': status,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    await _sendMessageToMain(data);
  }

  // 修改开始捕获方法，使用消息机制
  Future<void> _startCapturing() async {
    if (_isCapturing) return;

    setState(() {
      _statusMessage = '开始识别中...';
    });

    // 发送命令而不是直接调用方法
    await _sendMessageToMain({
      'command': OverlayConstants.CMD_START_CAPTURE,
      'timestamp': DateTime.now().millisecondsSinceEpoch
    });

    setState(() {
      _isCapturing = true;
    });
  }

  // 修改停止捕获方法，使用消息机制
  Future<void> _stopCapturing() async {
    if (!_isCapturing) return;

    // 发送命令而不是直接调用方法
    await _sendMessageToMain({
      'command': OverlayConstants.CMD_STOP_CAPTURE,
      'timestamp': DateTime.now().millisecondsSinceEpoch
    });

    setState(() {
      _isCapturing = false;
      _statusMessage = '识别已暂停';
    });
  }

  // 更新引擎走法箭头
  void _updateEnginePV(List pvMoves) {
    try {
      if (pvMoves.isEmpty) return;

      // 创建引擎信息对象
      final allMoves = pvMoves.cast<String>().join(' ');
      final engineInfo = EngineInfo.parse('info depth 20 seldepth 30 multipv 1 score cp 50 nodes 10000 nps 5000 hashfull 0 tbhits 0 time 2000 pv $allMoves');

      // 设置最佳着法
      if (pvMoves.isNotEmpty) {
        final bestmove = Bestmove(pvMoves[0]);
        if (pvMoves.length > 1) {
          bestmove.ponder = pvMoves[1];
        }
        _boardState.bestmove = bestmove;
      }

      // 设置引擎信息
      _boardState.engineInfo = engineInfo;

      // 生成中文着法描述
      final position = Fen.positionFromFen(_boardFen);
      if (position != null && pvMoves.isNotEmpty) {
        final move = Move.fromEngineMove(pvMoves[0]);
        final moveName = "${MoveName.translate(position, move)} (${pvMoves[0]})";
        _engineHint = moveName;
      }
    } catch (e) {
      print('更新引擎PV出错: $e');
    }
  }

  // 请求引擎提示的方法
  Future<void> _requestEngineHint() async {
    if (_boardFen.isEmpty) {
      return;
    }

    // 只更新分析状态，不清除已有的棋盘箭头
    setState(() {
      _isEngineThinking = true;
      // 保留 _engineHint 和 _engineMoves，这样在分析过程中棋盘上的箭头不会消失
      // _engineHint = null;
      // _engineMoves = [];
    });

    print('请求引擎提示，走棋方: ${_currentPlayer == 'red' ? '红方' : '黑方'}');

    try {
      // 先停止任何正在进行的引擎分析
      await _stopPonder();
      await Future.delayed(const Duration(milliseconds: 500));

      // 重置引擎状态，避免状态混乱导致崩溃
      await HybridEngine().stop();
      await Future.delayed(const Duration(milliseconds: 500));
      await HybridEngine().newGame();
      await Future.delayed(const Duration(milliseconds: 300));

      final position = Fen.positionFromFen(_boardFen);
      if (position == null) {
        print('无法从FEN创建棋局位置');
        setState(() {
          _isEngineThinking = false;
        });
        return;
      }

      print("Kevin 666 HybridEngine().go");
      await HybridEngine().go(position, _engineCallback);
    } catch (e) {
      print('请求引擎提示时出错: $e');
      setState(() {
        _isEngineThinking = false;
      });
    }
  }

  // 设置走棋提示显示方法（从BoardRecognitionPage中移植而来）
  void _setupEngineMovesToDisplay(BoardState boardState, List<Move> moves) {
    if (moves.isEmpty) return;

    try {
      // 创建一个临时位置，检查走法是否有效
      final position = Fen.positionFromFen(_boardFen);
      if (position == null) return;

      // 创建一个新的EngineInfo以显示思考线路
      final allMoves = moves.map((m) => m.asEngineMove()).toList();
      final stringPV = allMoves.join(' ');
      print('创建引擎信息 PV: $stringPV');

      // 创建引擎信息对象
      final engineInfo = EngineInfo.parse('info depth 20 seldepth 30 multipv 1 score cp 50 nodes 10000 nps 5000 hashfull 0 tbhits 0 time 2000 pv $stringPV');

      // 设置引擎信息，确保pvs包含所有走法
      boardState.engineInfo = engineInfo;

      // 设置bestmove，但将其设为空，强制使用pvs中的走法
      if (moves.length >= 1) {
        print('设置最佳走法: ${moves[0].asEngineMove()}');

        // 清除任何现有的bestmove，确保使用engineInfo中的走法
        boardState.bestmove = null;
      }

      // 确保更新UI
      boardState.notifyListeners();
    } catch (e) {
      print('设置走棋提示显示出错: $e');
    }
  }

  // 引擎回调函数
  void _engineCallback(EngineResponse er) {
    final resp = er.response;

    if (resp is EngineInfo) {
      // 保存最新的引擎分析信息，但不立即更新界面上的箭头
      _boardState.engineInfo = resp;

      final score = resp.tokens['score'];
      final depth = resp.tokens['depth'];
      final cpOrMate = resp.tokens['cp_or_mate'];

      if (score != null && depth != null) {
        final judgement = cpOrMate == 1
          ? (score > 0 ? "$score 步成杀" : "${-score} 步被杀")
          : (score == 0 ? "均势" : (score > 0 ? "优势" : "劣势"));

        // 检查是否找到必胜着法等情况
        if (cpOrMate == 1 && depth >= 60) {
          HybridEngine().stop();
        }
      }

      // 分析中不更新棋盘显示，等待最终结果
    } else if (resp is Bestmove) {
      print('引擎最佳着法: ${resp.bestmove}');

      // 保存引擎提供的最佳着法
      _boardState.bestmove = resp;

      if (resp.bestmove != null) {
        try {
          final move = Move.fromEngineMove(resp.bestmove);

          // 创建当前和后续走法的列表
          List<Move> newMoves = [move];
          if (resp.ponder != null) {
            try {
              newMoves.add(Move.fromEngineMove(resp.ponder!));
              print('添加后续走法: ${resp.ponder}');
            } catch (e) {
              print('解析后续走法时出错: $e');
            }
          }

          setState(() {
            _engineMoves = newMoves;
            _isEngineThinking = false;
          });

          // 现在分析完成，更新棋盘显示
          if (mounted) {
            _setupEngineMovesToDisplay(_boardState, newMoves);
          }

          // 尝试生成中文着法描述
          final position = Fen.positionFromFen(_boardFen);
          if (position != null) {
            final moveName = "${MoveName.translate(position, move)} (${resp.bestmove})";

            setState(() {
              _engineHint = moveName;
            });
            print('引擎建议: $moveName');

            // 发送引擎提示回主应用
            _sendAnalysisResult(_boardFen, _currentPlayer, moveName);
          } else {
            setState(() {
              _engineHint = resp.bestmove;
            });

            // 发送引擎提示回主应用
            _sendAnalysisResult(_boardFen, _currentPlayer, resp.bestmove);
          }
        } catch (e) {
          print('解析引擎着法时出错: $e');
          setState(() {
            _engineHint = resp.bestmove;
            _isEngineThinking = false;
          });

          // 发送引擎提示回主应用
          _sendAnalysisResult(_boardFen, _currentPlayer, resp.bestmove);
        }
      } else {
        setState(() {
          _isEngineThinking = false;
        });
      }
    } else if (resp is NoBestmove) {
      // 处理无最佳着法的情况，但保留现有的箭头
      setState(() {
        _isEngineThinking = false;
        _engineHint = "无法找到有效走法";
      });

      // 发送状态消息
      _sendStatusUpdate("无法找到有效走法");
    } else if (resp is Error) {
      print('引擎返回错误: ${resp.message}');
      setState(() {
        _isEngineThinking = false;
        _engineHint = "引擎错误: ${resp.message}";
      });

      // 发送错误消息
      _sendStatusUpdate('引擎返回错误: ${resp.message}', true);
    }
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  }

  void _togglePlayer() {
    setState(() {
      _currentPlayer = _currentPlayer == 'red' ? 'black' : 'red';

      // 更新FEN中的走棋方
      if (_boardFen.isNotEmpty) {
        final parts = _boardFen.split(' ');
        if (parts.length >= 2) {
          parts[1] = _currentPlayer == 'red' ? 'w' : 'b';
          _boardFen = parts.join(' ');
        }

        // 更新BoardState
        _boardState.load(_boardFen, notify: true);

        // 清除引擎提示和箭头
        _engineHint = null;
        _engineMoves = [];
      }
    });

    // 重置引擎状态
    _stopPonder().then((_) async {
      await Future.delayed(const Duration(milliseconds: 500));
      await HybridEngine().stop();
      await Future.delayed(const Duration(milliseconds: 500));
      await HybridEngine().newGame();

      // 切换后自动请求新走法提示
      _requestEngineHint();
    });
  }

  void _toggleCapturing() async {
    // 发送切换捕获命令
    Map<String, dynamic> toggleData = {
      'type': OverlayConstants.TYPE_TOGGLE_CAPTURE,
      'isCapturing': !_isCapturing, // Invert the current state to send the new desired state
      'timestamp': DateTime.now().millisecondsSinceEpoch
    };

    // 提前更新UI状态，提供即时反馈
    setState(() {
      _isCapturing = !_isCapturing;
      _statusMessage = _isCapturing ? '正在识别...' : '识别已暂停';
    });

    await _sendMessageToMain(toggleData);
  }

  void _closeOverlay() {
    FlutterOverlayWindow.closeOverlay();
  }

  // 处理来自OverlayService的数据
  void _handleServiceData(Map<String, dynamic> data) {
    if (data.containsKey('type')) {
      final type = data['type'];

      switch (type) {
        case OverlayConstants.TYPE_ANALYSIS_RESULT:
          if (data.containsKey('fen') && data.containsKey('player')) {
            setState(() {
              _boardFen = data['fen'];
              _currentPlayer = data['player'];
              _lastCaptureTime = DateTime.now();

              // 更新BoardState
              _boardState.load(_boardFen, notify: true);

              _statusMessage = '最近识别: ${_formatTime(_lastCaptureTime!)}';
            });

            // 请求引擎提示
            _requestEngineHint();
          }
          break;

        case OverlayConstants.TYPE_STATUS:
          if (data.containsKey('message')) {
            setState(() {
              _statusMessage = data['message'];
            });
          }
          break;

        case OverlayConstants.TYPE_ERROR:
          if (data.containsKey('message')) {
            setState(() {
              _statusMessage = '错误: ${data['message']}';
            });
          }
          break;

        case OverlayConstants.TYPE_TOGGLE_CAPTURE:
          // 处理捕获状态切换结果
          setState(() {
            // 如果消息中包含明确的状态，使用它，否则切换当前状态
            if (data.containsKey('newStatus')) {
              _isCapturing = data['newStatus'];
            } else {
              _isCapturing = !_isCapturing;
            }

            _statusMessage = _isCapturing ? '正在识别...' : '识别已暂停';
          });
          break;

        case 'capture_started':
          setState(() {
            _isCapturing = true;
            _statusMessage = '开始识别...';
          });
          break;

        case 'capture_stopped':
          setState(() {
            _isCapturing = false;
            _statusMessage = '识别已暂停';
          });
          break;

        case 'request_engine_hint':
          // 收到请求引擎提示的消息
          _requestEngineHint();
          break;
      }
    }
  }

  // 添加防抖处理方法
  void _handleMatrixUpdate(Matrix4 m, Matrix4 tm, Matrix4 sm, Matrix4 rm) {
    // 处理缩放
    double scale = sm.getMaxScaleOnAxis();
    if (_currentScale * scale < _minScale) {
      scale = _minScale / _currentScale;
    } else if (_currentScale * scale > _maxScale) {
      scale = _maxScale / _currentScale;
    }

    // 判断是否触发更新
    bool isScaling = (scale - 1.0).abs() > 0.01;
    bool isTranslating = false;

    // 检查平移量是否足够大，避免微小变化触发更新
    if (tm != Matrix4.identity()) {
      double dx = tm.getTranslation().x;
      double dy = tm.getTranslation().y;
      isTranslating = dx.abs() > 1.0 || dy.abs() > 1.0;
    }

    bool shouldUpdate = isScaling || isTranslating;

    if (shouldUpdate) {
      // 标记正在拖动
      _isDragging = true;
      _lastUpdateTime = DateTime.now();

      // 取消之前的稳定定时器
      _stabilizeTimer?.cancel();

      setState(() {
        // 应用缩放
        if (isScaling) {
          _currentScale *= scale;
          _matrix.multiply(Matrix4.diagonal3Values(scale, scale, 1.0));
        }

        // 应用平移
        if (isTranslating) {
          _matrix.multiply(tm);
        }

        _notifier.value = _matrix.clone();
      });

      // 设置定时器，当用户停止操作一段时间后，标记为非拖动状态
      _stabilizeTimer = Timer(const Duration(milliseconds: 300), () {
        if (DateTime.now().difference(_lastUpdateTime).inMilliseconds >= 300) {
          setState(() {
            _isDragging = false;
          });

          // 拖动结束后立即更新位置
          _reportOverlayPosition();
        }
      });
    }
  }

  // 停止后台思考并释放引擎资源
  Future<void> _stopPonder() async {
    try {
      await HybridEngine().stopPonder();
      _boardState.engineInfo = null;
      _boardState.bestmove = null;
    } catch (e) {
      print('停止后台思考出错: $e');
    }
  }

  // 停止引擎的思考并清理相关资源
  Future<void> _stopEngine() async {
    try {
      await _stopPonder();
      await Future.delayed(const Duration(milliseconds: 300));
      await HybridEngine().stop();
      setState(() {
        if (_isEngineThinking) {
          _isEngineThinking = false;
        }
      });
    } catch (e) {
      print('停止引擎思考出错: $e');
    }
  }

  // 开始定期报告悬浮窗位置
  void _startPositionReporting() {
    // 首次报告位置前等待1秒确保悬浮窗完全初始化
    Future.delayed(const Duration(seconds: 1), () {
      // 立即报告一次位置
      _reportOverlayPosition();

      // 每5秒报告一次位置
      _positionReportTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
        if (mounted) {
          _reportOverlayPosition();
        } else {
          timer.cancel();
        }
      });
    });
  }

  // 报告悬浮窗位置
  void _reportOverlayPosition() async {
    try {
      // 检查是否是悬浮窗模式
      final isActive = await FlutterOverlayWindow.isActive();
      if (!isActive) {
        print('当前不是悬浮窗模式，跳过位置报告');
        return;
      }
      // await FlutterOverlayWindow.moveOverlay(OverlayPosition(200, 200));
      // 使用FlutterOverlayWindow.getOverlayPosition()获取悬浮窗位置
      final position = await FlutterOverlayWindow.getOverlayPosition();

      if (position != null) {
        final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;

        // 确保所有值都不为null
        // 获取dp单位的坐标（以左上角为原点）
        final double dpX = position.x ?? 0.0;
        final double dpY = position.y ?? 0.0;


        // 将dp转换为物理像素值
        final double physicalX = dpX * devicePixelRatio;
        final double physicalY = dpY * devicePixelRatio;
        final double physicalWidth = _currentWidth;
        final double physicalHeight = _currentHeight;

        print('悬浮窗位置: dp=($dpX, $dpY), $devicePixelRatio  物理像素=($physicalX, $physicalY), 物理像素=${physicalWidth}x${physicalHeight}');

        // 发送位置信息到主应用
        _sendMessageToMain({
          'type': 'overlay_position',
          'x': physicalX,
          'y': physicalY,
          'width': physicalWidth,
          'height': physicalHeight,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
      } else {
        print('无法获取悬浮窗位置，返回为null');
      }
    } catch (e) {
      print('获取悬浮窗位置出错: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _boardState,
      child: Stack(
        children: [
          MatrixGestureDetector(
            clipChild: false,
            focalPointAlignment: Alignment.center,
            shouldRotate: false, // 禁用旋转
            shouldScale: false,   // 允许缩放
            shouldTranslate: true, // 允许平移
            onMatrixUpdate: _handleMatrixUpdate,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              width: _currentWidth,
              height: _currentHeight,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.9),
                borderRadius: BorderRadius.circular(16),
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
                children: [
                  // 顶部操作栏 - 减小高度
                  Container(
                    height: _currentScale * 40, // 从50减小到40
                    padding: EdgeInsets.symmetric(horizontal: 4 * _currentScale, vertical: 0), // 减小垂直padding
                    decoration: BoxDecoration(
                      color: Colors.grey[800],
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // 标题
                        Expanded(
                          child: Text(
                            '象棋识别悬浮窗',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16 * _currentScale, // 从18减小到16
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // 操作按钮
                        Row(
                          children: [
                            // 切换红黑方按钮
                            IconButton(
                              padding: EdgeInsets.zero,
                              constraints: BoxConstraints(),
                              iconSize: 22 * _currentScale, // 从24减小到22
                              icon: Icon(
                                Icons.swap_horiz,
                                color: _currentPlayer == 'red' ? Colors.red : Colors.white,
                              ),
                              onPressed: _togglePlayer,
                              tooltip: '切换走棋方',
                            ),
                            SizedBox(width: 4 * _currentScale),
                            // 开始/停止按钮
                            IconButton(
                              padding: EdgeInsets.zero,
                              constraints: BoxConstraints(),
                              iconSize: 22 * _currentScale, // 从24减小到22
                              icon: Icon(
                                _isCapturing ? Icons.stop : Icons.play_arrow,
                                color: _isCapturing ? Colors.red : Colors.green,
                              ),
                              onPressed: _toggleCapturing,
                              tooltip: _isCapturing ? '停止捕捉' : '开始捕捉',
                            ),
                            SizedBox(width: 4 * _currentScale),
                            // 关闭按钮
                            IconButton(
                              padding: EdgeInsets.zero,
                              constraints: BoxConstraints(),
                              iconSize: 22 * _currentScale, // 从24减小到22
                              icon: const Icon(
                                Icons.close,
                                color: Colors.white,
                              ),
                              onPressed: _closeOverlay,
                              tooltip: '关闭悬浮窗',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // 棋盘区域
                  Expanded(
                    child: Column(
                      children: [
                        // 引擎提示 - 简化设计以减小高度
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            border: Border(
                              bottom: BorderSide(color: Colors.grey.shade400, width: 1),
                            ),
                          ),
                          width: double.infinity,
                          padding: EdgeInsets.symmetric(horizontal: 4 * _currentScale, vertical: 2 * _currentScale), // 大幅减小padding
                          child: Row(  // 改成Row布局以减少高度
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // 左侧：走棋方和提示
                              Expanded(
                                child: Row(
                                  children: [
                                    Text(
                                      '${_currentPlayer == 'red' ? '红方' : '黑方'}:',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: _currentPlayer == 'red' ? Colors.red[700] : Colors.grey[800],
                                        fontSize: 13 * _currentScale, // 减小字体
                                      ),
                                    ),
                                    SizedBox(width: 4 * _currentScale),
                                    Expanded(
                                      child: _engineHint != null
                                        ? Text(
                                            _engineHint!,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontFamily: 'monospace',
                                              fontSize: 14 * _currentScale, // 减小字体
                                              color: _currentPlayer == 'red' ? Colors.red[800] : Colors.black,
                                            ),
                                          )
                                        : Text(
                                            _isEngineThinking ? '思考中...' : '',
                                            style: TextStyle(
                                              fontSize: 13 * _currentScale, // 减小字体
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                    ),
                                  ],
                                ),
                              ),

                              // 右侧：控制按钮
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // 切换显示箭头
                                  IconButton(
                                    iconSize: 16 * _currentScale, // 从18减小到16
                                    padding: EdgeInsets.all(1 * _currentScale), // 减小padding
                                    constraints: BoxConstraints(),
                                    icon: Icon(
                                      _showEngineArrows ? Icons.arrow_forward : Icons.arrow_forward_outlined,
                                      color: _showEngineArrows ? Colors.blue : Colors.grey,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _showEngineArrows = !_showEngineArrows;

                                        // 更新LocalData，确保ThinkingBoardLayout能正确显示或隐藏箭头
                                        LocalData().thinkingArrowEnabled.value = _showEngineArrows;

                                        // 如果切换到显示，但没有引擎提示，重新请求
                                        if (_showEngineArrows && _engineHint == null && !_isEngineThinking) {
                                          _requestEngineHint();
                                        }
                                      });
                                    },
                                  ),
                                  Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: (){

                                        print("Kevin 666 click _requestEngineHint");

                                        if(!_isEngineThinking){
                                          _requestEngineHint();
                                        }
                                      },
                                      borderRadius: BorderRadius.circular(4 * _currentScale),
                                      child: Container(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 6 * _currentScale, // 减小padding
                                          vertical: 2 * _currentScale,   // 减小padding
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.blue,
                                          borderRadius: BorderRadius.circular(4 * _currentScale),
                                        ),
                                        child: _isEngineThinking
                                          ? Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                SizedBox(
                                                  width: 10 * _currentScale, // 从12减小到10
                                                  height: 10 * _currentScale, // 从12减小到10
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 1.5 * _currentScale, // 从2减小到1.5
                                                    color: Colors.white,
                                                  ),
                                                ),
                                                SizedBox(width: 3 * _currentScale), // 从4减小到3
                                                Text(
                                                  '思考中',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 11 * _currentScale, // 从12减小到11
                                                  ),
                                                ),
                                              ],
                                            )
                                          : Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.flash_on,
                                                  size: 12 * _currentScale, // 从14减小到12
                                                  color: Colors.white,
                                                ),
                                                SizedBox(width: 2 * _currentScale),
                                                Text(
                                                  '提示',  // 简化文字
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 11 * _currentScale, // 从12减小到11
                                                  ),
                                                ),
                                              ],
                                            ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // 棋盘部分 - 使用createChessBoard函数
                        Expanded(
                          child: Builder(
                            builder: (context) {
                              // 确保ThinkingArrowEnabled值在build期间是正确的
                              LocalData().thinkingArrowEnabled.value = _showEngineArrows;
                              return createChessBoardMini(
                                context,
                                GameScene.battle,
                                opponentHuman: false,
                              );
                            }
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 通信状态指示器
          Positioned(
            top: 5,
            right: 5,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: _mainSendPort != null ? Colors.green : Colors.orange,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    // 停止捕获并清理资源
    _stopCapturing();

    // 停止引擎 - 使用try-catch避免异常影响析构
    try {
      _stopEngine();
    } catch (e) {
      print('dispose时停止引擎出错: $e');
    }

    // 清理IsolateNameServer相关资源
    _overlayReceivePort?.close();
    IsolateNameServer.removePortNameMapping(OverlayConstants.MAIN_TO_OVERLAY_PORT_NAME);

    // 发送关闭消息
    try {
      _sendMessageToMain({
        'type': 'overlay_closed',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (_) {
      // 忽略
    }

    // 取消定时器
    _stabilizeTimer?.cancel();
    _positionReportTimer?.cancel();

    super.dispose();
  }
}