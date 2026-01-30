import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:characters/characters.dart';
import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import '../service/local_storage_service.dart';
import 'sherpa_model_manager.dart';
import 'role_classifier.dart';

// sherpa-onnx 离线 TTS（Android 优先）
import 'package:flutter/services.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

enum TtsMode { azure, sherpa }

/// 专业听书：
/// - 分角色：旁白/女声/男声自动切换音色
/// - 350 字流式：每次只合成 <=350 字，读完自动续读下一段
/// - 全程异步：不阻塞 UI
class AudiobookTtsService extends GetxService {
  final _dio = Dio();
  final _player = AudioPlayer();
  final _playlist = ConcatenatingAudioSource(children: []);

  final isActive = false.obs;
  final isPlaying = false.obs;
  final isPaused = false.obs;
  final currentRole = SpeakerRole.narrator.obs;

  StreamingChunker? _chunker;
  bool _stopFlag = false;

  int _addedCount = 0;
  final int _prefetchCount = 2;

  // sherpa-onnx runtime
  sherpa.OfflineTts? _sherpaTts;
  bool _sherpaReady = false;
  bool _sherpaIniting = false;
  String? _sherpaModelDir;

  String? _lastSnackKey;
  DateTime? _lastSnackAt;

  void _snackOnce(String title, String message, {Duration window = const Duration(seconds: 2)}) {
    final now = DateTime.now();
    final key = '$title|$message';
    if (_lastSnackKey == key && _lastSnackAt != null && now.difference(_lastSnackAt!) < window) {
      return;
    }
    _lastSnackKey = key;
    _lastSnackAt = now;
    Get.snackbar(title, message);
  }

  @override
  Future<void> onInit() async {
    super.onInit();
    await _player.setAudioSource(_playlist);

    _player.playerStateStream.listen((state) {
      isPlaying.value = state.playing;
      if (isActive.value && !_stopFlag) {
        // 续读：一边播放一边补队列
        _kickPrefetch();
      }
      if (state.processingState == ProcessingState.completed) {
        // 解决“合成比播放慢导致队列读完就停止”的问题：
        // 如果还有未读文本，就补队列并从下一段继续播放。
        final chunker = _chunker;
        if (!_stopFlag && chunker != null && !chunker.isDone) {
          // ignore: discarded_futures
          _continueAfterCompleted();
          return;
        }
        stop();
      }
    });
  }

  TtsMode get mode {
    final raw = LocalStorageService.instance.getTtsMode();
    return (raw == 'sherpa' || raw == 'piper') ? TtsMode.sherpa : TtsMode.azure;
  }

  String get _azureKey => LocalStorageService.instance.getAzureKey().trim();
  String get _azureRegion => LocalStorageService.instance.getAzureRegion().trim();

  String _voiceFor(SpeakerRole role) {
    final ls = LocalStorageService.instance;
    return switch (role) {
      SpeakerRole.female => ls.getVoiceFemale(),
      SpeakerRole.male => ls.getVoiceMale(),
      _ => ls.getVoiceNarrator(),
    };
  }

  /// 开始听书：直接使用你现有的段落数据
  Future<void> startFromParagraphs(List<String> currentChapterParagraphs) async {
    if (currentChapterParagraphs.isEmpty) return;

    await stop();
    _stopFlag = false;

    isActive.value = true;
    isPaused.value = false;
    final mappingsJson = LocalStorageService.instance.getRoleVoiceMappings().map((e) => e.toJson()).toList();
    _chunker = StreamingChunker(paragraphs: currentChapterParagraphs, maxChars: 350, roleVoiceMappingsJson: mappingsJson);

    await _playlist.clear();
    _addedCount = 0;

    // 先预取两段，保证无缝续读
    await _kickPrefetch(awaitAll: true);
    if (_playlist.length == 0) {
      stop();
      return;
    }
    await _player.seek(Duration.zero, index: 0);
    await _player.play();
  }

  Future<void> pause() async {
    if (!isActive.value) return;
    isPaused.value = true;
    await _player.pause();
  }

  Future<void> resume() async {
    if (!isActive.value) return;
    isPaused.value = false;
    await _player.play();
  }

  Future<void> stop() async {
    _stopFlag = true;
    isActive.value = false;
    isPaused.value = false;
    currentRole.value = SpeakerRole.narrator;

    try {
      await _player.stop();
    } catch (_) {}
    try {
      await _playlist.clear();
    } catch (_) {}
    _chunker = null;
  }


Future<void> _continueAfterCompleted() async {
  if (_stopFlag) return;
  final chunker = _chunker;
  if (chunker == null) return;

  // 确保至少补到 1 段
  await _kickPrefetch(awaitAll: true);

  final cur = _player.currentIndex ?? 0;
  final next = cur + 1;
  if (_playlist.length > next) {
    try {
      await _player.seek(Duration.zero, index: next);
      await _player.play();
    } catch (_) {}
  }
}

  Future<void> _kickPrefetch({bool awaitAll = false}) async {
    if (_stopFlag) return;
    final chunker = _chunker;
    if (chunker == null) return;

    final curIndex = _player.currentIndex ?? 0;
    final remaining = max(0, _addedCount - curIndex);
    final need = max(0, _prefetchCount - remaining);
    if (need == 0) return;

    Future<void> one() async {
      if (_stopFlag) return;
      final u = chunker.nextUtterance();
      if (u == null) return;
      currentRole.value = u.role;

      final f = await _synthesizeToTempFile(u.role, u.text, voiceOverride: u.voiceOverride);
      if (f == null || _stopFlag) return;
      await _playlist.add(AudioSource.file(f.path));
      _addedCount++;
    }

    if (awaitAll) {
      for (var i = 0; i < need; i++) {
        await one();
      }
    } else {
      for (var i = 0; i < need; i++) {
        // ignore: discarded_futures
        one();
      }
    }
  }

  Future<File?> _synthesizeToTempFile(SpeakerRole role, String text, {String? voiceOverride}) async {
    if (_stopFlag) return null;
    final safeText = text.characters.take(350).toString();

    final dir = await getTemporaryDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final rnd = Random().nextInt(1 << 20);
    final ext = mode == TtsMode.azure ? 'mp3' : 'wav';
    final out = File('${dir.path}/tts_${ts}_$rnd.$ext');

    if (mode == TtsMode.azure) {
      if (_azureKey.isEmpty || _azureRegion.isEmpty) {
        _snackOnce('Azure 未配置', '请到「我的-设置-听书设置」填写 Azure Key/Region');
        return null;
      }
      final bytes = await _azureSynthesize(role: role, text: safeText, voiceOverride: voiceOverride);
      if (bytes == null) return null;
      await out.writeAsBytes(bytes, flush: true);
      return out;
    }

    // Android：sherpa-onnx
    if (!Platform.isAndroid) return null;
    final ok = await _ensureSherpaReady();
    if (!ok) return null;

    try {
      final tts = _sherpaTts!;
      // 目前离线模型通常只有 1 个说话人（sid=0）；仍保留接口以便未来扩展
      final audio = await _generateSherpaAudio(tts, safeText);
      final wrote = sherpa.writeWave(filename: out.path, samples: audio.samples, sampleRate: audio.sampleRate);
      if (!wrote) return null;
      return out;
    } catch (_) {
      return null;
    }
  }



  /// Azure TTS: synthesize text to MP3 bytes (16kHz/128kbps mono).
  Future<Uint8List?> _azureSynthesize({
    required SpeakerRole role,
    required String text,
    String? voiceOverride,
  }) async {
    final key = _azureKey;
    final region = _azureRegion;
    if (key.isEmpty || region.isEmpty) {
      _snackOnce('Azure 未配置', '请到「我的-设置-听书设置」填写 Azure Key/Region');
      return null;
    }

    final voice = (voiceOverride != null && voiceOverride.trim().isNotEmpty)
        ? voiceOverride.trim()
        : _voiceFor(role);

    // Basic XML escape for SSML.
    String esc(String s) => s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');

    final ssml = '''
<speak version="1.0" xml:lang="zh-CN">
  <voice name="${esc(voice)}">${esc(text)}</voice>
</speak>
''';

    final url = 'https://$region.tts.speech.microsoft.com/cognitiveservices/v1';

    try {
      final resp = await _dio.post<List<int>>(
        url,
        data: ssml,
        options: Options(
          responseType: ResponseType.bytes,
          headers: <String, dynamic>{
            'Ocp-Apim-Subscription-Key': key,
            'Content-Type': 'application/ssml+xml',
            'X-Microsoft-OutputFormat': 'audio-16khz-128kbitrate-mono-mp3',
            'User-Agent': 'hikari_novel_flutter',
          },
        ),
      );

      if (resp.statusCode != 200) {
        final sc = resp.statusCode ?? -1;
        Get.snackbar('Azure 合成失败', 'HTTP $sc');
        return null;
      }
      final data = resp.data;
      if (data == null || data.isEmpty) {
        Get.snackbar('Azure 合成失败', '返回为空');
        return null;
      }
      return Uint8List.fromList(data);
    } on DioException catch (e) {
      final sc = e.response?.statusCode;
      String msg = '请求失败';
      if (sc != null) msg += ' (HTTP $sc)';
      final body = e.response?.data;
      if (body is List<int>) {
        // ignore
      } else if (body != null) {
        msg += '\n$body';
      } else if (e.message != null) {
        msg += '\n${e.message}';
      }
      Get.snackbar('Azure 合成失败', msg);
      return null;
    } catch (e) {
      Get.snackbar('Azure 合成失败', '$e');
      return null;
    }
  }
  Future<sherpa.GeneratedAudio> _generateSherpaAudio(sherpa.OfflineTts tts, String text) async {
    // 这里保持 async，避免阻塞 UI 的 build；实际生成在 native 侧执行，速度取决于模型/设备性能
    return await Future(() => tts.generate(text: text, sid: 0, speed: 1.0));
  }

    Future<bool> _ensureSherpaReady() async {
    if (!Platform.isAndroid) return false;
    if (_sherpaReady && _sherpaTts != null) return true;
    if (_sherpaIniting) return false;
    _sherpaIniting = true;

    try {
      // 1) 优先使用用户已导入并保存的模型目录（真实路径）
      final savedDir = LocalStorageService.instance.getSherpaModelDir();
      if (savedDir != null && savedDir.trim().isNotEmpty) {
        final check = await SherpaModelManager.checkModelDir(savedDir.trim());
        if (check.ok && check.model != null) {
          return await _initSherpaFromModel(check.model!);
        } else {
          // 路径无效：清掉，避免每次都卡在同一个坏路径上
          LocalStorageService.instance.clearSherpaModelDir();
        }
      }

      // 2) 自动扫描应用私有目录下的固定父目录：tts_models/sherpa_matcha_zh/<任意子目录>
      final found = await SherpaModelManager.findFirstValidModel();
      if (found != null) {
        LocalStorageService.instance.setSherpaModelDir(found.dirPath);
        return await _initSherpaFromModel(found);
      }

      // 3) 兜底：如果你开发阶段有把模型放进 assets，则尝试从 assets 拷贝出来再初始化
      //    正式发布建议走“用户导入模型”，不要内置大模型进 APK。
      final ok = await _tryInitSherpaFromAssets();
      if (ok) return true;

      _snackOnce(
        '离线模型未导入',
        '''未找到可用离线模型。
请到「我的-设置-听书设置」导入模型文件夹，放入：tts_models/sherpa_matcha_zh/ 下任意子目录即可。''',
      );
      return false;
    } catch (e) {
      _snackOnce('离线 TTS 初始化失败', '$e');
      return false;
    } finally {
      _sherpaIniting = false;
    }
  }

  Future<bool> _initSherpaFromModel(SherpaModelInfo model) async {
    sherpa.initBindings();

    final vits = sherpa.OfflineTtsVitsModelConfig(
      model: model.onnxPath,
      tokens: model.tokensPath,
      lexicon: model.lexiconPath,
      dataDir: model.dirPath,
    );
    final modelCfg = sherpa.OfflineTtsModelConfig(
      vits: vits,
      numThreads: 2,
      debug: false,
      provider: 'cpu',
    );
    final config = sherpa.OfflineTtsConfig(model: modelCfg);

    _sherpaTts?.free();
    _sherpaTts = sherpa.OfflineTts(config);
    _sherpaReady = true;
    _sherpaModelDir = model.dirPath;
    return true;
  }

  Future<bool> _tryInitSherpaFromAssets() async {
    const basePrefix = 'assets/tts_models/';

    try {
      final assetManifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final allAssets = assetManifest.listAssets().where((k) => k.startsWith(basePrefix)).toList();

      final candidatePrefixes = <String>{};
      for (final a in allAssets) {
        if (a.toLowerCase().endsWith('.onnx')) {
          final idx = a.lastIndexOf('/');
          if (idx > 0) candidatePrefixes.add(a.substring(0, idx + 1));
        }
      }
      if (candidatePrefixes.isEmpty) return false;

      String? chosenPrefix;
      for (final p in candidatePrefixes) {
        final hasTokens = allAssets.contains('${p}tokens.txt');
        final hasLexicon = allAssets.contains('${p}lexicon.txt');
        if (hasTokens && hasLexicon) {
          chosenPrefix = p;
          break;
        }
      }
      chosenPrefix ??= candidatePrefixes.first;

      final manifest = allAssets.where((k) => k.startsWith(chosenPrefix!)).toList();
      if (manifest.isEmpty) return false;

      final onnxAssets = manifest.where((p) => p.toLowerCase().endsWith('.onnx')).toList();
      if (onnxAssets.isEmpty) return false;

      final supportDir = await getApplicationSupportDirectory();
      final safeName = chosenPrefix
          .replaceFirst(basePrefix, '')
          .replaceAll('/', '_')
          .replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
      final modelDir = Directory('${supportDir.path}/sherpa_tts/$safeName');
      await modelDir.create(recursive: true);

      for (final assetPath in manifest) {
        final rel = assetPath.substring(chosenPrefix.length);
        if (rel.isEmpty) continue;
        final outFile = File('${modelDir.path}/$rel');
        if (await outFile.exists()) continue;
        await outFile.parent.create(recursive: true);
        final bd = await rootBundle.load(assetPath);
        await outFile.writeAsBytes(bd.buffer.asUint8List(), flush: true);
      }

      final check = await SherpaModelManager.checkModelDir(modelDir.path);
      if (!check.ok || check.model == null) return false;

      return await _initSherpaFromModel(check.model!);
    } catch (_) {
      return false;
    }
  }

}