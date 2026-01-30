import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hikari_novel_flutter/hive_registrar.g.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider/path_provider.dart';

import '../models/common/language.dart';
import '../models/common/wenku8_node.dart';
import '../models/dual_page_mode.dart';
import '../models/reader_direction.dart';
import '../models/user_info.dart';
import '../models/tts/role_voice_mapping.dart';
import '../tts/role_classifier.dart';

class LocalStorageService extends GetxService {
  static LocalStorageService get instance => Get.find<LocalStorageService>();

  late final Box<dynamic> _setting;
  late final Box<dynamic> _loginInfo;
  late final Box<dynamic> _reader;

  static const String kCookie = "cookie",
      kUserInfo = "user_info",
      kUsername = "username",
      kPassword = "password",
      kBiometricCheckInEnabled = "biometricCheckInEnabled",
      kLanguage = "language",
      kIsAutoCheckUpdate = "isAutoCheckUpdate",
      kWenku8Node = "wenku8Node",
      kIsDynamicColor = "isDynamicColor",
      kCustomColor = "customColor",
      kThemeMode = "themeMode",
      kDefaultHomePage = "defaultHomePage",
      kReadMode = "readMode",
      kIsRelativeTime = "isRelativeTime",
      kReaderDirection = "readerDirection",
      kReaderFontSize = "readerFontSize",
      kReaderLineSpacing = "readerLineSpacing",
      kReaderWakeLock = "readerWakeLock",
      kReaderLeftMargin = "readerLeftMargin",
      kReaderTopMargin = "readerTopMargin",
      kReaderRightMargin = "readerRightMargin",
      kReaderBottomMargin = "readerBottomMargin",
      kReaderDualPageMode = "readerDualPageMode",
      kReaderDualPageSpacing = "readerDualPageSpacing",
      kReaderImmersionMode = "readerImmersionMode",
      kReaderStatusBar = "readerStatusBar",
      kReaderDayBgColor = "readerDayBgColor",
      kReaderDayTextColor = "readerDayTextColor",
      kReaderNightBgColor = "readerNightBgColor",
      kReaderNightTextColor = "readerNightTextColor",
      kReaderDayBgImage = "readerDayBgImage",
      kReaderNightBgImage = "readerNightBgImage",
      kReaderTextFamily = "readerTextFamily",
      kReaderTextStyleFilePath = "readerTextStyleFilePath",
      kReaderPageTurningAnimation = "readerPageTurningAnimation",
      // ===== 听书 / TTS =====
      kTtsMode = "ttsMode", // "azure" | "sherpa"
      kAzureKey = "azureKey",
      kAzureRegion = "azureRegion",
      kVoiceNarrator = "voiceNarrator",
      kVoiceFemale = "voiceFemale",
      kVoiceMale = "voiceMale",
      kRoleVoiceMappings = "roleVoiceMappings", // JSON 列表：角色名->(role/voice)
      kSherpaModelDir = "sherpaModelDir"; // 离线 sherpa 模型目录（应用私有目录下的真实路径）

  Future<void> init() async {
    final Directory dir = await getApplicationSupportDirectory();
    final String path = dir.path;
    Hive.init("$path/hive");
    Hive.registerAdapters();
    _setting = await Hive.openBox("setting");
    _loginInfo = await Hive.openBox("loginInfo");
    _reader = await Hive.openBox("reader");
  }

  void setCookie(String? value) => _loginInfo.put(kCookie, value);

  String? getCookie() => _loginInfo.get(kCookie);

  void setUserInfo(UserInfo value) => _setting.put(kUserInfo, value);

  UserInfo? getUserInfo() => _setting.get(kUserInfo);

  void setUsername(String value) => _loginInfo.put(kUsername, value);

  String? getUsername() => _loginInfo.get(kUsername);

  void setPassword(String value) => _loginInfo.put(kPassword, value);

  String? getPassword() => _loginInfo.get(kPassword);

  void setBiometricCheckInEnabled(bool enabled) => _setting.put(kBiometricCheckInEnabled, enabled);

  bool getBiometricCheckInEnabled() => _setting.get(kBiometricCheckInEnabled, defaultValue: false);

  void setIsAutoCheckUpdate(bool enabled) => _setting.put(kIsAutoCheckUpdate, enabled);

  bool getIsAutoCheckUpdate() => _setting.get(kIsAutoCheckUpdate, defaultValue: true);

  void setThemeMode(ThemeMode tm) => _setting.put(kThemeMode, tm.index);

  ThemeMode getThemeMode() => ThemeMode.values[_setting.get(kThemeMode, defaultValue: ThemeMode.system.index)];

  void setCustomColor(Color color) => _setting.put(kCustomColor, color.toARGB32());

  Color getCustomColor() => Color(_setting.get(kCustomColor, defaultValue: Colors.blue.toARGB32()));

  void setIsDynamicColor(bool enabled) => _setting.put(kIsDynamicColor, enabled);

  bool getIsDynamicColor() => _setting.get(kIsDynamicColor, defaultValue: true);

  void setIsRelativeTime(bool enabled) => _setting.put(kIsRelativeTime, enabled);

  bool getIsRelativeTime() => _setting.get(kIsRelativeTime, defaultValue: false);

  // ===== 听书 / TTS =====
  void setTtsMode(String mode) => _setting.put(kTtsMode, mode);

  String getTtsMode() => _setting.get(kTtsMode, defaultValue: "azure");

  void setAzureKey(String v) => _setting.put(kAzureKey, v);

  String getAzureKey() => _setting.get(kAzureKey, defaultValue: "");

  void setAzureRegion(String v) => _setting.put(kAzureRegion, v);

  String getAzureRegion() => _setting.get(kAzureRegion, defaultValue: "eastasia");

  void setVoiceNarrator(String v) => _setting.put(kVoiceNarrator, v);

  String getVoiceNarrator() => _setting.get(kVoiceNarrator, defaultValue: "zh-CN-XiaoxiaoNeural");

  void setVoiceFemale(String v) => _setting.put(kVoiceFemale, v);

  String getVoiceFemale() => _setting.get(kVoiceFemale, defaultValue: "zh-CN-XiaoyiNeural");

  void setVoiceMale(String v) => _setting.put(kVoiceMale, v);

  String getVoiceMale() => _setting.get(kVoiceMale, defaultValue: "zh-CN-YunxiNeural");

  // ===== 角色列表：用于自动识别“角色：台词”并切换音色（Azure 模式下最明显） =====
  void setRoleVoiceMappings(List<RoleVoiceMapping> list) {
    final raw = jsonEncode(list.map((e) => e.toJson()).toList());
    _setting.put(kRoleVoiceMappings, raw);
  }

  List<RoleVoiceMapping> getRoleVoiceMappings() {
    final raw = _setting.get(kRoleVoiceMappings, defaultValue: "[]");
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final out = <RoleVoiceMapping>[];
      for (final item in decoded) {
        final m = RoleVoiceMapping.fromJson(item);
        if (m != null) out.add(m);
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  void addOrUpdateRoleVoice(RoleVoiceMapping item) {
    final list = getRoleVoiceMappings();
    final idx = list.indexWhere((e) => e.name == item.name);
    if (idx >= 0) {
      list[idx] = item;
    } else {
      list.add(item);
    }
    setRoleVoiceMappings(list);
  }

  void removeRoleVoice(String name) {
    final list = getRoleVoiceMappings()..removeWhere((e) => e.name == name);
    setRoleVoiceMappings(list);
  }


  

// ===== sherpa-onnx 离线模型目录（用户导入后保存的真实路径）=====
void setSherpaModelDir(String? dirPath) {
  if (dirPath == null || dirPath.trim().isEmpty) {
    _setting.delete(kSherpaModelDir);
    return;
  }
  _setting.put(kSherpaModelDir, dirPath.trim());
}

String? getSherpaModelDir() => _setting.get(kSherpaModelDir, defaultValue: null);

void clearSherpaModelDir() => _setting.delete(kSherpaModelDir);

void setLanguage(Language value) => _setting.put(kLanguage, value.index);

  Language getLanguage() => Language.values[_setting.get(kLanguage, defaultValue: Language.followSystem.index)];

  void setWenku8Node(Wenku8Node value) => _setting.put(kWenku8Node, value.index);

  Wenku8Node getWenku8Node() => Wenku8Node.values[_setting.get(kWenku8Node, defaultValue: Wenku8Node.wwwWenku8Net.index)];

  ReaderDirection getReaderDirection() => ReaderDirection.values[_reader.get(kReaderDirection, defaultValue: ReaderDirection.upToDown.index)];

  void setReaderDirection(ReaderDirection value) => _reader.put(kReaderDirection, value.index);

  double getReaderFontSize() => _reader.get(kReaderFontSize, defaultValue: 16.0);

  void setReaderFontSize(double value) => _reader.put(kReaderFontSize, value);

  double getReaderLineSpacing() => _reader.get(kReaderLineSpacing, defaultValue: 1.5);

  void setReaderLineSpacing(double value) => _reader.put(kReaderLineSpacing, value);

  bool getReaderWakeLock() => _reader.get(kReaderWakeLock, defaultValue: false);

  void setReaderWakeLock(bool enabled) => _reader.put(kReaderWakeLock, enabled);

  double getReaderLeftMargin() => _reader.get(kReaderLeftMargin, defaultValue: 20.0);

  void setReaderLeftMargin(double value) => _reader.put(kReaderLeftMargin, value);

  double getReaderTopMargin() => _reader.get(kReaderTopMargin, defaultValue: 20.0);

  void setReaderTopMargin(double value) => _reader.put(kReaderTopMargin, value);

  double getReaderRightMargin() => _reader.get(kReaderRightMargin, defaultValue: 20.0);

  void setReaderRightMargin(double value) => _reader.put(kReaderRightMargin, value);

  double getReaderBottomMargin() => _reader.get(kReaderBottomMargin, defaultValue: 20.0);

  void setReaderBottomMargin(double value) => _reader.put(kReaderBottomMargin, value);

  DualPageMode getReaderDualPageMode() => DualPageMode.values[_reader.get(kReaderDualPageMode, defaultValue: DualPageMode.auto.index)];

  void setReaderDualPageMode(DualPageMode value) => _reader.put(kReaderDualPageMode, value.index);

  double getReaderDualPageSpacing() => _reader.get(kReaderDualPageSpacing, defaultValue: 20.0);

  void setReaderDualPageSpacing(double value) => _reader.put(kReaderDualPageSpacing, value);

  bool getReaderImmersionMode() => _reader.get(kReaderImmersionMode, defaultValue: false);

  void setReaderImmersionMode(bool enabled) => _reader.put(kReaderImmersionMode, enabled);

  bool getReaderStatusBar() => _reader.get(kReaderStatusBar, defaultValue: true);

  void setReaderStatusBar(bool enabled) => _reader.put(kReaderStatusBar, enabled);

  String? getReaderTextFamily() => _reader.get(kReaderTextFamily, defaultValue: null);

  void setReaderTextFamily(String? value) => _reader.put(kReaderTextFamily, value);

  String? getReaderTextStyleFilePath() => _reader.get(kReaderTextStyleFilePath, defaultValue: null);

  void setReaderTextStyleFilePath(String? value) => _reader.put(kReaderTextStyleFilePath, value);

  bool getReaderPageTurningAnimation() => _reader.get(kReaderPageTurningAnimation, defaultValue: true);

  void setReaderPageTurningAnimation(bool enabled) => _reader.put(kReaderPageTurningAnimation, enabled);

  Color? getReaderDayBgColor() {
    final result = _reader.get(kReaderDayBgColor, defaultValue: null);
    return result == null ? null : Color(result);
  }

  void setReaderDayBgColor(Color? value) => _reader.put(kReaderDayBgColor, value?.toARGB32());

  Color? getReaderDayTextColor() {
    final result = _reader.get(kReaderDayTextColor, defaultValue: null);
    return result == null ? null : Color(result);
  }

  void setReaderDayTextColor(Color? value) => _reader.put(kReaderDayTextColor, value?.toARGB32());

  Color? getReaderNightBgColor() {
    final result = _reader.get(kReaderNightBgColor, defaultValue: null);
    return result == null ? null : Color(result);
  }

  void setReaderNightBgColor(Color? value) => _reader.put(kReaderNightBgColor, value?.toARGB32());

  Color? getReaderNightTextColor() {
    final result = _reader.get(kReaderNightTextColor, defaultValue: null);
    return result == null ? null : Color(result);
  }

  void setReaderNightTextColor(Color? value) => _reader.put(kReaderNightTextColor, value?.toARGB32());

  String? getReaderDayBgImage() => _reader.get(kReaderDayBgImage, defaultValue: null);

  void setReaderDayBgImage(String? value) => _reader.put(kReaderDayBgImage, value);

  String? getReaderNightBgImage() => _reader.get(kReaderDayBgImage, defaultValue: null);

  void setReaderNightBgImage(String? value) => _reader.put(kReaderDayBgImage, value);
}
