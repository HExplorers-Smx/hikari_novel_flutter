import 'dart:io';

import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';

import '../../common/database/database.dart';
import '../../models/novel_detail.dart';
import '../../service/db_service.dart';

class OfflineNovelItem {
  final String aid;
  final String? title;
  final String? imgUrl;
  final int chapterCount;
  final int totalBytes;
  final DateTime lastModified;

  OfflineNovelItem({
    required this.aid,
    required this.title,
    required this.imgUrl,
    required this.chapterCount,
    required this.totalBytes,
    required this.lastModified,
  });
}

class OfflineBooksController extends GetxController {
  RxList<OfflineNovelItem> items = <OfflineNovelItem>[].obs;
  RxBool loading = true.obs;
  RxString errorMsg = "".obs;

  late final Directory _supportDir;

  @override
  void onReady() async {
    super.onReady();
    _supportDir = await getApplicationSupportDirectory();
    await refreshList();
  }

  Future<void> refreshList() async {
    loading.value = true;
    errorMsg.value = "";
    try {
      final cacheDir = Directory("${_supportDir.path}/cached_chapter");
      if (!await cacheDir.exists()) {
        items.clear();
        loading.value = false;
        return;
      }

      final Map<String, List<FileSystemEntity>> grouped = {};
      await for (final entity in cacheDir.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.isNotEmpty ? entity.uri.pathSegments.last : entity.path.split(Platform.pathSeparator).last;
        // expected: {aid}_{cid}.txt
        if (!name.endsWith(".txt")) continue;
        final i = name.indexOf("_");
        if (i <= 0) continue;
        final aid = name.substring(0, i);
        grouped.putIfAbsent(aid, () => []).add(entity);
      }

      final List<OfflineNovelItem> result = [];

      for (final entry in grouped.entries) {
        final aid = entry.key;
        final files = entry.value.whereType<File>().toList();

        int bytes = 0;
        DateTime last = DateTime.fromMillisecondsSinceEpoch(0);
        for (final f in files) {
          final stat = await f.stat();
          bytes += stat.size;
          if (stat.modified.isAfter(last)) last = stat.modified;
        }

        // Try to get cached novel detail (title/cover) from local DB
        String? title;
        String? imgUrl;
        final NovelDetailEntityData? nd = await DBService.instance.getNovelDetail(aid);
        if (nd != null) {
          try {
            final detail = NovelDetail.fromString(nd.json);
            title = detail.title;
            imgUrl = detail.imgUrl;
          } catch (_) {
            // ignore parsing error
          }
        }

        result.add(
          OfflineNovelItem(
            aid: aid,
            title: title,
            imgUrl: imgUrl,
            chapterCount: files.length,
            totalBytes: bytes,
            lastModified: last,
          ),
        );
      }

      // Sort by last modified desc
      result.sort((a, b) => b.lastModified.compareTo(a.lastModified));
      items.assignAll(result);
    } catch (e) {
      errorMsg.value = e.toString();
    } finally {
      loading.value = false;
    }
  }

  String formatBytes(int bytes) {
    if (bytes < 1024) return "${bytes}B";
    final kb = bytes / 1024;
    if (kb < 1024) return "${kb.toStringAsFixed(1)}KB";
    final mb = kb / 1024;
    if (mb < 1024) return "${mb.toStringAsFixed(1)}MB";
    final gb = mb / 1024;
    return "${gb.toStringAsFixed(1)}GB";
  }

  Future<void> deleteNovelCache(String aid) async {
    final cacheDir = Directory("${_supportDir.path}/cached_chapter");
    if (!await cacheDir.exists()) return;

    await for (final entity in cacheDir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.isNotEmpty ? entity.uri.pathSegments.last : entity.path.split(Platform.pathSeparator).last;
      if (!name.startsWith("${aid}_") || !name.endsWith(".txt")) continue;
      try {
        await entity.delete();
      } catch (_) {}
    }
    await refreshList();
  }
}
