import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../network/request.dart';
import '../../utils/image_saver.dart';

class PhotoController extends GetxController {
  final pageController = PageController();
  // 当前正在查看的图片索引（用于上下滑动也能切换）
  final currentIndex = 0.obs;

  void _showAdaptiveSnackbar({
    required String title,
    required String message,
    required bool success,
  }) {
    final theme = Get.theme;
    final cs = theme.colorScheme;
    final isDark = Get.isDarkMode || theme.brightness == Brightness.dark || cs.brightness == Brightness.dark;

    // 亮色模式：白底黑字；暗色模式：深色底白字
    final bgColor = isDark ? const Color(0xFF1F1F1F).withOpacity(0.95) : Colors.white.withOpacity(0.95);
    final textColor = isDark ? Colors.white : Colors.black87;
    final shadowColor = isDark ? Colors.black.withOpacity(0.45) : Colors.black.withOpacity(0.15);

    Get.snackbar(
      title,
      message,
      snackPosition: SnackPosition.BOTTOM,
      snackStyle: SnackStyle.FLOATING,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      borderRadius: 16,
      backgroundColor: bgColor,
      colorText: textColor,
      icon: Icon(
        success ? Icons.check_circle_rounded : Icons.error_rounded,
        color: success ? cs.primary : cs.error,
      ),
      duration: const Duration(seconds: 2),
      isDismissible: true,
      shouldIconPulse: false,
      boxShadows: [
        BoxShadow(
          color: shadowColor,
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  Future<void> saveImage(String url) async {
    final (ok, msg) = await ImageSaver.saveNetworkImage(url: url, headers: Request.userAgent);
    if (ok) {
      _showAdaptiveSnackbar(title: '保存图片成功', message: msg, success: true);
    } else {
      _showAdaptiveSnackbar(title: '保存图片失败', message: msg, success: false);
    }
  }

  @override
  void onReady() {
    super.onReady();
    if (Get.arguments["gallery_mode"]) {
      final idx = (Get.arguments["index"] ?? 0) as int;
      currentIndex.value = idx;
      pageController.jumpToPage(idx);
    }
  }
}