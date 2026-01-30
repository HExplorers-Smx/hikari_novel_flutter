enum SpeakerRole { narrator, female, male }

/// 用户可维护的“角色列表”映射：
/// - 识别形如： 角色名：台词 / 角色名: 台词
/// - 或段落开头的【旁白】【女声】【男声】强制标注
///
/// 说明：
/// - 规则识别是“尽力而为”，识别不到就退化为旁白；不会导致听书卡死。
class RoleClassifier {
  /// 识别段落，并返回：角色、文本（去掉前缀）、可选 voiceOverride（如果映射里指定了）
  static (SpeakerRole role, String text, String? voiceOverride) classifyParagraph(
    String p, {
    List<dynamic> mappings = const [],
  }) {
    final s = p.trim();
    if (s.isEmpty) return (SpeakerRole.narrator, "", null);

    // 1) 强制标注：【旁白】/【女声】/【男声】
    final tagMatch = RegExp(r"^【(旁白|女声|男声)】\s*(.*)$").firstMatch(s);
    if (tagMatch != null) {
      final tag = tagMatch.group(1)!;
      final content = (tagMatch.group(2) ?? "").trim();
      return switch (tag) {
        "女声" => (SpeakerRole.female, content, null),
        "男声" => (SpeakerRole.male, content, null),
        _ => (SpeakerRole.narrator, content, null),
      };
    }

    // 2) 角色名：台词（从用户列表里匹配）
    // 支持中文冒号/英文冒号
    final prefixMatch = RegExp(r"^(.{1,20})(：|:)\s*(.+)$").firstMatch(s);
    if (prefixMatch != null) {
      final name = (prefixMatch.group(1) ?? "").trim();
      final content = (prefixMatch.group(3) ?? "").trim();

      for (final m in mappings) {
        if (m is! Map) continue;
        final mName = (m['name'] ?? '').toString().trim();
        if (mName.isEmpty) continue;
        if (name == mName) {
          final roleStr = (m['role'] ?? 'narrator').toString();
          final role = SpeakerRole.values.firstWhere(
            (e) => e.name == roleStr,
            orElse: () => SpeakerRole.narrator,
          );
          final voice = (m['voiceOverride'] ?? '').toString().trim();
          return (role, content, voice.isEmpty ? null : voice);
        }
      }
    }

    // 3) 简单性别线索（可选）：他说/她说
    // 仅作为兜底：避免大量对话都被当成旁白
    final head = s.length > 40 ? s.substring(0, 40) : s;
    if (head.contains("她说") || head.contains("她轻声") || head.contains("她低声")) {
      return (SpeakerRole.female, s, null);
    }
    if (head.contains("他说") || head.contains("他沉声") || head.contains("他低声")) {
      return (SpeakerRole.male, s, null);
    }

    return (SpeakerRole.narrator, s, null);
  }
}

class SpeakerSpan {
  SpeakerSpan(this.role, this.text, {this.voiceOverride});
  final SpeakerRole role;
  final String text;
  final String? voiceOverride;
}

/// 把段落合并成按角色的 span，并做 350 字切片（每次合成 <=350）。
class StreamingChunker {
  StreamingChunker({
    required List<String> paragraphs,
    this.maxChars = 350,
    this.roleVoiceMappingsJson = const [],
  }) : _spans = _mergeSpans(paragraphs, roleVoiceMappingsJson);

  final int maxChars;
  final List<dynamic> roleVoiceMappingsJson;

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
      return SpeakerSpan(span.role, part, voiceOverride: span.voiceOverride);
    }
    return null;
  }

  static List<SpeakerSpan> _mergeSpans(List<String> paragraphs, List<dynamic> mappingsJson) {
    final spans = <SpeakerSpan>[];
    for (final p in paragraphs) {
      final (role, text, voiceOverride) = RoleClassifier.classifyParagraph(p, mappings: mappingsJson);
      if (text.trim().isEmpty) continue;

      // 只有当 role + voiceOverride 都一致时才合并，保证“角色音色”切换不会被合并掉
      if (spans.isNotEmpty &&
          spans.last.role == role &&
          spans.last.voiceOverride == voiceOverride) {
        spans[spans.length - 1] =
            SpeakerSpan(role, "${spans.last.text}\n$text", voiceOverride: voiceOverride);
      } else {
        spans.add(SpeakerSpan(role, text, voiceOverride: voiceOverride));
      }
    }
    return spans;
  }
}
