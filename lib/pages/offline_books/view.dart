import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hikari_novel_flutter/network/request.dart';
import 'controller.dart';
import '../../router/app_sub_router.dart';

class OfflineBooksPage extends StatelessWidget {
  OfflineBooksPage({super.key});

  final controller = Get.put(OfflineBooksController());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("offline_books".tr),
        titleSpacing: 0,
        actions: [
          IconButton(
            tooltip: "refresh".tr,
            onPressed: controller.refreshList,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Obx(() {
        if (controller.loading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        if (controller.errorMsg.value.isNotEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(controller.errorMsg.value),
            ),
          );
        }
        if (controller.items.isEmpty) {
          return Center(child: Text("no_offline_books".tr));
        }

        return ListView.separated(
          itemCount: controller.items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 4),
          itemBuilder: (ctx, idx) {
            final item = controller.items[idx];
            final subtitle = "${"cached_chapters".tr}: ${item.chapterCount} · ${controller.formatBytes(item.totalBytes)}";
            return Card.filled(
              child: ListTile(
                leading: _buildCover(item.imgUrl),
                title: Text(item.title ?? ("ID: ${item.aid}"), maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                onTap: () => AppSubRouter.toNovelDetail(aid: item.aid),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == "delete") {
                      final ok = await _confirmDelete(ctx, item.title ?? item.aid);
                      if (ok == true) await controller.deleteNovelCache(item.aid);
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem<String>(
                      value: "delete",
                      child: Row(
                        children: [
                          const Icon(Icons.delete_outline),
                          const SizedBox(width: 8),
                          Text("delete_cache".tr),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      }),
    );
  }

  Widget _buildCover(String? url) {
    if (url == null || url.isEmpty) {
      return const SizedBox(width: 48, height: 64, child: Icon(Icons.menu_book_outlined));
    }
    return SizedBox(
      width: 48,
      height: 64,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: url,
          httpHeaders: Request.userAgent,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) => const Icon(Icons.menu_book_outlined),
        ),
      ),
    );
  }

    Future<bool?> _confirmDelete(BuildContext context, String name) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => AlertDialog(
        title: Text("delete_cache".tr),
        content: Text("${"delete_cache_confirm".tr}\n$name"),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text("cancel".tr),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text("confirm".tr),
          ),
        ],
      ),
    );
  }
}
