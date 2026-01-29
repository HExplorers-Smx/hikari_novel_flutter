import 'dart:io';
import 'dart:math';

import 'package:characters/characters.dart';
import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import '../service/local_storage_service.dart';
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
  String? _sherpaModelDir;

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
    _chunker = StreamingChunker(paragraphs: currentChapterParagraphs, maxChars: 350);

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

      final f = await _synthesizeToTempFile(u.role, u.text);
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

  Future<File?> _synthesizeToTempFile(SpeakerRole role, String text) async {
    if (_stopFlag) return null;
    final safeText = text.characters.take(350).toString();

    final dir = await getTemporaryDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final rnd = Random().nextInt(1 << 20);
    final ext = mode == TtsMode.azure ? 'mp3' : 'wav';
    final out = File('${dir.path}/tts_${ts}_$rnd.$ext');

    if (mode == TtsMode.azure) {
      if (_azureKey.isEmpty || _azureRegion.isEmpty) return null;
      final bytes = await _azureSynthesize(role: role, text: safeText);
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

  Future<sherpa.GeneratedAudio> _generateSherpaAudio(sherpa.OfflineTts tts, String text) async {
    // 这里保持 async，避免阻塞 UI 的 build；实际生成在 native 侧执行，速度取决于模型/设备性能
    return await Future(() => tts.generate(text: text, sid: 0, speed: 1.0));
  }

  Future<bool> _ensureSherpaReady() async {
    if (_sherpaReady && _sherpaTts != null) return true;

    // 模型文件要求：放在 assets/tts_models/sherpa_matcha_zh/ 下（见 README/说明）
    // 我们会把 assets 拷贝到可读写目录，然后把路径交给 sherpa-onnx。
    final dir = await getApplicationSupportDirectory();
    final modelDir = Directory('${dir.path}/sherpa_tts/matcha_zh');
    _sherpaModelDir = modelDir.path;

    // 你可以把下面这些文件按同名放到 assets 里（不放则离线模式不可用）
    const requiredFiles = <String>[
      'acoustic_model.onnx',
      'vocoder.onnx',
      'tokens.txt',
      'lexicon.txt',
    ];

    try {
      await modelDir.create(recursive: true);
      for (final f in requiredFiles) {
        final out = File('${modelDir.path}/$f');
        if (!await out.exists()) {
          final bd = await rootBundle.load('assets/tts_models/sherpa_matcha_zh/$f');
          await out.writeAsBytes(bd.buffer.asUint8List(), flush: true);
        }
      }

      sherpa.initBindings(); // 主 isolate 初始化一次
      final matcha = sherpa.OfflineTtsMatchaModelConfig(
        acousticModel: '${modelDir.path}/acoustic_model.onnx',
        vocoder: '${modelDir.path}/vocoder.onnx',
        tokens: '${modelDir.path}/tokens.txt',
        lexicon: '${modelDir.path}/lexicon.txt',
        dataDir: modelDir.path,
      );
      final model = sherpa.OfflineTtsModelConfig(matcha: matcha, numThreads: 2, debug: false, provider: 'cpu');
      final config = sherpa.OfflineTtsConfig(model: model);

      _sherpaTts?.free();
      _sherpaTts = sherpa.OfflineTts(config);
      _sherpaReady = true;
      return true;
    } catch (_) {
      _sherpaReady = false;
      return false;
    }
  }

  Future<List<int>?> _azureSynthesize({required SpeakerRole role, required String text}) async {
    final url = 'https://$_azureRegion.tts.speech.microsoft.com/cognitiveservices/v1';
    final voice = _voiceFor(role);
    final ssml = '''
<speak version="1.0" xml:lang="zh-CN">
  <voice name="$voice">${_escapeXml(text)}</voice>
</speak>
''';

    try {
      final res = await _dio.post<List<int>>(
        url,
        data: ssml,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {
            'Ocp-Apim-Subscription-Key': _azureKey,
            'Content-Type': 'application/ssml+xml',
            'X-Microsoft-OutputFormat': 'audio-16khz-32kbitrate-mono-mp3',
            'User-Agent': 'hikari_novel_flutter',
          },
        ),
      );
      return res.data;
    } catch (_) {
      return null;
    }
  }

  String _escapeXml(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}
