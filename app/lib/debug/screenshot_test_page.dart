import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:media_projection_screenshot/media_projection_screenshot.dart';
import 'package:media_projection_screenshot/captured_image.dart';
import 'package:path_provider/path_provider.dart';

class ScreenshotTestPage extends StatefulWidget {
  const ScreenshotTestPage({Key? key}) : super(key: key);

  @override
  State<ScreenshotTestPage> createState() => _ScreenshotTestPageState();
}

class _ScreenshotTestPageState extends State<ScreenshotTestPage> {
  final MediaProjectionScreenshot _screenshotPlugin = MediaProjectionScreenshot();
  CapturedImage? _capturedImage;
  String _statusText = "准备就绪";
  bool _capturingStream = false;
  Uint8List? _displayBytes;
  String? _savePath;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    // 确保停止任何正在进行的捕获
    _stopStreamCapture();
    super.dispose();
  }

  // 请求截屏权限
  Future<void> _requestPermission() async {
    setState(() {
      _statusText = "请求权限中...";
    });

    try {
      final result = await _screenshotPlugin.requestPermission();
      setState(() {
        _statusText = "权限结果: $result (0表示成功)";
      });
    } catch (e) {
      setState(() {
        _statusText = "请求权限出错: $e";
      });
    }
  }

  // 单次截屏
  Future<void> _takeSingleCapture() async {
    // 打印当前线程信息
    print('[Kevin 666 ${Isolate.current.debugName}] 开始单次截屏');
    setState(() {
      _statusText = "截屏中...";
      _displayBytes = null;
    });

    try {
      // 尝试两种方式捕获屏幕
      try {
        // 方式1: 不指定区域参数
        _capturedImage = await _screenshotPlugin.takeCapture();
      } catch (e) {
        print("方式1捕获失败，尝试方式2: $e");
        // 方式2: 指定全屏区域
        _capturedImage = await _screenshotPlugin.takeCapture(
          x: 0,
          y: 0,
          width: -1, // 使用-1表示全屏宽度
          height: -1, // 使用-1表示全屏高度
        );
      }

      if (_capturedImage != null) {
        setState(() {
          _statusText = "截屏成功 - 宽: ${_capturedImage!.width}, 高: ${_capturedImage!.height}";
          _displayBytes = _capturedImage!.bytes;
        });
        // 保存图像到文件
        await _saveImageToFile(_capturedImage!.bytes);
      } else {
        setState(() {
          _statusText = "截屏失败 - 返回null";
        });
      }
    } catch (e) {
      setState(() {
        _statusText = "截屏出错: $e";
      });
    }
  }

  // 开始流式截屏
  Future<void> _startStreamCapture() async {
    if (_capturingStream) return;

    setState(() {
      _statusText = "开始流式截屏...";
      _capturingStream = true;
    });

    try {
      // 尝试两种方式开始流式捕获
      Stream<dynamic>? captureStream;

      try {
        // 方式1: 不指定区域参数
        captureStream = await _screenshotPlugin.startCapture();
      } catch (e) {
        print("方式1流式捕获失败，尝试方式2: $e");
        // 方式2: 指定全屏区域
        captureStream = await _screenshotPlugin.startCapture(
          x: 0,
          y: 0,
          width: -1,
          height: -1,
        );
      }

      if (captureStream != null) {
        captureStream.listen(
          (data) {
            if (data != null) {
              try {
                final capturedImage = CapturedImage.fromMap(Map<String, dynamic>.from(data));
                setState(() {
                  _capturedImage = capturedImage;
                  _displayBytes = capturedImage.bytes;
                  _statusText = "收到流数据 - 宽: ${capturedImage.width}, 高: ${capturedImage.height}";
                });
                // 保存最新的图像
                _saveImageToFile(capturedImage.bytes);
              } catch (e) {
                print("解析流数据失败: $e");
              }
            }
          },
          onError: (error) {
            setState(() {
              _statusText = "流捕获错误: $error";
              _capturingStream = false;
            });
          },
          onDone: () {
            setState(() {
              _statusText = "流捕获完成";
              _capturingStream = false;
            });
          },
        );
      } else {
        setState(() {
          _statusText = "开始流捕获失败 - 返回null";
          _capturingStream = false;
        });
      }
    } catch (e) {
      setState(() {
        _statusText = "开始流捕获出错: $e";
        _capturingStream = false;
      });
    }
  }

  // 停止流式截屏
  Future<void> _stopStreamCapture() async {
    if (!_capturingStream) return;

    setState(() {
      _statusText = "停止流式截屏...";
    });

    try {
      await _screenshotPlugin.stopCapture();
      setState(() {
        _statusText = "流式截屏已停止";
        _capturingStream = false;
      });
    } catch (e) {
      setState(() {
        _statusText = "停止流式截屏出错: $e";
        _capturingStream = false;
      });
    }
  }

  // 保存图像到文件
  Future<void> _saveImageToFile(Uint8List bytes) async {
    try {
      final directory = await getExternalStorageDirectory() ?? await getTemporaryDirectory();
      final filePath = '${directory.path}/screenshot_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final file = File(filePath);
      await file.writeAsBytes(bytes);

      setState(() {
        _savePath = filePath;
      });

      print("截图已保存到: $filePath");
    } catch (e) {
      print("保存图像失败: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('截屏调试测试'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('调试信息'),
                  content: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('状态: $_statusText'),
                        if (_capturedImage != null) ...[
                          const SizedBox(height: 8),
                          Text('宽度: ${_capturedImage!.width}'),
                          Text('高度: ${_capturedImage!.height}'),
                        ],
                        if (_savePath != null) ...[
                          const SizedBox(height: 8),
                          Text('保存路径: $_savePath'),
                        ],
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      child: const Text('关闭'),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              _statusText,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          const Divider(),
          Expanded(
            child: _displayBytes != null
                ? Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Image.memory(
                      _displayBytes!,
                      fit: BoxFit.contain,
                    ),
                  )
                : const Center(
                    child: Text('截图将显示在这里'),
                  ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                ElevatedButton(
                  onPressed: _requestPermission,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                  ),
                  child: const Text('请求权限'),
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: _takeSingleCapture,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                  ),
                  child: const Text('单次截屏'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _capturingStream ? null : _startStreamCapture,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                        ),
                        child: const Text('开始流式截屏'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _capturingStream ? _stopStreamCapture : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                        ),
                        child: const Text('停止流式截屏'),
                      ),
                    ),
                  ],
                ),
                if (_savePath != null) ...[
                  const SizedBox(height: 10),
                  Text('保存路径: $_savePath',
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}