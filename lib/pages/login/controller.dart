import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:hikari_novel_flutter/main.dart';
import 'package:hikari_novel_flutter/models/common/wenku8_node.dart';
import 'package:hikari_novel_flutter/network/request.dart';
import 'package:hikari_novel_flutter/router/route_path.dart';

import '../../common/database/database.dart';
import '../../models/resource.dart';
import '../../network/api.dart';
import '../../network/parser.dart';
import '../../service/db_service.dart';
import '../../service/local_storage_service.dart';

class LoginController extends GetxController {
  RxBool showLoading = true.obs;
  RxInt loadingProgress = 0.obs;
  final CookieManager cookieManager = CookieManager.instance(webViewEnvironment: webViewEnvironment);
  InAppWebViewController? inAppWebViewController;
  final GlobalKey webViewKey = GlobalKey();
  final InAppWebViewSettings settings = InAppWebViewSettings(
    isInspectable: kDebugMode,
    userAgent: Request.userAgent[HttpHeaders.userAgentHeader],
    javaScriptEnabled: true,
  );

  String get url => "${Api.wenku8Node.node}/login.php";

  @override
  void onInit() {
    super.onInit();
    cookieManager.deleteAllCookies();
  }

  Future<void> saveCookie(InAppWebViewController webController, WebUri uri) async {
    showLoading.value = false;

    // 只要在 wenku8 域名内就尝试处理
    if (!uri.toString().contains("wenku8")) return;

    // ✅ 用根域名取 cookie 更稳
    final root = WebUri(Api.wenku8Node.node);
    final cookies = await cookieManager.getCookies(url: root);

    final hasLoginCookie =
        cookies.any((c) => c.name.contains("jieqiUserInfo")) &&
        cookies.any((c) => c.name.contains("jieqiVisitInfo"));

    if (hasLoginCookie) {
      // ✅ 保存整套 cookie（包含 PHPSESSID 等）
      final cookieHeader = cookies.map((c) => "${c.name}=${c.value}").join("; ");
      LocalStorageService.instance.setCookie(cookieHeader);

      await _getUserInfo();
      await _refreshBookshelf();
      Get.offAllNamed(RoutePath.main);
      return;
    }

    // ======= 到这里：没拿到登录态 Cookie，开始分析网页提示 =======
    final urlStr = uri.toString();
    final isLoginPage = urlStr.contains("login.php");
    if (!isLoginPage) return;

    String pageText = "";
    try {
      pageText = await webController.evaluateJavascript(
        source: "document.body ? (document.body.innerText || '') : ''",
      ) as String;
    } catch (_) {
      // ignore
    }

    final t = pageText.trim();
    String reason = "未获取到登录 Cookie";
    String detail = "可能原因：站点需要验证码/风控拦截、Cookie 没写入、网页结构变化、或登录没有真正成功。";

    if (t.isNotEmpty) {
      if (t.contains("验证码")) {
        reason = "需要验证码或安全验证";
        detail = "网页提示包含“验证码”。请在 WebView 里完成验证码后再试。";
      } else if (t.contains("密码") && (t.contains("错误") || t.contains("不正确"))) {
        reason = "密码可能被判定错误";
        detail = "网页提示包含“密码错误/不正确”。也可能是站点风控导致表单提交失败。";
      } else if (t.contains("用户名") && (t.contains("错误") || t.contains("不存在"))) {
        reason = "用户名可能被判定无效";
        detail = "网页提示包含“用户名错误/不存在”。";
      } else if (t.contains("频繁") || t.contains("过快") || t.contains("限制")) {
        reason = "登录过于频繁被限制";
        detail = "网页提示包含“频繁/限制”。建议稍等一会再试或换网络。";
      } else if (t.contains("禁止") || t.contains("封") || t.contains("黑名单")) {
        reason = "账号/环境可能被限制";
        detail = "网页提示包含“禁止/封/黑名单”等字样。";
      } else if (t.contains("成功") || t.contains("欢迎")) {
        reason = "页面显示登录成功，但 App 没拿到登录态";
        detail = "通常是 Cookie 取值不全、域名取 Cookie 不对、或缺少 PHPSESSID 等 Cookie。已建议保存整套 Cookie（本方法已做）。";
      } else {
        final snippet = t.length > 120 ? "${t.substring(0, 120)}..." : t;
        reason = "登录失败（网页返回信息）";
        detail = snippet;
      }
    }

    Get.dialog(
      AlertDialog(
        title: Text(reason),
        content: Text(detail),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: Text("confirm".tr),
          ),
        ],
      ),
    );
  }

  Future<void> _getUserInfo() async {
    final data = await Api.getUserInfo();
    switch (data) {
      case Success():
        LocalStorageService.instance.setUserInfo(Parser.getUserInfo(data.data));
      case Error():
        {
          Get.dialog(
            AlertDialog(
              title: Text("error".tr),
              content: Text(data.error.toString()),
              actions: [TextButton(onPressed: () => Get.back(), child: Text("confirm".tr))],
            ),
          );
        }
    }
  }

  Future<void> _refreshBookshelf() async {
    await DBService.instance.deleteAllBookshelf();

    final futures = Iterable.generate(6, (index) async {
      await _insertAll(index);
    });
    await Future.wait(futures);
  }

  Future<void> _insertAll(int index) async {
    final result = await Api.getBookshelf(classId: index);
    switch (result) {
      case Success():
        {
          final bookshelf = Parser.getBookshelf(result.data, index);
          if (bookshelf.list.isNotEmpty) {
            final insertData = bookshelf.list.map((e) {
              return BookshelfEntityData(aid: e.aid, bid: e.bid, url: e.url, title: e.title, img: e.img, classId: bookshelf.classId.toString());
            });
            await DBService.instance.insertAllBookshelf(insertData);
          }
        }
      case Error():
        {
          Get.dialog(
            AlertDialog(
              title: Text("error".tr),
              content: Text(result.error.toString()),
              actions: [TextButton(onPressed: () => Get.back(), child: Text("confirm".tr))],
            ),
          );
        }
    }
  }
}
