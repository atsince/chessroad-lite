import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

class SimpleOverlayService {
  // 单例模式
  static final SimpleOverlayService _instance = SimpleOverlayService._internal();
  factory SimpleOverlayService() => _instance;
  SimpleOverlayService._internal();

  bool _isOverlayActive = false;
  bool get isOverlayActive => _isOverlayActive;

  // 显示简易悬浮窗
  Future<bool> showSimpleOverlay() async {
    debugPrint('准备显示简易悬浮窗...');

    // 首先检查悬浮窗是否已经激活
    try {
      final isActive = await FlutterOverlayWindow.isActive();
      if (isActive) {
        debugPrint('悬浮窗已经处于激活状态');
        _isOverlayActive = true;
        return true;
      }
    } catch (e) {
      debugPrint('检查悬浮窗状态时出错: $e');
    }

    // 检查权限
    if (!await FlutterOverlayWindow.isPermissionGranted()) {
      debugPrint('悬浮窗权限未授予，请求权限...');
      final granted = await FlutterOverlayWindow.requestPermission();
      if (!(granted ?? false)) {
        debugPrint('用户拒绝授予悬浮窗权限');
        return false;
      }
      debugPrint('悬浮窗权限已授予');
    } else {
      debugPrint('悬浮窗权限已经获取');
    }

    try {
      // 设置悬浮窗参数
      debugPrint('显示悬浮窗...');
      await FlutterOverlayWindow.showOverlay(
        height: 150,         // 设置高度为150
        width: 150,          // 设置宽度为150
        alignment: OverlayAlignment.center, // 居中显示
        flag: OverlayFlag.defaultFlag,
        visibility: NotificationVisibility.visibilityPublic,
        enableDrag: true,    // 允许拖动
        positionGravity: PositionGravity.auto,
        overlayTitle: "简易悬浮窗",
        overlayContent: "绿色悬浮窗演示",
      );

      debugPrint('悬浮窗显示成功');
      _isOverlayActive = true;
      return true;
    } catch (e) {
      debugPrint('显示悬浮窗失败: $e');
      _isOverlayActive = false;
      return false;
    }
  }

  // 关闭悬浮窗
  Future<void> closeOverlay() async {
    debugPrint('正在关闭悬浮窗...');
    try {
      await FlutterOverlayWindow.closeOverlay();
      debugPrint('悬浮窗关闭成功');
    } catch (e) {
      debugPrint('关闭悬浮窗出错: $e');
    } finally {
      _isOverlayActive = false;
    }
  }
}