import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class SherpaModelInfo {
  final String dirPath;
  final String onnxPath;
  final String tokensPath;
  final String lexiconPath;

  SherpaModelInfo({
    required this.dirPath,
    required this.onnxPath,
    required this.tokensPath,
    required this.lexiconPath,
  });
}

class SherpaModelCheckResult {
  final bool ok;
  final String message;
  final SherpaModelInfo? model;

  SherpaModelCheckResult({
    required this.ok,
    required this.message,
    required this.model,
  });
}

/// sherpa-onnx 离线模型管理器
///
/// 约定：
/// - 模型根目录固定：<AppSupport>/tts_models/sherpa_matcha_zh/
/// - 子目录名称不做任何限制（解压出来叫啥都行）
/// - 每个子目录只要包含关键文件（至少 1 个 .onnx + tokens.txt + lexicon.txt），就认为是可用模型
class SherpaModelManager {
  static const String kModelRootRelative = 'tts_models/sherpa_matcha_zh';

  /// 获取应用私有目录下的模型根目录（真实可读写路径）
  static Future<Directory> getModelRootDir() async {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, kModelRootRelative));
  }

  /// 确保模型根目录存在
  static Future<Directory> ensureModelRootDir() async {
    final root = await getModelRootDir();
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    return root;
  }

  /// 导入用户选择的模型文件夹：复制到应用私有目录下。
  ///
  /// 返回复制后的目录。
  static Future<Directory> importModelDirectory(String sourceDirPath) async {
    final src = Directory(sourceDirPath);
    if (!await src.exists()) {
      throw Exception('源目录不存在：$sourceDirPath');
    }

    final root = await ensureModelRootDir();

    final baseName = p.basename(sourceDirPath);
    final safeName = _sanitizeFolderName(baseName.isEmpty ? 'model' : baseName);
    final ts = DateTime.now().millisecondsSinceEpoch;

    final dst = Directory(p.join(root.path, '${safeName}_$ts'));
    await dst.create(recursive: true);

    await _copyDirectoryRecursive(src, dst);
    return dst;
  }

  /// 列出根目录下所有一级子目录（不限制名称）
  static Future<List<Directory>> listCandidateModelDirs() async {
    final root = await ensureModelRootDir();
    final out = <Directory>[];
    if (!await root.exists()) return out;

    await for (final ent in root.list(followLinks: false)) {
      if (ent is Directory) out.add(ent);
    }

    out.sort((a, b) => a.path.compareTo(b.path));
    return out;
  }

  /// 在模型根目录中找到第一个可用模型
  static Future<SherpaModelInfo?> findFirstValidModel() async {
    final dirs = await listCandidateModelDirs();
    for (final d in dirs) {
      final r = await checkModelDir(d.path);
      if (r.ok && r.model != null) return r.model;
    }
    return null;
  }

  /// 检查一个模型目录是否完整，并返回关键文件路径。
  ///
  /// 规则：
  /// - 至少一个 .onnx
  /// - tokens.txt 必须存在
  /// - lexicon.txt 必须存在
  static Future<SherpaModelCheckResult> checkModelDir(String dirPath) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) {
      return SherpaModelCheckResult(ok: false, message: '目录不存在', model: null);
    }

    final files = await _listFilesRecursively(dir);
    final onnx = files.where((f) => f.path.toLowerCase().endsWith('.onnx')).toList();
    if (onnx.isEmpty) {
      return SherpaModelCheckResult(ok: false, message: '缺少 .onnx 模型文件', model: null);
    }

    final tokens = File(p.join(dir.path, 'tokens.txt'));
    if (!await tokens.exists()) {
      return SherpaModelCheckResult(ok: false, message: '缺少 tokens.txt', model: null);
    }

    final lexicon = File(p.join(dir.path, 'lexicon.txt'));
    if (!await lexicon.exists()) {
      return SherpaModelCheckResult(ok: false, message: '缺少 lexicon.txt', model: null);
    }

    final onnxPath = onnx.first.path;
    final model = SherpaModelInfo(
      dirPath: dir.path,
      onnxPath: onnxPath,
      tokensPath: tokens.path,
      lexiconPath: lexicon.path,
    );

    return SherpaModelCheckResult(ok: true, message: 'OK', model: model);
  }

  /// 删除根目录下所有导入的模型（谨慎使用）
  static Future<void> deleteAllImportedModels() async {
    final root = await ensureModelRootDir();
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
    await root.create(recursive: true);
  }

  static String _sanitizeFolderName(String name) {
    final s = name.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    return s.isEmpty ? 'model' : s;
  }

  static Future<void> _copyDirectoryRecursive(Directory src, Directory dst) async {
    await for (final ent in src.list(recursive: true, followLinks: false)) {
      final rel = p.relative(ent.path, from: src.path);
      final targetPath = p.join(dst.path, rel);

      if (ent is Directory) {
        final d = Directory(targetPath);
        if (!await d.exists()) {
          await d.create(recursive: true);
        }
        continue;
      }

      if (ent is File) {
        final parent = Directory(p.dirname(targetPath));
        if (!await parent.exists()) {
          await parent.create(recursive: true);
        }
        await ent.copy(targetPath);
      }
    }
  }

  static Future<List<File>> _listFilesRecursively(Directory dir) async {
    final out = <File>[];
    await for (final ent in dir.list(recursive: true, followLinks: false)) {
      if (ent is File) out.add(ent);
    }
    out.sort((a, b) => a.path.compareTo(b.path));
    return out;
  }
}
