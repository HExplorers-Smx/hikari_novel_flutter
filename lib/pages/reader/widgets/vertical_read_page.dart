import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../router/route_path.dart';
import '../../../network/request.dart';

class VerticalReadPage extends StatefulWidget {
  final String text;
  final List<String> images;
  final int initPosition;
  final EdgeInsets padding;
  final TextStyle style;
  final ScrollController controller;
  final Function(double position, double max) onScroll;

  const VerticalReadPage(this.text, this.images,
      {required this.initPosition,
      required this.padding,
      required this.style,
      required this.controller,
      required this.onScroll,
      super.key});

  @override
  State<StatefulWidget> createState() => _VerticalReadPageState();
}

class _VerticalReadPageState extends State<VerticalReadPage> with WidgetsBindingObserver {
  String text = "";
  List<String> images = [];

  TextStyle textStyle = const TextStyle();
  EdgeInsets padding = EdgeInsets.zero;

  double position = 0;

  late String _lastLayoutSig;

  // Paragraph virtualization: avoid laying out a single giant Text.
  List<String> _paragraphs = const [];

  // Throttle scroll progress reporting to avoid rebuilding heavy UI too frequently.
  Timer? _scrollTimer;
  double _pendingPixels = 0;
  double _pendingMax = 0;

  @override
  void initState() {
    super.initState();
    position = widget.initPosition.toDouble();
    _lastLayoutSig = _layoutSignature();
    WidgetsBinding.instance.addObserver(this);
    resetPage();
  }

  @override
  void dispose() {
    _scrollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _scheduleOnScroll(double pixels, double max) {
    _pendingPixels = pixels;
    _pendingMax = max;
    if (_scrollTimer != null) return;
    // 80ms throttle gives a smooth progress update while keeping scroll buttery.
    _scrollTimer = Timer(const Duration(milliseconds: 80), () {
      _scrollTimer = null;
      widget.onScroll(_pendingPixels, _pendingMax);
    });
  }

  List<String> _splitParagraphs(String raw) {
    // Normalize newlines and split. Keep short empty lines out.
    final t = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final parts = t.split(RegExp(r'\n+'));
    final out = <String>[];
    for (final p in parts) {
      final s = p.trim();
      if (s.isNotEmpty) out.add(s);
    }
    // If everything got trimmed away, keep original to avoid blank page.
    return out.isEmpty ? [raw] : out;
  }

  void resetPage() {
    text = widget.text;
    textStyle = widget.style;
    images = List<String>.from(widget.images); //转换为纯净的List<String>
    padding = widget.padding;

    if (text.isEmpty && images.isEmpty) {
      position = 0;
      _paragraphs = const [];
      setState(() {});
      return;
    }

    // Build paragraphs once per chapter/settings change.
    _paragraphs = _splitParagraphs(text);

    setState(() {});

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Restore scroll position after layout.
      if (widget.controller.hasClients) {
        widget.controller.jumpTo(widget.initPosition.toDouble());
        _scheduleOnScroll(widget.controller.offset, widget.controller.position.maxScrollExtent); //页面加载完成时，提醒保存进度
      }
    });
  }

  @override
  void didUpdateWidget(covariant VerticalReadPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    //这里比较排版几何参数（fontSize, textStyle）是否有变化
    //这里不能使用"widget.xxx != oldWidget.xxx"，这是在比较对象，而不是比较其中的参数。比如深浅模式切换导致页面重建，会重建TextStyle对象实例，最终误判
    final newSig = _layoutSignature();
    if (newSig != _lastLayoutSig) {
      _lastLayoutSig = newSig;
      if (widget.text != oldWidget.text && listEquals(widget.images, oldWidget.images)) {
        //判断章节是否切换
        setState(() {});
      }
      resetPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollUpdateNotification>(
      onNotification: (notification) {
        _scheduleOnScroll(notification.metrics.pixels, notification.metrics.maxScrollExtent);
        return false; // don't swallow notifications; keep scroll pipeline efficient
      },
      child: CustomScrollView(
        controller: widget.controller,
        slivers: [
          SliverPadding(
            padding: padding,
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  // Insert small spacing between paragraphs to improve readability without heavy layout.
                  if (index.isOdd) return const SizedBox(height: 10);
                  final pIndex = index ~/ 2;
                  return Text(
                    _paragraphs.isEmpty ? text : _paragraphs[pIndex],
                    textAlign: TextAlign.justify,
                    style: textStyle,
                  );
                },
                childCount: _paragraphs.isEmpty ? 1 : (_paragraphs.length * 2 - 1),
              ),
            ),
          ),
          if (images.isNotEmpty) ...[
            const SliverToBoxAdapter(child: SizedBox(height: 20)),
            SliverPadding(
              padding: padding.copyWith(top: 0),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index.isOdd) return const SizedBox(height: 20);
                    final imgIndex = index ~/ 2;
                    return GestureDetector(
                      onDoubleTap: () => Get.toNamed(
                        RoutePath.photo,
                        arguments: {"gallery_mode": true, "list": images, "index": imgIndex},
                      ),
                      onLongPress: () => Get.toNamed(
                        RoutePath.photo,
                        arguments: {"gallery_mode": true, "list": images, "index": imgIndex},
                      ),
                      child: CachedNetworkImage(
                        width: double.infinity,
                        imageUrl: images[imgIndex],
                        httpHeaders: Request.userAgent,
                        fit: BoxFit.fitWidth,
                        // Avoid per-byte progress rebuilds; keep a lightweight placeholder.
                        placeholder: (context, url) => const Center(
                          child: Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(),
                          ),
                        ),
                        errorWidget: (context, url, error) => Column(
                          children: [const Icon(Icons.error_outline), Text(error.toString())],
                        ),
                      ),
                    );
                  },
                  childCount: images.isEmpty ? 0 : (images.length * 2 - 1),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  //排版几何参数的签名
  String _layoutSignature() {
    final s = widget.style;
    final p = widget.padding;

    return [
      widget.text.length,
      widget.images.length,
      s.fontSize,
      s.height,
      s.letterSpacing,
      s.wordSpacing,
      p.left,
      p.right,
      p.top,
      p.bottom,
    ].join("|");
  }
}
