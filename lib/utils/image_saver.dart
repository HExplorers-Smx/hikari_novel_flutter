import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';

import '../network/image_url_helper.dart';

/// 下载网络图片并保存到系统相册（Android 原生 MediaStore / iOS Photos）
///
/// 权限说明：
/// - Android 10+（API 29+）：通过 MediaStore 写入相册通常**不需要**存储权限
/// - Android 9 及以下（API <=28）：需要申请 WRITE/READ 外部存储权限（Permission.storage）
/// - iOS：需要 Photos 权限描述（Info.plist）
class ImageSaver {
  static const MethodChannel _channel = MethodChannel('hikari/image_saver');

  static Future<(bool ok, String message)> saveNetworkImage({
    required String url,
    Map<String, dynamic>? headers,
    String? name,
  }) async {
    final permissionOk = await _ensurePermissionIfNeeded();
    if (!permissionOk) {
      return (false, '没有相册/存储权限');
    }

    final dio = Dio();
    final primaryUrl = ImageUrlHelper.normalize(url);
    final fallbackUrl = ImageUrlHelper.fallback(url);

    Future<List<int>?> _download(String u) async {
      final resp = await dio.get<List<int>>(
        u,
        options: Options(
          responseType: ResponseType.bytes,
          headers: headers,
          followRedirects: true,
          receiveTimeout: const Duration(seconds: 30),
          sendTimeout: const Duration(seconds: 30),
        ),
      );
      return resp.data;
    }

    try {
      // 先尝试原链接（避免把可用域名强制换掉导致在线加载失败）
      var bytes = await _download(primaryUrl);

      // 若失败/为空，再尝试备用链接（针对 DNS 失败等情况）
      if ((bytes == null || bytes.isEmpty) && fallbackUrl != primaryUrl) {
        bytes = await _download(fallbackUrl);
      }

      if (bytes == null || bytes.isEmpty) {
        return (false, '下载失败：图片数据为空');
      }

      final fileName = name ?? 'hikari_${DateTime.now().millisecondsSinceEpoch}';
      final ok = await _channel.invokeMethod<bool>('saveImage', <String, dynamic>{
        'bytes': Uint8List.fromList(bytes),
        'name': fileName,
      });

      if (ok == true) return (true, '已保存到相册');
      return (false, '保存失败');
    } on DioException catch (e) {
      // 如果 primary 是 DNS/网络错误，也尝试 fallback
      if (fallbackUrl != primaryUrl) {
        try {
          final bytes = await _download(fallbackUrl);
          if (bytes != null && bytes.isNotEmpty) {
            final fileName = name ?? 'hikari_${DateTime.now().millisecondsSinceEpoch}';
            final ok = await _channel.invokeMethod<bool>('saveImage', <String, dynamic>{
              'bytes': Uint8List.fromList(bytes),
              'name': fileName,
            });
            if (ok == true) return (true, '已保存到相册');
          }
        } catch (_) {}
      }
      return (false, '保存失败：$e');
    } catch (e) {
      return (false, '保存失败：$e');
    }
  }

  static Future<bool> _ensurePermissionIfNeeded() async {
    try {
      if (Platform.isAndroid) {
        final info = await DeviceInfoPlugin().androidInfo;
        final sdk = info.version.sdkInt ?? 0;
        // Android 10+ 一般不需要存储权限
        if (sdk >= 29) return true;

        final storage = await Permission.storage.request();
        return storage.isGranted || storage.isLimited;
      }

      if (Platform.isIOS) {
        // iOS 保存需要 Photos 权限（Add Only / Photos）
        final photos = await Permission.photosAddOnly.request();
        if (photos.isGranted || photos.isLimited) return true;

        final photos2 = await Permission.photos.request();
        return photos2.isGranted || photos2.isLimited;
      }

      // 其他平台先放行
      return true;
    } catch (_) {
      // 异常情况下尽量放行，避免 ROM/权限适配导致保存入口“必失败”
      return true;
    }
  }
}
