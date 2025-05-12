import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

// 定义日志回调函数类型
typedef LogCallback = void Function(String message);

class BoardRecognitionResult {
  final bool success;
  final String? fen;
  final String? message;
  final int timeMs;

  BoardRecognitionResult({
    required this.success,
    this.fen,
    this.message,
    required this.timeMs,
  });

  factory BoardRecognitionResult.fromJson(Map<String, dynamic> json) {
    print('解析返回的JSON: $json');
    return BoardRecognitionResult(
      success: json['success'] ?? false,
      fen: json['fen'],
      message: json['message'],
      timeMs: json['time'] ?? 0,
    );
  }

  factory BoardRecognitionResult.error(String errorMessage) {
    print('创建错误结果: $errorMessage');
    return BoardRecognitionResult(
      success: false,
      message: errorMessage,
      timeMs: 0,
    );
  }
}

class BoardRecognitionService {
  static Future<BoardRecognitionResult> recognizeBoard(
    File imageFile,
    String apiUrl, {
    LogCallback? logCallback,
  }) async {
    // 定义一个记录日志的内部方法
    void log(String message) {
      print(message);
      if (logCallback != null) {
        logCallback(message);
      }
    }

    try {
      log('BoardRecognitionService: 准备创建请求');
      final request = http.MultipartRequest('POST', Uri.parse(apiUrl));

      log('BoardRecognitionService: 添加文件到请求');
      final filename = path.basename(imageFile.path);
      log('BoardRecognitionService: 文件名: $filename');

      request.files.add(
        await http.MultipartFile.fromPath(
          'image',
          imageFile.path,
          filename: filename,
        ),
      );

      log('BoardRecognitionService: 发送请求到 $apiUrl');
      final streamedResponse = await request.send();

      log('BoardRecognitionService: 收到响应，状态码: ${streamedResponse.statusCode}');
      log('BoardRecognitionService: 响应头: ${streamedResponse.headers}');

      final responseData = await streamedResponse.stream.bytesToString();
      log('BoardRecognitionService: 响应体长度: ${responseData.length}');
      log('BoardRecognitionService: 响应体前100个字符: ${responseData.length > 100 ? responseData.substring(0, 100) : responseData}');

      try {
        final result = jsonDecode(responseData);
        log('BoardRecognitionService: JSON解析成功');
        return BoardRecognitionResult.fromJson(result);
      } catch (jsonError) {
        log('BoardRecognitionService: JSON解析失败: $jsonError');
        return BoardRecognitionResult.error('响应不是有效的JSON格式: $jsonError, 原始响应: ${responseData.length > 100 ? responseData.substring(0, 100) + "..." : responseData}');
      }
    } catch (e) {
      log('BoardRecognitionService: 请求过程中发生异常: $e');
      return BoardRecognitionResult.error('请求失败: $e');
    }
  }
}