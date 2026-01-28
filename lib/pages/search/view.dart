import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hikari_novel_flutter/models/page_state.dart';
import 'package:responsive_grid_list/responsive_grid_list.dart';

import '../../service/db_service.dart';
import '../../widgets/novel_cover_card.dart';
import 'controller.dart' as c;

class SearchPage extends StatelessWidget {
  final String? author;
  late final c.SearchController controller;

  SearchPage({super.key, required this.author}) {
    controller = Get.put(c.SearchController(author: author));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: NestedScrollView(
        headerSliverBuilder:
            (context, innerBoxIsScrolled) => [
              SliverAppBar(
                pinned: true,
                expandedHeight: 300,
                title: Text("搜索"),
                titleSpacing: 0,
                flexibleSpace: FlexibleSpaceBar(
                  background: SafeArea(
                    bottom: false,
                    left: false,
                    right: false,
                    child: Padding(
                      padding: EdgeInsets.only(top: kToolbarHeight),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: TextField(
                              controller: controller.keywordController,
                              textInputAction: TextInputAction.search,
                              decoration: InputDecoration(
                                hintText: "关键词",
                                border: OutlineInputBorder(),
                                suffixIcon: IconButton(icon: const Icon(Icons.clear), onPressed: controller.keywordController.clear),
                              ),
                              onSubmitted: (_) {
                                controller.getPage(false);
                              },
                            ),
                          ),
                          SizedBox(height: 10),
                          Padding(padding: EdgeInsets.fromLTRB(20, 0, 0, 2), child: Text("搜索方式", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
                          Padding(
                            padding: const EdgeInsets.only(left: 20),
                            child: Obx(
                              () => Row(
                                children: [
                                  ChoiceChip(
                                    label: Text("按标题名称搜索", style: TextStyle(fontSize: 13)),
                                    selected: controller.searchMode.value == 0,
                                    onSelected: (_) {
                                      controller.searchMode.value = 0;
                                    },
                                  ),
                                  SizedBox(width: 10),
                                  ChoiceChip(
                                    label: Text("按作者名称搜索", style: TextStyle(fontSize: 13)),
                                    selected: controller.searchMode.value == 1,
                                    onSelected: (_) {
                                      controller.searchMode.value = 1;
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                          SizedBox(height: 10),
                          Padding(padding: EdgeInsets.only(left: 20), child: Text("搜索历史", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Obx(
                              () => Row(
                                children: [
                                  Expanded(
                                    child: SizedBox(
                                      height: 50,
                                      child: ListView.separated(
                                        scrollDirection: Axis.horizontal,
                                        itemCount: controller.searchHistory.length,
                                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                                        itemBuilder: (context, index) {
                                          return ActionChip(
                                            label: Text(controller.searchHistory[index], style: TextStyle(fontSize: 13)),
                                onPressed: () => controller.searchFromHistory(controller.searchHistory[index]),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                  IconButton(icon: Icon(Icons.delete_outline), tooltip: "清除所有历史记录", onPressed: () => DBService.instance.deleteAllSearchHistory()),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
        body: ColoredBox(color: Theme.of(context).colorScheme.surface, child: Stack(
          children: [
            Obx(() => Offstage(
              offstage: controller.pageState.value != PageState.success,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: EasyRefresh(
                  onRefresh: () => controller.getPage(false),
                  onLoad: () => controller.getPage(true),
                  child: Padding(
                    padding: EdgeInsets.zero,
                    child: ResponsiveGridList(
                      minItemWidth: 100,
                      horizontalGridSpacing: 4,
                      verticalGridSpacing: 4,
                      children:
                      controller.data.map((item) {
                        return NovelCoverCard(novelCover: item);
                      }).toList(),
                    ),
                  ),
                ),
              ),
            )),
            Obx(() => Offstage(offstage: controller.pageState.value != PageState.loading, child: Center(child: CircularProgressIndicator()))),
Obx(() => Offstage(
  offstage: controller.pageState.value != PageState.inFiveSecond,
  child: Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text("点那么快爬虫呢，这不是bug等5秒", textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Obx(() {
          final sec = controller.cooldownSeconds.value;
          final kw = controller.pendingKeyword.value;
          if (kw.isNotEmpty) {
            return Text("请稍后 ${sec}s，将自动搜索：$kw", textAlign: TextAlign.center);
          }
          return Text("请稍后 ${sec}s", textAlign: TextAlign.center);
        }),
        const SizedBox(height: 12),
        Obx(() => ElevatedButton(
          onPressed: () => controller.getPage(false),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            disabledForegroundColor: Colors.transparent,
            elevation: 0,
          ),
          child: const Text("重试", style: TextStyle(color: Colors.transparent)),
        )),
      ],
    ),
  ),
)),
            Obx(() => Offstage(offstage: controller.pageState.value != PageState.empty, child: Center(child: Text("搜索内容为空")))),
            Obx(() => Offstage(offstage: controller.pageState.value != PageState.error, child: Center(child: Text(controller.errorMsg)))),
            Obx(() => Offstage(offstage: controller.pageState.value != PageState.jumpToOtherPage, child: Center(child: Text("已跳转至另一页面")))),
          ],
        ))
      ),
    );
  }
}