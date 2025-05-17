import 'dart:async';

import 'package:chessroad/config/local_data.dart';
import 'package:chessroad/debug/debug_routes.dart';
import 'package:chessroad/engine/hybrid_engine.dart';
import 'package:chessroad/routes/board_recognition/board_recognition_page.dart';
import 'package:chessroad/routes/main_menu/privacy_policy.dart';
import 'package:chessroad/services/overlay_service.dart';
import 'package:chessroad/services/simple_overlay_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../ad/ad.dart';
import '../../game/game.dart';
import '../../services/audios.dart';
import '../../ui/ruler.dart';
import '../battle/battle_page.dart';
import '../saved_manuals.dart';
import '../settings/settings_page.dart';
import 'flowers_mixin.dart';
import 'readme.dart';

class MainMenu extends StatefulWidget {
  //
  const MainMenu({Key? key}) : super(key: key);

  @override
  MainMenuState createState() => MainMenuState();
}

class MainMenuState extends State<MainMenu>
    with TickerProviderStateMixin, FlowersMixin {
  //
  late AnimationController _inController, _shadowController;
  late Animation _inAnimation, _shadowAnimation;

  bool _waitingInit = true;
  bool _debugMode = true; // 调试模式开关
  int _debugTapCount = 0; // 用于激活调试模式的点击计数器
  Timer? _debugTapTimer; // 用于重置点击计数的定时器
  StreamSubscription? _overlayDataSubscription; // 悬浮窗数据订阅
  String? _lastRecognizedFen; // 最近识别的FEN
  String? _lastEngineHint; // 最近的引擎提示
  DateTime? _lastUpdateTime; // 最后更新时间

  // 添加简易悬浮窗状态
  bool _isSimpleOverlayShown = false;
  final SimpleOverlayService _simpleOverlayService = SimpleOverlayService();

  @override
  void initState() {
    //
    super.initState();

    initSync();
    initAsync();
    _setupOverlayListener();
  }

  void initSync() {
    //
    _inController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _inAnimation = CurvedAnimation(
      parent: _inController,
      curve: Curves.bounceIn,
    );
    _inAnimation = Tween(begin: 1.6, end: 1.0).animate(_inController);

    _shadowController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _shadowAnimation = Tween(begin: 0.0, end: 12.0).animate(_shadowController);

    _inController.addStatusListener((status) {
      if (status == AnimationStatus.completed) _shadowController.forward();
    });
    _shadowController.addStatusListener((status) {
      if (status == AnimationStatus.completed) _shadowController.reverse();
    });

    _inAnimation.addListener(() {
      if (mounted) setState(() {});
    });
    _shadowAnimation.addListener(() {
      if (mounted) setState(() {});
    });

    _inController.forward();
  }

  Future<void> initAsync() async {
    //
    await LocalData().load();

    if (!mounted) return;

    createFlowers(context, this, () => setState(() {}));

    bool newUser = await checkPrivacyPolicy();

    await Ad.instance.init();

    startSplashAd(newUser);

    Audios.init();

    await HybridEngine().startup();

    setState(() => _waitingInit = false);

    Audios.loopBgm();
  }

  Future<void> startSplashAd(bool newUser) async {
    //
    if (!newUser) {
      //
      int counterDown = 30;

      while ((!mounted || !Ad.instance.initCompleted) && counterDown > 0) {
        await Future.delayed(const Duration(milliseconds: 100));
        counterDown--;
      }

      if (counterDown > 0 && mounted) {
        await Ad.instance.showSplashVideo(context);
      }
    }
  }

  checkPrivacyPolicy() async {
    //
    if (!LocalData().acceptedPrivacyPolicy.value) {
      await openPrivacyPolicy(context);
      return true;
    }

    return false;
  }

  String charRepeat(String ch, int times) {
    //
    var result = '';

    for (var i = 0; i < times; i++) {
      result += ch;
    }

    return result;
  }

  // 处理标题点击，用于激活调试模式
  void _handleTitleTap() {
    _debugTapCount++;

    // 重置点击计数器的定时器
    _debugTapTimer?.cancel();
    _debugTapTimer = Timer(const Duration(seconds: 2), () {
      _debugTapCount = 0;
    });

    // 连续点击5次激活调试模式
    if (_debugTapCount >= 5) {
      setState(() {
        _debugMode = !_debugMode;
        _debugTapCount = 0;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('调试模式: ${_debugMode ? "已开启" : "已关闭"}'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  // 设置悬浮窗消息监听
  void _setupOverlayListener() {
    final overlayService = OverlayService();

    // 取消之前的订阅（如果有）
    _overlayDataSubscription?.cancel();

    // 监听来自悬浮窗的数据
    _overlayDataSubscription = overlayService.dataStream.listen((data) {
      _handleOverlayData(data);
    });
  }

  // 处理来自悬浮窗的数据
  void _handleOverlayData(Map<String, dynamic> data) {
    if (!mounted) return;

    // 根据数据类型处理不同的消息
    if (data.containsKey('type')) {
      final type = data['type'];

      switch (type) {
        case 'analysis_result':
          // 处理棋盘分析结果
          if (data.containsKey('fen') && data.containsKey('player')) {
            setState(() {
              _lastRecognizedFen = data['fen'];
              if (data.containsKey('engineHint')) {
                _lastEngineHint = data['engineHint'];
              }
              _lastUpdateTime = DateTime.now();
            });

            // 如果需要，可以在这里显示分析结果通知
            if (_debugMode) {
              _showOverlayUpdateNotification('收到棋盘识别结果');
            }
          }
          break;

        case 'status':
        case 'error':
          // 处理状态更新或错误消息
          if (data.containsKey('message')) {
            final message = data['message'];
            final isError = type == 'error';

            if (_debugMode) {
              _showOverlayUpdateNotification(
                isError ? '悬浮窗错误: $message' : '悬浮窗状态: $message',
                isError: isError,
              );
            }
          }
          break;

        case 'toggle_capture':
          // 处理捕获状态切换
          if (_debugMode) {
            _showOverlayUpdateNotification('悬浮窗捕获状态切换');
          }
          break;

        default:
          print('收到未知类型的悬浮窗消息: $type');
          break;
      }
    }
  }

  // 显示悬浮窗更新通知
  void _showOverlayUpdateNotification(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        backgroundColor: isError ? Colors.red : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    //
    if (_waitingInit) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Text('加载中', style: TextStyle(color: Colors.white)),
        ),
      );
    }

    final nameShadow = Shadow(
      color: const Color.fromARGB(0x99, 66, 0, 0),
      offset: Offset(0, _shadowAnimation.value / 2),
      blurRadius: _shadowAnimation.value,
    );

    final nameStyle = TextStyle(
      fontSize: 64,
      fontFamily: LocalData().artFont.value,
      color: Colors.black,
      shadows: [nameShadow],
    );

    Widget buildActionCtrls() {
      //
      final menuItemStyle = GameFonts.art(
        fontSize: 28,
        color: GameColors.primary,
      );

      return Expanded(
        flex: 8,
        child: Column(
          children: [
            TextButton(
              child: Text(
                '人机练习',
                style: menuItemStyle,
              ),
              onPressed: () => navigateTo(GameScene.battle),
            ),
            // const Expanded(child: SizedBox()),
            // TextButton(
            //   child: Text(
            //     '我的对局',
            //     style: menuItemStyle,
            //   ),
            //   onPressed: () => navigateTo(GameScene.gameNotation),
            // ),
            // const Expanded(child: SizedBox()),
            TextButton(
              child: Text(
                '棋盘识别',
                style: menuItemStyle,
              ),
              onPressed: () => Navigator.of(context).push(
                CupertinoPageRoute(
                  builder: (context) => const BoardRecognitionPage(),
                ),
              ),
            ),
            // 添加简易悬浮窗按钮
            TextButton(
              onPressed: _toggleSimpleOverlay,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('简易悬浮窗', style: menuItemStyle),
                  const SizedBox(width: 8),
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: _isSimpleOverlayShown ? Colors.green : Colors.grey,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
            ),
            const Expanded(child: SizedBox()),
            TextButton(
              onPressed: () => showReadme(context),
              child: Text('版本说明', style: menuItemStyle),
            ),
            const Expanded(child: SizedBox()),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: _toggleOverlay,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('棋盘识别悬浮窗', style: menuItemStyle),
                      const SizedBox(width: 8),
                      // 显示悬浮窗状态指示器
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: _isOverlayShown ? Colors.green : Colors.grey,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // 如果有调试模式且悬浮窗已经打开，显示最近识别的信息
            if (_debugMode && _isOverlayShown && _lastRecognizedFen != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Text(
                      '悬浮窗最新识别:',
                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                    ),
                    const SizedBox(height: 4),
                    if (_lastEngineHint != null)
                      Text(
                        _lastEngineHint!,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    if (_lastUpdateTime != null)
                      Text(
                        '更新时间: ${_formatTime(_lastUpdateTime!)}',
                        style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                      ),
                  ],
                ),
              ),
            ],
            const Expanded(flex: 3, child: SizedBox()),
          ],
        ),
      );
    }

    final mainEntries = Center(
      child: Column(
        children: <Widget>[
          const Expanded(flex: 2, child: SizedBox()),
          Hero(tag: 'logo', child: Image.asset('images/logo.png')),
          const Expanded(child: SizedBox()),
          GestureDetector(
            onTap: _handleTitleTap, // 添加点击处理
            child: Transform.scale(
              scale: _inAnimation.value,
              child: Text(
                '象棋课堂',
                style: nameStyle,
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const Expanded(child: SizedBox()),
          buildActionCtrls(),
          const Expanded(flex: 2, child: SizedBox()),
          Container(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '用心娱乐，为爱传承',
                style: GameFonts.art(color: Colors.black54, fontSize: 16),
              ),
              // 添加调试模式按钮
              if (_debugMode)
                IconButton(
                  icon: const Icon(Icons.bug_report, color: Colors.grey),
                  onPressed: () => DebugRoutes.showDebugMenu(context),
                  tooltip: '打开调试菜单',
                ),
            ],
          ),
          const Expanded(child: SizedBox()),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: GameColors.menuBackground,
      body: Stack(
        children: <Widget>[
          const Positioned(
            right: 0,
            top: 0,
            child: Image(image: AssetImage('images/mei.png')),
          ),
          const Positioned(
            left: 0,
            bottom: 0,
            child: Image(image: AssetImage('images/zhu.png')),
          ),
          buildFlowersCanvas(),
          mainEntries,
          Positioned(
            top: Ruler.statusBarHeight(context),
            left: 10,
            child: IconButton(
              icon: const Icon(Icons.settings, color: GameColors.primary),
              onPressed: () async {
                await Navigator.of(context).push(
                  CupertinoPageRoute(
                    builder: (context) => const SettingsPage(),
                  ),
                );
                _inController.forward();
              },
            ),
          ),
        ],
      ),
    );
  }

  navigateTo(GameScene scene) async {
    //
    Widget page;

    switch (scene) {
      case GameScene.battle:
        page = const BattlePage();
        break;

      case GameScene.gameNotation:
        page = const SavedManuals();
        break;

      case GameScene.unknown:
        throw 'Scene is not define.';
    }

    await Navigator.of(context).push(
      CupertinoPageRoute(builder: (context) => page),
    );

    _inController.reset();
    _shadowController.reset();
    _inController.forward();
  }

  bool _isOverlayShown = false;

  void _toggleOverlay() async {
    OverlayService service = OverlayService();

    if (_isOverlayShown) {
      await service.closeOverlay();
      setState(() => _isOverlayShown = false);
    } else {
      final result = await service.showOverlay();
      setState(() => _isOverlayShown = result);

      if (result) {
        // 悬浮窗显示成功，发送测试消息
        await Future.delayed(const Duration(milliseconds: 500));
        await service.sendCommand('test_connection', {
          'message': '主应用连接测试',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });

        // 如果需要，可以自动开始捕获
        // await service.startCapture();
      }
    }
  }

  void _changeOverlayColor() async {
    // 已弃用
  }

  @override
  void dispose() {
    _debugTapTimer?.cancel();
    _overlayDataSubscription?.cancel();
    //
    _inController.dispose();
    _shadowController.dispose();

    super.dispose();
  }

  // 格式化时间
  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  }

  // 切换简易悬浮窗显示状态
  void _toggleSimpleOverlay() async {
    if (_isSimpleOverlayShown) {
      await _simpleOverlayService.closeOverlay();
      setState(() => _isSimpleOverlayShown = false);
    } else {
      final result = await _simpleOverlayService.showSimpleOverlay();
      setState(() => _isSimpleOverlayShown = result);
    }
  }
}
