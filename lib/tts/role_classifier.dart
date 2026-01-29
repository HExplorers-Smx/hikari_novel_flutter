enum SpeakerRole { narrator, female, male }

/// 识别段落开头形如：
/// 【旁白】xxx / 【女声】xxx / 【男声】xxx
/// 未标注则默认旁白。
class RoleClassifier {
  static (SpeakerRole role, String text) classifyParagraph(String p) {
    final s = p.trim();
    if (s.isEmpty) return (SpeakerRole.narrator, "");
    final match = RegExp(r"^【(旁白|女声|男声)】\s*(.*)$").firstMatch(s);
    if (match == null) return (SpeakerRole.narrator, s);

    final tag = match.group(1)!;
    final content = (match.group(2) ?? "").trim();
    return switch (tag) {
      "女声" => (SpeakerRole.female, content),
      "男声" => (SpeakerRole.male, content),
      _ => (SpeakerRole.narrator, content),
    };
  }
}

class SpeakerSpan {
  SpeakerSpan(this.role, this.text);
  final SpeakerRole role;
  final String text;
}

/// 把段落合并成按角色的 span，并做 350 字切片（每次合成 <=350）。
class StreamingChunker {
  StreamingChunker({required List<String> paragraphs, this.maxChars = 350}) : _spans = _mergeSpans(paragraphs);

  final int maxChars;
  final List<SpeakerSpan> _spans;

  int _spanIndex = 0;
  int _offsetInSpan = 0;

  bool get isDone => _spanIndex >= _spans.length;

  /// 取下一段要合成的文本（同一角色），长度 <= maxChars。
  SpeakerSpan? nextUtterance() {
    while (_spanIndex < _spans.length) {
      final span = _spans[_spanIndex];
      final remain = span.text.length - _offsetInSpan;
      if (remain <= 0) {
        _spanIndex++;
        _offsetInSpan = 0;
        continue;
      }
      final take = remain > maxChars ? maxChars : remain;
      final part = span.text.substring(_offsetInSpan, _offsetInSpan + take).trim();
      _offsetInSpan += take;
      if (part.isEmpty) continue;
      return SpeakerSpan(span.role, part);
    }
    return null;
  }

  static List<SpeakerSpan> _mergeSpans(List<String> paragraphs) {
    final spans = <SpeakerSpan>[];
    for (final p in paragraphs) {
      final (role, text) = RoleClassifier.classifyParagraph(p);
      if (text.trim().isEmpty) continue;

      if (spans.isNotEmpty && spans.last.role == role) {
        spans[spans.length - 1] = SpeakerSpan(role, "${spans.last.text}\n$text");
      } else {
        spans.add(SpeakerSpan(role, text));
      }
    }
    return spans;
  }
}
