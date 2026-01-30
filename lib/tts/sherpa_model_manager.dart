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

  /// 递归扫描最大深度：避免用户误选 Download 根目录导致遍历太大
  static const int kMaxDiscoverDepth = 4;

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
    // 允许用户选择上层目录：这里会递归寻找真正的模型目录
    final check = await checkModelDir(sourceDirPath);
    if (!check.ok || check.model == null) {
      throw Exception(check.message);
    }

    final src = Directory(check.model!.dirPath);
    if (!await src.exists()) {
      throw Exception('源目录不存在：${check.model!.dirPath}');
    }

    final root = await ensureModelRootDir();

    // 目标目录命名：优先使用“真实模型目录”的文件夹名，避免用户选上层目录导致命名怪异
    final baseName = p.basename(check.model!.dirPath);
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
  /// - 允许用户选择上层目录：会在所选目录及其子目录中递归寻找真正的模型目录
  /// - 模型目录内至少一个 .onnx
  /// - tokens.txt 必须存在（同层）
  /// - lexicon.txt 必须存在（同层）
  static Future<SherpaModelCheckResult> checkModelDir(String dirPath) async {
    final root = Directory(dirPath);
    if (!await root.exists()) {
      return SherpaModelCheckResult(ok: false, message: '目录不存在：$dirPath', model: null);
    }

    // 1) 先尝试：当前目录就是模型目录（最快）
    final flat = await _checkModelDirFlat(root);
    if (flat.ok) return flat;

    // 2) 再递归向下寻找
    final found = await _discoverFirstValidModelDir(root, depth: 0);
    if (found != null) {
      return SherpaModelCheckResult(ok: true, message: 'OK', model: found);
    }

    return SherpaModelCheckResult(
      ok: false,
      message: '未在所选目录及其子目录中找到可用模型。\n请确保某一层目录内至少包含：*.onnx / tokens.txt / lexicon.txt',
      model: null,
    );
  }

  /// 仅检查“这一层目录”是否为模型目录（不递归）
  static Future<SherpaModelCheckResult> _checkModelDirFlat(Directory dir) async {
    final entities = await dir.list(followLinks: false).toList();
    final files = <File>[];
    for (final e in entities) {
      if (e is File) files.add(e);
    }

    String? onnxPath;
    for (final f in files) {
      final lower = f.path.toLowerCase();
      if (lower.endsWith('.onnx')) {
        onnxPath = f.path;
        break;
      }
    }

    if (onnxPath == null) {
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

    return SherpaModelCheckResult(
      ok: true,
      message: 'OK',
      model: SherpaModelInfo(
        dirPath: dir.path,
        onnxPath: onnxPath,
        tokensPath: tokens.path,
        lexiconPath: lexicon.path,
      ),
    );
  }

  /// 在 root 及其子目录中递归寻找第一个合法模型目录
  static Future<SherpaModelInfo?> _discoverFirstValidModelDir(
    Directory root, {
    required int depth,
  }) async {
    if (depth > kMaxDiscoverDepth) return null;

    // 跳过隐藏目录，减少无意义扫描
    final name = p.basename(root.path);
    if (name.startsWith('.')) return null;

    // 当前层尝试
    final flat = await _checkModelDirFlat(root);
    if (flat.ok && flat.model != null) return flat.model;

    // 深度优先：子目录按名称排序，保证结果稳定
    final subs = <Directory>[];
    await for (final ent in root.list(followLinks: false)) {
      if (ent is Directory) subs.add(ent);
    }
    subs.sort((a, b) => a.path.compareTo(b.path));

    for (final sub in subs) {
      final got = await _discoverFirstValidModelDir(sub, depth: depth + 1);
      if (got != null) return got;
    }
    return null;
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
