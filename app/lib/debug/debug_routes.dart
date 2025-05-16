import 'package:flutter/material.dart';
import 'screenshot_test_page.dart';

/// 调试路由类，提供各种调试功能的入口
class DebugRoutes {
  /// 打开截屏测试页面
  static Future<void> openScreenshotTestPage(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const ScreenshotTestPage(),
      ),
    );
  }

  /// 展示调试菜单
  static void showDebugMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '调试菜单',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.screenshot),
              title: const Text('截屏测试'),
              subtitle: const Text('调试media_projection_screenshot功能'),
              onTap: () {
                Navigator.pop(context);
                openScreenshotTestPage(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}