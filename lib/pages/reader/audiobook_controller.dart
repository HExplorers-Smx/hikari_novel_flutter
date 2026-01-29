import 'package:get/get.dart';

import '../../tts/audiobook_tts_service.dart';
import 'controller.dart';

/// 读书页听书控制器：不修改原有阅读逻辑，只负责把当前章节内容交给 TTS。
class ReaderAudiobookController extends GetxController {
  final tts = Get.find<AudiobookTtsService>();

  /// 你原需求是直接用 List<String> currentChapterParagraphs。
  /// 当前项目 ReaderController 里只有 text(String)，这里用 split 做等价段落。
  /// 如果你后续加了 currentChapterParagraphs 字段，直接替换这段即可。
  List<String> buildParagraphs(ReaderController reader) {
    return reader.text.value
        .split(RegExp(r"\n+"))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  Future<void> togglePlay(ReaderController reader) async {
    if (!tts.isActive.value) {
      await tts.startFromParagraphs(buildParagraphs(reader));
      return;
    }
    if (tts.isPlaying.value) {
      await tts.pause();
    } else {
      await tts.resume();
    }
  }

  Future<void> stop() => tts.stop();
}
