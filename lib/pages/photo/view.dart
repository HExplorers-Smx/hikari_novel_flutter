import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hikari_novel_flutter/pages/photo/controller.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

import '../../network/request.dart';

class PhotoPage extends StatelessWidget {
  PhotoPage({super.key});

  final controller = Get.put(PhotoController());

  final RxInt currentIndex = 0.obs;

  @override
  Widget build(BuildContext context) {
    void showActions(String url) {
      Get.bottomSheet(
        SafeArea(
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Container(height: 4, width: 42, decoration: BoxDecoration(color: Theme.of(context).dividerColor, borderRadius: BorderRadius.circular(99))),
                ListTile(
                  leading: const Icon(Icons.download_rounded),
                  title: const Text('保存图片到相册'),
                  onTap: () async {
                    Get.back();
                    await controller.saveImage(url);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.close_rounded),
                  title: const Text('取消'),
                  onTap: Get.back,
                ),
              ],
            ),
          ),
        ),
      );
    }
    // ✅ 需求：上下滑 / 左右滑都要保留
    // - 左右滑：交给 PhotoViewGallery（PageView）原生处理
    // - 上下滑：监听“垂直甩动”，手动切换到上一张/下一张

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton.filledTonal(onPressed: Get.back, icon: Icon(Icons.close, size: 30, color: Theme.of(context).colorScheme.primary)),
      ),
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      body:
          Get.arguments["gallery_mode"]
              ? Stack(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragEnd: (details) {
                      final v = details.primaryVelocity ?? 0;
                      // 速度太小认为是普通拖动/误触
                      if (v.abs() < 600) return;

                      final total = (Get.arguments["list"] as List).length;
                      final idx = currentIndex.value;

                      // 往上甩（v < 0）=> 下一张；往下甩（v > 0）=> 上一张
                      int target = idx;
                      if (v < 0 && idx < total - 1) {
                        target = idx + 1;
                      } else if (v > 0 && idx > 0) {
                        target = idx - 1;
                      }
                      if (target != idx) {
                        controller.pageController.animateToPage(
                          target,
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOut,
                        );
                      }
                    },
                    onLongPress: () {
                      final idx = currentIndex.value;
                      final url = Get.arguments["list"][idx];
                      showActions(url);
                    },
                    child: PhotoViewGallery.builder(
                    scrollDirection: Axis.horizontal,
                    scrollPhysics: const BouncingScrollPhysics(),
                    itemCount: Get.arguments["list"].length,
                    builder: (_, index) {
                      return PhotoViewGalleryPageOptions(imageProvider: CachedNetworkImageProvider(Get.arguments["list"][index], headers: Request.userAgent));
                    },
                    loadingBuilder:
                        (context, progress) => Center(
                          child: Center(
                            child: CircularProgressIndicator(
                              value: progress == null ? null : progress.cumulativeBytesLoaded / (progress.expectedTotalBytes?.toInt() ?? 0),
                            ),
                          ),
                        ),
                    pageController: controller.pageController,
                    onPageChanged: (index) {
                      currentIndex.value = index;
                      controller.currentIndex.value = index;
                    },
                    ),
                  ),
                  Positioned.fill(
                    child: Container(
                      alignment: Alignment.bottomCenter,
                      padding: const EdgeInsets.all(20.0),
                      child: Obx(
                        () => Text(
                          "${currentIndex.value + 1} / ${Get.arguments["list"].length}",
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            shadows: [
                              Shadow(
                                color: Colors.black.withValues(alpha: 0.6), //阴影颜色
                                offset: Offset(1, 1), //阴影偏移量
                                blurRadius: 6, //模糊程度
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              )
              : GestureDetector(
                onLongPress: () => showActions(Get.arguments["url"]),
                child: PhotoView(
                imageProvider: CachedNetworkImageProvider(Get.arguments["url"], headers: Request.userAgent),
                loadingBuilder:
                    (context, progress) => Center(
                      child: Center(
                        child: CircularProgressIndicator(
                          value: progress == null ? null : progress.cumulativeBytesLoaded / (progress.expectedTotalBytes?.toInt() ?? 0),
                        ),
                      ),
                    ),
                ),
              ),
    );
  }
}

