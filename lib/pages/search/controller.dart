import 'dart:async';

import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hikari_novel_flutter/models/novel_cover.dart';
import 'package:hikari_novel_flutter/models/page_state.dart';
import 'package:hikari_novel_flutter/models/resource.dart';
import 'package:hikari_novel_flutter/network/parser.dart';

import '../../common/database/database.dart';
import '../../network/api.dart';
import '../../service/db_service.dart';

class SearchController extends GetxController {
  SearchController({required this.author});

  final String? author;

  final keywordController = TextEditingController();

  RxInt searchMode = 0.obs;
  RxList<String> searchHistory = RxList();

  Rx<PageState> pageState = Rx(PageState.pleaseSelect);

  /// 站点会在短时间内频繁搜索时返回“出现错误！”页面。
  /// 这里做一个简单的冷却，避免用户连续点搜索历史导致看起来“没反应”。
  RxInt cooldownSeconds = 0.obs;
  Timer? _cooldownTimer;

  /// 冷却期间用户最后一次点的关键词（用于自动排队搜索）
  RxString pendingKeyword = ''.obs;
  int? _pendingSearchMode;

  String errorMsg = "";

  int _maxNum = 1;
  int _index = 0;
  final RxList<NovelCover> data = RxList();

  @override
  void onReady() {
    super.onReady();

    DBService.instance.getAllSearchHistory().listen((sh) {
      searchHistory.assignAll(sh.reversed.map((e) => e.keyword));
    });

    checkIsAuthorSearch(author);
  }

  void checkIsAuthorSearch(String? author) {
    if (author != null) {
      keywordController.text = author;
      searchMode.value = 1;
      getPage(false);
    }
  }

  /// 点击“搜索历史”后直接触发搜索
  void searchFromHistory(String keyword) {
    keywordController.text = keyword;
    keywordController.selection = TextSelection.fromPosition(
      TextPosition(offset: keywordController.text.length),
    );
    // 直接执行搜索
    getPage(false);
    // 顺便收起键盘
    Get.focusScope?.unfocus();
  }

void _startCooldown() {
  // 站点提示：两次搜索间隔不得少于 5 秒
  _cooldownTimer?.cancel();
  cooldownSeconds.value = 5;
  _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
    if (cooldownSeconds.value <= 1) {
      timer.cancel();
      cooldownSeconds.value = 0;

      // 冷却结束：恢复显示状态
      if (pageState.value == PageState.inFiveSecond) {
        pageState.value = data.isNotEmpty ? PageState.success : PageState.pleaseSelect;
      }

      // 冷却结束后：如果用户在冷却期点了新的搜索历史，自动执行“最后一次”
      final kw = pendingKeyword.value;
      final mode = _pendingSearchMode;
      if (kw.isNotEmpty) {
        pendingKeyword.value = '';
        _pendingSearchMode = null;

        // 恢复当时的模式（标题/作者）
        if (mode != null) searchMode.value = mode;
        keywordController.text = kw;
        keywordController.selection = TextSelection.fromPosition(
          TextPosition(offset: keywordController.text.length),
        );

        // 自动搜索最后一次点击的关键词
        getPage(false);
      }
    } else {
      cooldownSeconds.value -= 1;
    }
  });
}


  Future<IndicatorResult> getPage(bool loadMore) async {
// 冷却中：不再重复发请求；把“最后一次点击的关键词”排队，冷却结束后自动搜索
if (!loadMore && cooldownSeconds.value > 0) {
  pendingKeyword.value = keywordController.text;
  _pendingSearchMode = searchMode.value;

  Get.rawSnackbar(
    title: "提示",
    message: "点那么快爬虫呢，这不是bug等5秒",
    snackPosition: SnackPosition.BOTTOM,
    duration: const Duration(milliseconds: 900),
    animationDuration: const Duration(milliseconds: 120),
  );
  return IndicatorResult.fail;
}
    if (!loadMore) pageState.value = PageState.loading;

    if (!loadMore) {
      // 新的搜索开始，清空排队提示
      pendingKeyword.value = '';
      _pendingSearchMode = null;

      DBService.instance.upsertSearchHistory(SearchHistoryEntityData(keyword: keywordController.text));

      data.clear();
      _index = 0;
    }
    if (_index >= _maxNum) {
      return IndicatorResult.noMore;
    }
    _index += 1;

    Resource result;
    if (searchMode.value == 0) {
      result = await Api.searchNovelByTitle(title: keywordController.text, index: _index);
    } else {
      result = await Api.searchNovelByAuthor(author: keywordController.text, index: _index);
    }

    switch (result) {
      case Success():
        {
          final html = result.data;
          if (Parser.isError(html)) {
            if (!loadMore) {
              // 搜索过快：进入冷却，但不显示遮罩层、不切换页面状态（保持可操作）
              // 排队一次“最后的关键词”，冷却结束后自动重试
              pendingKeyword.value = keywordController.text;
              _pendingSearchMode = searchMode.value;

              pageState.value = data.isNotEmpty ? PageState.success : PageState.pleaseSelect;
              _startCooldown();

              Get.rawSnackbar(
                title: "提示",
                message: "点那么快爬虫呢，这不是bug等5秒",
                snackPosition: SnackPosition.BOTTOM,
                duration: const Duration(milliseconds: 900),
                animationDuration: const Duration(milliseconds: 120),
              );
            } else {
              Get.dialog(
                AlertDialog(
                  title: Text("warning".tr),
                  content: Text("search_too_quickly_tip".tr),
                  actions: [TextButton(onPressed: Get.back, child: Text("confirm".tr))],
                ),
              );
            }

            return IndicatorResult.fail;
          }

          // 站点在“只有 1 条搜索结果”时会返回一个特殊页面。
          // 以前这里会自动跳转到详情页，但体验上会让用户
          // （尤其是从“搜索历史”点进来时）无法先看到结果列表。
          // 现在统一改为：即使只有 1 本，也先展示搜索结果列表，
          // 让用户自己点一下再进入详情。
          var tempResult = Parser.isSearchResultOnlyOne(html);
          if (tempResult != null) {
            data.add(tempResult);
            _maxNum = 1;
            if (!loadMore) pageState.value = PageState.success;
            return IndicatorResult.noMore;
          }
          if (!loadMore) _maxNum = Parser.getMaxNum(html);

          final parsedHtml = Parser.parseToList(html);

          if (parsedHtml.isEmpty) {
            pageState.value = PageState.empty;
            return IndicatorResult.noMore;
          }

          data.addAll(parsedHtml);
          if (!loadMore) pageState.value = PageState.success;
          return IndicatorResult.success;
        }
      case Error():
        {
          if (!loadMore) {
            errorMsg = result.error;
            pageState.value = PageState.error;
          } else {
            Get.dialog(
              AlertDialog(
                title: Text("error".tr),
                content: Text(result.error.toString()),
                actions: [TextButton(onPressed: () => Get.back(), child: Text("confirm".tr))],
              ),
            );
          }
          if (_index > 0) {
            _index -= 1;
          }
          return IndicatorResult.fail;
        }
    }
  }
@override
void onClose() {
  _cooldownTimer?.cancel();
  keywordController.dispose();
  super.onClose();
}
}