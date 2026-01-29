import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hikari_novel_flutter/models/resource.dart';
import 'package:hikari_novel_flutter/models/user_info.dart';
import 'package:hikari_novel_flutter/network/api.dart';
import 'package:hikari_novel_flutter/router/route_path.dart';

import '../../service/local_storage_service.dart';

class MyController extends GetxController {
  Rxn<UserInfo> userInfo = Rxn(LocalStorageService.instance.getUserInfo());

  final RxBool isCheckingIn = false.obs;

  /// 是否已签到（用于把按钮变为“已签到”）
  final RxBool hasCheckedIn = false.obs;

  final usernameController = TextEditingController();
  final passwordController = TextEditingController();

  final LocalAuthentication _localAuth = LocalAuthentication();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  String _pwdKey(String username) => "checkin_pwd_${username.trim()}";

  Future<bool> _isBiometricSupported() async {
    try {
      final supported = await _localAuth.isDeviceSupported();
      final canCheck = await _localAuth.canCheckBiometrics;
      return supported || canCheck;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _authenticateForCheckIn() async {
    try {
      return await _localAuth.authenticate(
        localizedReason: "使用指纹/面容验证以进行签到",
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }


  void logout() {
    LocalStorageService.instance.setCookie(null);
    hasCheckedIn.value = false;
    Get.offAndToNamed(RoutePath.welcome);
  }

  void _showAdaptiveSnackBar(String message) {
    final context = Get.context;
    if (context == null) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(color: isDark ? Colors.white : Colors.black),
        ),
        backgroundColor: isDark ? Colors.grey[900] : Colors.white,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _friendlyCheckInError(Object? e) {
    final s = (e ?? "").toString();
    // 常见 Dio 提示里会包含 status code
    if (s.contains("status code of 404") || s.contains("status code 404")) {
      return "签到接口返回 404（当前节点可能不支持签到，可在设置里切换节点后重试）";
    }
    if (s.contains("status code of 403") || s.contains("status code 403")) {
      return "签到被拒绝（403），可能需要重新登录后再试";
    }
    if (s.contains("SocketException") || s.contains("Failed host lookup")) {
      return "网络异常，请检查网络或稍后重试";
    }
    // 兜底：不要把整段 DioException 直接显示给用户
    return "签到失败，请稍后重试（可尝试在设置里切换节点）";
  }

  String _pickXmlValue(String xml, String key) {
    final reg = RegExp('<item name="$key">(.*?)</item>', caseSensitive: false);
    final match = reg.firstMatch(xml);
    return match?.group(1) ?? "0";
  }

  Future<_CheckInInput?> _showCheckInDialog() async {
    final savedUsername = LocalStorageService.instance.getUsername() ?? "";
    final biometricEnabled = LocalStorageService.instance.getBiometricCheckInEnabled();
    final biometricSupported = await _isBiometricSupported();

    usernameController.text = savedUsername;
    passwordController.clear();

    final rememberUsername = (savedUsername.isNotEmpty).obs;
    final enableBiometric = (biometricEnabled && biometricSupported).obs;

    return Get.dialog<_CheckInInput>(
      AlertDialog(
        title: const Text("签到"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: usernameController,
              decoration: const InputDecoration(labelText: "用户名"),
            ),
            TextField(
              controller: passwordController,
              decoration: const InputDecoration(labelText: "密码"),
              obscureText: true,
            ),
            const SizedBox(height: 8),
            Obx(
              () => Row(
                children: [
                  Checkbox(
                    value: rememberUsername.value,
                    onChanged: (v) => rememberUsername.value = v ?? false,
                  ),
                  const Text("记住用户名"),
                ],
              ),
            ),
            if (biometricSupported) ...[
              const SizedBox(height: 4),
              Obx(
                () => Row(
                  children: [
                    Checkbox(
                      value: enableBiometric.value,
                      onChanged: (v) => enableBiometric.value = v ?? false,
                    ),
                    const Expanded(child: Text("启用指纹/面容签到（密码安全保存）")),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text("取消")),
          TextButton(
            onPressed: () {
              Get.back(
                result: _CheckInInput(
                  username: usernameController.text,
                  password: passwordController.text,
                  rememberUsername: rememberUsername.value,
                  enableBiometric: enableBiometric.value,
                ),
              );
            },
            child: const Text("签到"),
          ),
        ],
      ),
    );
  }

  /// fallback：使用网页登录态尝试签到（适用于 relay 不稳定/限流时）
  Future<bool> _fallbackWebCheckIn() async {
    try {
      final r = await Api.checkIn();
      if (r is Success<String>) {
        final s = (r.data ?? "").toString();
        if (s.contains("已签") || s.contains("已经签") || s.contains("已签到")) {
          hasCheckedIn.value = true;
          _showAdaptiveSnackBar("你今天已经签到过了");
          return true;
        }
        if (s.contains("成功") || s.contains("签到") || s.contains("reward")) {
          hasCheckedIn.value = true;
          _showAdaptiveSnackBar("签到成功");
          return true;
        }
        _showAdaptiveSnackBar("已尝试网页签到（返回内容已获取）");
        return false;
      }
      _showAdaptiveSnackBar("网页签到失败，请稍后重试");
      return false;
    } catch (e) {
      _showAdaptiveSnackBar("网页签到失败，请检查网络或稍后再试");
      return false;
    }
  }

  /// 解析 relay 返回并更新 UI，返回是否处理完成（含成功/已签/明确失败）
  bool _handleRelayResp(String resp) {
    resp = resp.trim();

    if (resp == "2") {
      _showAdaptiveSnackBar("用户名或密码错误");
      return true;
    }

    // 9：原版实现中表示“今日已签到”
    if (resp == "9") {
      hasCheckedIn.value = true;
      _showAdaptiveSnackBar("你今天已经签到过了");
      return true;
    }

    // 3：兼容某些实现里表示“已签到”
    if (resp == "3") {
      hasCheckedIn.value = true;
      _showAdaptiveSnackBar("你今天已经签到过了");
      return true;
    }

    if (resp.contains("<item")) {
      final score = _pickXmlValue(resp, "score");
      final exp = _pickXmlValue(resp, "experience");
      hasCheckedIn.value = true;
      _showAdaptiveSnackBar("签到成功：积分 +$score，经验 +$exp");
      return true;
    }

    if (resp.isNotEmpty) {
      hasCheckedIn.value = true;
      _showAdaptiveSnackBar(resp);
      return true;
    }
    return false;
  }

  Future<void> checkIn() async {
    if (isCheckingIn.value) return;
    if (userInfo.value == null) {
      _showAdaptiveSnackBar("请先登录后再签到");
      return;
    }

    // 指纹/面容签到：如果已启用并且安全存储里有密码，则无需弹窗
    final savedUsername = LocalStorageService.instance.getUsername() ?? "";
    final biometricEnabled = LocalStorageService.instance.getBiometricCheckInEnabled();
    if (biometricEnabled && savedUsername.isNotEmpty) {
      try {
        final storedPwd = await _secureStorage.read(key: _pwdKey(savedUsername));
        if (storedPwd != null && storedPwd.isNotEmpty) {
          final ok = await _authenticateForCheckIn();
          if (ok) {
            isCheckingIn.value = true;
            try {
              final login = await Api.loginAppWenku8(username: savedUsername, password: storedPwd);
              if (login is Error) {
                _showAdaptiveSnackBar("登录失败，请稍后重试");
                return;
              }
              final r = await Api.sign();
              if (r is Success<String>) {
                final resp = (r.data ?? "").toString();
                if (_handleRelayResp(resp)) return;
              }

              // relay 不稳定时，尝试使用网页登录态进行签到
              _showAdaptiveSnackBar("relay 签到失败，尝试网页签到…");
              await _fallbackWebCheckIn();
              return;
            } finally {
              isCheckingIn.value = false;
            }
          }
        }
      } catch (_) {
        // ignore, fallback to dialog
      }
    }

    final input = await _showCheckInDialog();
    if (input == null) return;

    final username = input.username.trim();
    final password = input.password; // A2：不保存密码

    if (username.isEmpty || password.isEmpty) {
      _showAdaptiveSnackBar("请输入用户名和密码");
      return;
    }

    // 记住用户名
    if (input.rememberUsername) {
      LocalStorageService.instance.setUsername(username);
    } else {
      LocalStorageService.instance.setUsername("");
    }

    // 指纹签到开关（方法1）：密码仅保存到系统安全存储
    if (input.enableBiometric) {
      final ok = await _authenticateForCheckIn();
      if (!ok) {
        _showAdaptiveSnackBar("未通过生物识别验证，已取消启用指纹签到");
        LocalStorageService.instance.setBiometricCheckInEnabled(false);
      } else {
        await _secureStorage.write(key: _pwdKey(username), value: password);
        LocalStorageService.instance.setBiometricCheckInEnabled(true);
      }
    } else {
      LocalStorageService.instance.setBiometricCheckInEnabled(false);
      try { await _secureStorage.delete(key: _pwdKey(username)); } catch (_) {}
    }

    isCheckingIn.value = true;
    try {
      // 1) relay 登录
      final login = await Api.loginAppWenku8(username: username, password: password);
      if (login is Error) {
        _showAdaptiveSnackBar("登录失败，请检查账号密码");
        return;
      }

      // 2) 签到
      final r = await Api.sign();
      if (r is Success<String>) {
        final resp = (r.data ?? "").toString();
        if (_handleRelayResp(resp)) {
          return;
        }
      }

      // relay 不稳定时，尝试使用网页登录态进行签到
      _showAdaptiveSnackBar("relay 签到失败，尝试网页签到…");
      await _fallbackWebCheckIn();
      return;
} catch (e) {
      _showAdaptiveSnackBar("签到失败，请检查网络或稍后再试");
    } finally {
      isCheckingIn.value = false;
    }
  }
}

class _CheckInInput {
  final String username;
  final String password;
  final bool rememberUsername;
  final bool enableBiometric;
  const _CheckInInput({required this.username, required this.password, required this.rememberUsername, required this.enableBiometric});
}
