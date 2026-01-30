import '../../tts/role_classifier.dart';

class RoleVoiceMapping {
  RoleVoiceMapping({
    required this.name,
    required this.role,
    this.voiceOverride,
  });

  final String name; // 角色名，如“金次”“亚莉亚”
  final SpeakerRole role; // 旁白/女声/男声
  final String? voiceOverride; // 可选：直接指定 Azure Voice Name

  Map<String, dynamic> toJson() => {
        'name': name,
        'role': role.name,
        'voiceOverride': voiceOverride,
      };

  static RoleVoiceMapping? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final name = (raw['name'] ?? '').toString().trim();
    if (name.isEmpty) return null;

    final roleStr = (raw['role'] ?? 'narrator').toString();
    final role = SpeakerRole.values.firstWhere(
      (e) => e.name == roleStr,
      orElse: () => SpeakerRole.narrator,
    );

    final voice = (raw['voiceOverride'] ?? '').toString().trim();
    return RoleVoiceMapping(
      name: name,
      role: role,
      voiceOverride: voice.isEmpty ? null : voice,
    );
  }
}
