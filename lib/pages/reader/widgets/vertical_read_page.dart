import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../router/route_path.dart';
import '../../../network/request.dart';

sealed class _Block {
  const _Block();
}

class _TextBlock extends _Block {
  final String text;
  const _TextBlock(this.text);
}

class _ImageBlock extends _Block {
  final String url;
  final int index;
  const _ImageBlock(this.url, this.index);
}

class VerticalReadPage extends StatefulWidget {
  final String text;
  final List<String> images;
  final int initPosition;
  final EdgeInsets padding;
  final TextStyle style;
  final ScrollController controller;
  final Function(double position, double max) onScroll;

  const VerticalReadPage(
    this.text,
    this.images, {
    required this.initPosition,
    required this.padding,
    required this.style,
    required this.controller,
    required this.onScroll,
    super.key,
  });

  @override
  State<StatefulWidget> createState() => _VerticalReadPageState();
}

class _VerticalReadPageState extends State<VerticalReadPage> with WidgetsBindingObserver {
  String text = "";
  List<String> images = [];

  TextStyle textStyle = TextStyle();
  EdgeInsets padding = EdgeInsets.zero;

  double position = 0;

  late String _lastLayoutSig;

  late List<_Block> _blocks = <_Block>[];
  int _lastReportMs = 0;

  List<String> _splitTextToChunks(String text) {
    final raw = text
        .replaceAll('\r\n', '\n')
        .split(RegExp(r'\n{2,}'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    const int maxLen = 900;
    final out = <String>[];
    for (final p in raw) {
      if (p.length <= maxLen) {
        out.add(p);
      } else {
        for (int i = 0; i < p.length; i += maxLen) {
          out.add(p.substring(i, (i + maxLen).clamp(0, p.length)));
        }
      }
    }
    return out;
  }

  void _rebuildBlocks() {
    final chunks = _splitTextToChunks(text);
    final blocks = <_Block>[];
    for (final c in chunks) {
      blocks.add(_TextBlock(c));
    }
    for (int i = 0; i < images.length; i++) {
      blocks.add(_ImageBlock(images[i], i));
    }
    _blocks = blocks;
  }

@override
  void initState() {
    super.initState();
    position = widget.initPosition.toDouble();
    _lastLayoutSig = _layoutSignature();
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.controller.jumpTo(widget.initPosition.toDouble());
      widget.onScroll(widget.controller.offset, widget.controller.position.maxScrollExtent); //页面加载完成时，提醒保存进度
    });

    resetPage();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void resetPage() {
    text = widget.text;
    textStyle = widget.style;
    images = List<String>.from(widget.images); //转换为纯净的List<String>
    padding = widget.padding;
    _rebuildBlocks();
    if (text.isEmpty && images.isEmpty) {
      position = 0;
      setState(() {});
      return;
    }
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
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        final now = DateTime.now().millisecondsSinceEpoch;
        if (n is ScrollEndNotification || now - _lastReportMs > 80) {
          _lastReportMs = now;
          widget.onScroll(n.metrics.pixels, n.metrics.maxScrollExtent);
        }
        return false;
      },
      child: ListView.builder(
        controller: widget.controller,
        padding: padding,
        //允许展开
        //禁止自身滚动
        cacheExtent: 1200,
        itemCount: _blocks.length,
        itemBuilder: (_, i) {
          final b = _blocks[i];
          if (b is _TextBlock) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(b.text, textAlign: TextAlign.justify, style: textStyle),
            );
          }
          if (b is _ImageBlock) {
            return Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 20),
              child: GestureDetector(
                onDoubleTap: () => Get.toNamed(RoutePath.photo, arguments: {"gallery_mode": true, "list": images, "index": b.index}),
                onLongPress: () => Get.toNamed(RoutePath.photo, arguments: {"gallery_mode": true, "list": images, "index": b.index}),
                child: CachedNetworkImage(
                  width: double.infinity,
                  imageUrl: b.url,
                  httpHeaders: Request.userAgent,
                  fit: BoxFit.fitWidth,
                  progressIndicatorBuilder: (context, url, downloadProgress) =>
                      Center(child: CircularProgressIndicator(value: downloadProgress.progress)),
                  errorWidget: (context, url, error) => Column(children: [Icon(Icons.error_outline), Text(error.toString())]),
                ),
              ),
            );
          }
          return const SizedBox.shrink();
        },
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
      s.color?.toARGB32(),
      p.left,
      p.right,
      p.top,
      p.bottom,
    ].join("|");
  }
}
