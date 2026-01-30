import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class PiperModelInfo {
  final String dirPath;
  final String onnxPath;
  final String configPath;

  PiperModelInfo({
    required this.dirPath,
    required this.onnxPath,
    required this.configPath,
  });
}

class PiperModelCheck {
  final bool ok;
  final String message;
  final PiperModelInfo? model;

  const PiperModelCheck({required this.ok, required this.message, this.model});
}

/// Piper 模型管理：
/// - Piper 通常需要：model.onnx + model.onnx.json（或 model.json）
/// - 这里支持用户导入到应用私有目录，避免依赖 HuggingFace 下载。
class PiperModelManager {
  static Future<PiperModelCheck> checkModelDir(String dirPath) async {
    try {
      final d = Directory(dirPath);
      if (!await d.exists()) {
        return const PiperModelCheck(ok: false, message: '目录不存在');
      }

      final files = d
          .listSync(recursive: false)
          .whereType<File>()
          .map((f) => f.path)
          .toList();

      final onnx = files.where((x) => x.toLowerCase().endsWith('.onnx')).toList();
      if (onnx.isEmpty) {
        return const PiperModelCheck(ok: false, message: '缺少 *.onnx');
      }
      // 优先取第一个
      final onnxPath = onnx.first;

      final base = p.basename(onnxPath);
      final cfg1 = p.join(dirPath, '$base.json'); // xxx.onnx.json
      final cfg2 = p.join(dirPath, '${p.basenameWithoutExtension(onnxPath)}.json'); // xxx.json

      String? configPath;
      if (File(cfg1).existsSync()) configPath = cfg1;
      if (configPath == null && File(cfg2).existsSync()) configPath = cfg2;

      if (configPath == null) {
        // 兜底：目录里找第一个 json
        final jsons = files.where((x) => x.toLowerCase().endsWith('.json')).toList();
        if (jsons.isNotEmpty) configPath = jsons.first;
      }

      if (configPath == null) {
        return const PiperModelCheck(ok: false, message: '缺少配置文件 *.json / *.onnx.json');
      }

      return PiperModelCheck(
        ok: true,
        message: 'OK',
        model: PiperModelInfo(dirPath: dirPath, onnxPath: onnxPath, configPath: configPath),
      );
    } catch (e) {
      return PiperModelCheck(ok: false, message: '$e');
    }
  }

  /// 将用户选择的 onnx + json 复制到应用私有目录：
  /// <appSupport>/tts_models/piper/<name>/
  /// 返回导入后的目录。
  static Future<Directory> importModelFiles({
    required String onnxPath,
    required String configPath,
    String? name,
  }) async {
    final support = await getApplicationSupportDirectory();
    final baseDir = Directory(p.join(support.path, 'tts_models', 'piper'));
    if (!baseDir.existsSync()) baseDir.createSync(recursive: true);

    final n = (name != null && name.trim().isNotEmpty)
        ? name.trim()
        : p.basenameWithoutExtension(onnxPath);

    final dst = Directory(p.join(baseDir.path, n));
    if (dst.existsSync()) {
      // 避免覆盖：加时间戳
      final ts = DateTime.now().millisecondsSinceEpoch;
      return await importModelFiles(onnxPath: onnxPath, configPath: configPath, name: '${n}_$ts');
    }
    dst.createSync(recursive: true);

    await File(onnxPath).copy(p.join(dst.path, p.basename(onnxPath)));
    await File(configPath).copy(p.join(dst.path, p.basename(configPath)));
    return dst;
  }
}
