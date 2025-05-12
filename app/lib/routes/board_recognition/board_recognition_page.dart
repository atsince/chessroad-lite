import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;

import '../../cchess/cc_fen.dart';
import '../../game/board_state.dart';
import '../../game/page_state.dart';
import '../../game/game.dart';
import '../../services/board_recognition_service.dart';
import '../../ui/build_utils.dart';
import '../../ui/snack_bar.dart';

class BoardRecognitionPage extends StatefulWidget {
  const BoardRecognitionPage({Key? key}) : super(key: key);

  @override
  State<BoardRecognitionPage> createState() => _BoardRecognitionPageState();
}

class _BoardRecognitionPageState extends State<BoardRecognitionPage> {
  File? _image;
  bool _isLoading = false;
  String? _fen;
  String _apiUrl = "http://49.233.44.201:39010/api/chess/detect";
  final TextEditingController _apiController = TextEditingController(
    text: "http://49.233.44.201:39010/api/chess/detect",
  );

  // 添加默认测试FEN串
  static const String _testFen = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w - - 0 1";

  // 添加日志存储
  List<String> _logs = [];

  @override
  void initState() {
    super.initState();
  }

  // 添加日志方法
  void _addLog(String log) {
    print(log);
    setState(() {
      _logs.add("${DateTime.now().toString().split('.').first}: $log");
    });
  }

  // 显示日志对话框
  void _showLogs() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('请求日志'),
        content: Container(
          width: double.maxFinite,
          height: 400,
          child: ListView.builder(
            itemCount: _logs.length,
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Text(
                  _logs[_logs.length - 1 - index],
                  style: const TextStyle(fontSize: 12),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _logs.clear();
              });
              Navigator.of(context).pop();
            },
            child: const Text('清除'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image != null) {
      setState(() {
        _image = File(image.path);
        _fen = null; // 清除之前的FEN结果
      });
      _addLog("选择了图片: ${image.path}");
    }
  }

  Future<void> _takePicture() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.camera);

    if (image != null) {
      setState(() {
        _image = File(image.path);
        _fen = null; // 清除之前的FEN结果
      });
      _addLog("拍摄了照片: ${image.path}");
    }
  }

  Future<void> _uploadImage() async {
    if (_image == null) {
      showSnackBar('请先选择图片');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    _addLog('开始上传图片: ${_image!.path}');
    _addLog('API地址: $_apiUrl');

    try {
      final fileSize = await _image!.length();
      _addLog('图片文件大小: $fileSize 字节 (${(fileSize / 1024).toStringAsFixed(2)} KB)');

      // 检查文件大小是否合理
      if (fileSize > 10 * 1024 * 1024) {
        _addLog('警告: 图片文件较大，可能会导致上传较慢或超时');
      }

      // 检查API URL格式
      final uri = Uri.parse(_apiUrl);
      _addLog('解析的URL - 协议: ${uri.scheme}, 主机: ${uri.host}, 端口: ${uri.port}, 路径: ${uri.path}');

      // 如果不是http或https协议，给出警告
      if (uri.scheme != 'http' && uri.scheme != 'https') {
        _addLog('警告: URL协议不是http或https，可能无法正常工作');
      }

      _addLog('正在发送请求...');
      final result = await BoardRecognitionService.recognizeBoard(
        _image!,
        _apiUrl,
        logCallback: _addLog
      );

      _addLog('请求完成，状态: ${result.success ? '成功' : '失败'}');
      if (!result.success) {
        _addLog('失败原因: ${result.message}');

        // 尝试给出更具体的错误提示
        if (result.message?.contains('Connection refused') == true) {
          _addLog('提示: 连接被拒绝，请检查服务器是否在运行，以及地址和端口是否正确');
        } else if (result.message?.contains('SocketException') == true) {
          _addLog('提示: 网络连接错误，请检查网络连接、服务器地址和防火墙设置');
        } else if (result.message?.contains('timeout') == true) {
          _addLog('提示: 请求超时，服务器响应时间过长');
        } else if (result.message?.contains('JSON') == true) {
          _addLog('提示: 服务器返回的不是有效的JSON格式，可能不是正确的API端点');
        }
      } else {
        _addLog('返回的FEN: ${result.fen}');
        _addLog('识别用时: ${result.timeMs}毫秒');

        // 验证FEN字符串格式
        if (result.fen != null && result.fen!.isNotEmpty) {
          final fenParts = result.fen!.split(' ');
          if (fenParts.length >= 4) {
            _addLog('FEN格式有效，包含 ${fenParts.length} 个部分');
          } else {
            _addLog('警告: FEN格式可能不完整，只有 ${fenParts.length} 个部分，标准FEN应至少有4个部分');
          }
        }
      }

      setState(() {
        _isLoading = false;
      });

      if (result.success) {
        setState(() {
          _fen = result.fen;
        });
        showSnackBar('识别成功: ${result.timeMs}毫秒');
      } else {
        showSnackBar('识别失败: ${result.message}');
      }
    } catch (e) {
      _addLog('捕获到异常: $e');

      if (e.toString().contains('HandshakeException')) {
        _addLog('提示: SSL/TLS握手失败，这可能是因为服务器证书无效或不受信任');
      } else if (e.toString().contains('SocketException')) {
        _addLog('提示: 网络套接字错误，服务器可能未运行或不可达');
      }

      setState(() {
        _isLoading = false;
      });
      showSnackBar('上传出错: $e');
    }
  }

  void _loadFenToBoard() {
    if (_fen == null || _fen!.isEmpty) {
      showSnackBar('没有有效的FEN字符串');
      return;
    }

    final BoardState boardState = Provider.of<BoardState>(context, listen: false);
    final success = boardState.load(_fen!, notify: true);

    if (success) {
      _addLog('成功加载FEN到棋盘: $_fen');
      showSnackBar('棋盘已加载');
    } else {
      _addLog('加载FEN到棋盘失败: $_fen');
      showSnackBar('加载棋盘失败，FEN格式可能不正确');
    }
  }

  // 添加测试API连接的方法
  Future<void> _testApiConnection() async {
    _addLog('正在测试API连接: $_apiUrl');
    setState(() {
      _isLoading = true;
    });

    try {
      // 尝试发送一个简单的GET请求
      final uri = Uri.parse(_apiUrl);
      _addLog('发送测试请求到: $uri');

      final response = await http.get(uri).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('请求超时，检查API地址或网络连接');
        },
      );

      _addLog('收到测试响应，状态码: ${response.statusCode}');
      _addLog('响应内容: ${response.body.length > 100 ? response.body.substring(0, 100) + "..." : response.body}');

      if (response.statusCode == 200) {
        showSnackBar('API连接成功!');
      } else {
        showSnackBar('API返回错误状态码: ${response.statusCode}');
      }
    } catch (e) {
      _addLog('测试连接失败: $e');
      showSnackBar('无法连接到API: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // 添加加载测试FEN的方法
  void _loadTestFen() {
    _addLog('加载测试FEN串: $_testFen');
    setState(() {
      _fen = _testFen;
    });

    final BoardState boardState = Provider.of<BoardState>(context, listen: false);
    final success = boardState.load(_testFen, notify: true);

    if (success) {
      _addLog('成功加载测试FEN到棋盘');
      showSnackBar('已加载测试棋盘');
    } else {
      _addLog('加载测试FEN到棋盘失败');
      showSnackBar('加载测试棋盘失败');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('棋盘识别'),
        actions: [
          IconButton(
            icon: const Icon(Icons.visibility),
            onPressed: _showLogs,
            tooltip: '查看日志',
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('API设置'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: _apiController,
                        decoration: const InputDecoration(
                          labelText: 'API地址',
                          hintText: 'http://localhost:39008/api/chess/detect',
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _testApiConnection();
                        },
                        icon: const Icon(Icons.network_check),
                        label: const Text('测试连接'),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      child: const Text('取消'),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _apiUrl = _apiController.text;
                        });
                        Navigator.of(context).pop();
                        _addLog('API地址已更新为: $_apiUrl');
                        showSnackBar('API地址已更新');
                      },
                      child: const Text('确定'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 20),

            // 图片选择按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.photo_library),
                  label: const Text('从相册选择'),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  onPressed: _takePicture,
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('拍照'),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // 添加测试FEN按钮
            OutlinedButton.icon(
              onPressed: _loadTestFen,
              icon: const Icon(Icons.dashboard),
              label: const Text('加载测试棋盘'),
            ),

            const SizedBox(height: 20),

            // 显示选中的图片
            if (_image != null)
              Container(
                width: MediaQuery.of(context).size.width * 0.8,
                height: MediaQuery.of(context).size.width * 0.8,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                ),
                child: Image.file(
                  _image!,
                  fit: BoxFit.contain,
                ),
              ),

            const SizedBox(height: 20),

            // 上传按钮
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _uploadImage,
              icon: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.upload),
              label: Text(_isLoading ? '识别中...' : '上传识别'),
            ),

            const SizedBox(height: 20),

            // 显示FEN字符串
            if (_fen != null)
              Container(
                width: MediaQuery.of(context).size.width * 0.9,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('识别结果 (FEN):', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 5),
                    Text(_fen!, style: const TextStyle(fontFamily: 'monospace')),
                    const SizedBox(height: 10),
                    Center(
                      child: ElevatedButton(
                        onPressed: _loadFenToBoard,
                        child: const Text('加载到棋盘'),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 20),

            // 显示棋盘
            if (_fen != null)
              Consumer<BoardState>(
                builder: (context, boardState, child) {
                  return Column(
                    children: [
                      const Text('预览', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      createChessBoard(context, GameScene.battle),
                    ],
                  );
                },
              ),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}