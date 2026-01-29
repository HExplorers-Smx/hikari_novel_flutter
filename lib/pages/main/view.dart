import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hikari_novel_flutter/common/extension.dart';
import 'package:hikari_novel_flutter/models/page_state.dart';
import 'package:hikari_novel_flutter/pages/main/controller.dart';
import 'package:hikari_novel_flutter/pages/novel_detail/controller.dart';

import '../../common/widgets.dart';
import '../../router/app_pages.dart';
import '../../router/app_sub_router.dart';
import '../../router/route_path.dart';
import '../bookshelf/controller.dart';

class MainPage extends StatelessWidget {
  MainPage({super.key});

  final controller = Get.put(MainController());

  @override
  Widget build(BuildContext context) {
    return context.isLargeScreen() ? _buildLargeScreenScaffold() : _buildSmallScreenScaffold();
  }

  Future<void> _handleRootPop() async {
    // A. 内容区（小说详情 / 图片查看 等）优先处理
    if (controller.showContent.value) {
      // 1) 小说详情多选态优先退出
      try {
        final novelDetailController = Get.find<NovelDetailController>();
        if (novelDetailController.isSelectionMode.value) {
          novelDetailController.exitSelectionMode();
          return;
        }
      } catch (_) {}

      // 2) 子 Navigator 能退就退
      final subNav = AppSubRouter.subNavigatorKey?.currentState;
      if (subNav != null && subNav.canPop()) {
        subNav.pop();
        return;
      }

      // 3) 子 Navigator 已经在根（logo）了：关闭内容区
      controller.showContent.value = false;
      return;
    }

    // B. 书架 Tab：优先处理“搜索 / 多选”返回（不依赖底部操作栏是否显示）
    // 这样在书架搜索结果页手势返回，会先回到书架内容，而不是直接切回首页。
    if (controller.selectedIndex.value == 1) {
      try {
        final bookshelfController = Get.find<BookshelfController>();
        final currentTabController = Get.find<BookshelfContentController>(
          tag: "BookshelfContentController ${bookshelfController.tabController.index}",
        );

        // 1) 先退出“书架搜索”页：这个状态在 BookshelfController 上
        if (bookshelfController.pageState.value == PageState.bookshelfSearch) {
          bookshelfController.pageState.value = PageState.bookshelfContent;
          return;
        }

        // 2) 再退出多选（兼容 bool / RxBool）
        final dynamic ism = (currentTabController as dynamic).isSelectionMode;
        final bool isSel = ism is RxBool ? ism.value : (ism == true);
        if (isSel) {
          currentTabController.exitSelectionMode();
          return;
        }
      } catch (_) {}
    }

    // C. 已在三大主 Tab（首页/书架/我的）根：返回直接退出到桌面（Android）
    // 需求：无论当前在首页/书架/我的，只要已经在各自根页面，再次返回就退出应用。
    if (Platform.isAndroid) {
      await SystemNavigator.pop();
    }
  }

  Widget _buildSmallScreenScaffold() {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _handleRootPop();
      },
      child: Stack(
        children: [
          Obx(
            () => Scaffold(
              body: IndexedStack(index: controller.selectedIndex.value, children: controller.pages),
              bottomNavigationBar: Obx(() {
                if (controller.showBookshelfBottomActionBar.value) {
                  BookshelfController bookshelfController = Get.find();
                  BookshelfContentController currentTabController = Get.find(tag: "BookshelfContentController ${bookshelfController.tabController.index}");
                  return Widgets.bookshelfBottomActionBar(currentTabController, bookshelfController, edgeToEdge: true);
                } else {
                  return NavigationBar(
                    selectedIndex: controller.selectedIndex.value,
                    onDestinationSelected: (index) => controller.selectedIndex.value = index,
                    destinations: [
                      NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: "home".tr),
                      NavigationDestination(icon: Icon(Icons.book_outlined), selectedIcon: Icon(Icons.book), label: "bookshelf".tr),
                      NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: "my".tr),
                    ],
                  );
                }
              }),
            ),
          ),
          Obx(() => Offstage(offstage: !controller.showContent.value, child: _buildContentNavigator(controller))),
        ],
      ),
    );
  }

  Widget _buildLargeScreenScaffold() {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _handleRootPop();
      },
      child: Scaffold(
        body: Row(
          children: [
            Obx(
              () => NavigationRail(
                labelType: NavigationRailLabelType.all, //显示所有标签
                destinations: [
                  NavigationRailDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: Text("home".tr)),
                  NavigationRailDestination(icon: Icon(Icons.book_outlined), selectedIcon: Icon(Icons.book), label: Text("bookshelf".tr)),
                  NavigationRailDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: Text("my".tr)),
                ],
                selectedIndex: controller.selectedIndex.value,
                onDestinationSelected: (index) => controller.selectedIndex.value = index,
              ),
            ),
            Obx(
              () => Expanded(
                flex: 1,
                child: IndexedStack(index: controller.selectedIndex.value, children: controller.pages),
              ),
            ),
            Expanded(flex: 1, child: _buildContentNavigator(controller)),
          ],
        ),
      ),
    );
  }
}

//子路由
Widget _buildContentNavigator(MainController controller) {
  return PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (didPop) return;
      // 只处理子 Navigator 自己的返回，避免 Get.back() 抢主栈
      final subNav = AppSubRouter.subNavigatorKey?.currentState;
      if (subNav != null && subNav.canPop()) {
        subNav.pop();
      }
    },
    child: ClipRect(
      child: Navigator(
        key: AppSubRouter.subNavigatorKey,
        initialRoute: RoutePath.logo,
        observers: [SubNavigatorObserver()],
        onGenerateRoute: (settings) => AppRoutes.subRoutePages(settings),
      ),
    ),
  );
}

//子路由监听
class SubNavigatorObserver extends NavigatorObserver {
  @override
  void didPush(Route route, Route? previousRoute) {
    super.didPush(route, previousRoute);
    if (previousRoute != null) {
      var routeName = route.settings.name ?? "";
      AppSubRouter.currentContentRouteName = routeName;
      Get.find<MainController>().showContent.value = routeName != RoutePath.logo;
    }
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    super.didPop(route, previousRoute);
    var routeName = previousRoute?.settings.name ?? "";
    AppSubRouter.currentContentRouteName = routeName;
    Get.find<MainController>().showContent.value = routeName != RoutePath.logo;
  }
}
