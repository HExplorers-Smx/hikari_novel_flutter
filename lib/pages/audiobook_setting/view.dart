import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:get/get.dart';

import '../../service/local_storage_service.dart';
import '../../models/tts/role_voice_mapping.dart';
import '../../tts/role_classifier.dart';
import '../../tts/sherpa_model_manager.dart';

class AudiobookSettingPage extends StatefulWidget {
  const AudiobookSettingPage({super.key});

  @override
  State<AudiobookSettingPage> createState() => _AudiobookSettingPageState();
}

class _AudiobookSettingPageState extends State<AudiobookSettingPage> {
  final ls = LocalStorageService.instance;

  late final TextEditingController keyCtrl;
  late final TextEditingController regionCtrl;

  late final TextEditingController narratorVoiceCtrl;
  late final TextEditingController femaleVoiceCtrl;
  late final TextEditingController maleVoiceCtrl;

  late String mode; // "azure" | "sherpa"

  List<RoleVoiceMapping> roleMappings = [];

  @override
  void initState() {
    super.initState();
    mode = ls.getTtsMode();
    if (mode == 'piper') mode = 'sherpa';
    keyCtrl = TextEditingController(text: ls.getAzureKey());
    regionCtrl = TextEditingController(text: ls.getAzureRegion());

    narratorVoiceCtrl = TextEditingController(text: ls.getVoiceNarrator());
    femaleVoiceCtrl = TextEditingController(text: ls.getVoiceFemale());
    maleVoiceCtrl = TextEditingController(text: ls.getVoiceMale());

    roleMappings = ls.getRoleVoiceMappings();
  }

  @override
  void dispose() {
    keyCtrl.dispose();
    regionCtrl.dispose();
    narratorVoiceCtrl.dispose();
    femaleVoiceCtrl.dispose();
    maleVoiceCtrl.dispose();
    super.dispose();
  }

  void _save() {
    ls.setTtsMode(mode);
    ls.setAzureKey(keyCtrl.text.trim());
    ls.setAzureRegion(regionCtrl.text.trim());
    ls.setVoiceNarrator(narratorVoiceCtrl.text.trim());
    ls.setVoiceFemale(femaleVoiceCtrl.text.trim());
    ls.setVoiceMale(maleVoiceCtrl.text.trim());
    ls.setRoleVoiceMappings(roleMappings);
    Get.snackbar("已保存", "听书设置已保存");
  }

  


Future<void> _importSherpaModel() async {
  if (!Platform.isAndroid) {
    Get.snackbar('仅支持 Android', '离线 sherpa-onnx 目前仅在 Android 端可用');
    return;
  }

  final picked = await FilePicker.platform.getDirectoryPath(dialogTitle: '选择模型文件夹（解压后的目录）');
  if (picked == null || picked.trim().isEmpty) return;

  Get.dialog(
    const AlertDialog(
      content: Row(
        children: [
          CircularProgressIndicator(),
          SizedBox(width: 16),
          Expanded(child: Text('正在导入模型，请稍候...')),
        ],
      ),
    ),
    barrierDismissible: false,
  );

  try {
    final dst = await SherpaModelManager.importModelDirectory(picked.trim());
    final check = await SherpaModelManager.checkModelDir(dst.path);
    if (!check.ok || check.model == null) {
      await dst.delete(recursive: true);
      Get.back();
      Get.snackbar('导入失败', '模型不完整：${check.message}\n\n请确认目录内至少包含：*.onnx / tokens.txt / lexicon.txt');
      setState(() {});
      return;
    }

    ls.setSherpaModelDir(check.model!.dirPath);
    Get.back();
    Get.snackbar('导入成功', '已导入：${p.basename(check.model!.dirPath)}');
    setState(() {});
  } catch (e) {
    try {
      Get.back();
    } catch (_) {}
    Get.snackbar('导入失败', '$e');
  }
}

Future<void> _clearSherpaModels() async {
  if (!Platform.isAndroid) {
    Get.snackbar('仅支持 Android', '离线 sherpa-onnx 目前仅在 Android 端可用');
    return;
  }

  final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: const Text('清除离线模型'),
            content: const Text('将删除已导入到应用私有目录下的所有离线模型文件。确定继续吗？'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
            ],
          );
        },
      ) ??
      false;

  if (!ok) return;

  try {
    await SherpaModelManager.deleteAllImportedModels();
    ls.clearSherpaModelDir();
    Get.snackbar('已清除', '离线模型已删除');
    setState(() {});
  } catch (e) {
    Get.snackbar('清除失败', '$e');
  }
}

Future<void> _copySherpaPathToClipboard() async {
  final dir = ls.getSherpaModelDir();
  if (dir == null || dir.trim().isEmpty) {
    Get.snackbar('未设置', '当前没有已选择的离线模型目录');
    return;
  }
  await Clipboard.setData(ClipboardData(text: dir));
  Get.snackbar('已复制', '模型路径已复制到剪贴板');
}

Future<RoleVoiceMapping?> _editRoleMapping(BuildContext context, RoleVoiceMapping? current) async {
  final nameCtrl = TextEditingController(text: current?.name ?? "");
  final voiceCtrl = TextEditingController(text: current?.voiceOverride ?? "");
  SpeakerRole role = current?.role ?? SpeakerRole.narrator;

  final result = await showDialog<RoleVoiceMapping>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: Text(current == null ? "添加角色" : "编辑角色"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: "角色名（如：金次）",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<SpeakerRole>(
                value: role,
                decoration: const InputDecoration(
                  labelText: "类型",
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: SpeakerRole.narrator, child: Text("旁白")),
                  DropdownMenuItem(value: SpeakerRole.female, child: Text("女声")),
                  DropdownMenuItem(value: SpeakerRole.male, child: Text("男声")),
                ],
                onChanged: (v) {
                  if (v != null) role = v;
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: voiceCtrl,
                decoration: const InputDecoration(
                  labelText: "可选：指定 Azure Voice（留空用默认）",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "提示：正文出现“角色名：台词”时触发匹配；Azure 模式下多音色效果最明显。",
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("取消"),
          ),
          FilledButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text("角色名不能为空")));
                return;
              }
              final voice = voiceCtrl.text.trim();
              Navigator.pop(
                ctx,
                RoleVoiceMapping(
                  name: name,
                  role: role,
                  voiceOverride: voice.isEmpty ? null : voice,
                ),
              );
            },
            child: const Text("保存"),
          ),
        ],
      );
    },
  );

  nameCtrl.dispose();
  voiceCtrl.dispose();
  return result;
}

@override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("听书设置")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text("引擎模式", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          RadioListTile<String>(
            value: "azure",
            groupValue: mode,
            onChanged: (v) => setState(() => mode = v!),
            title: const Text("云端模式（Azure TTS）"),
            subtitle: const Text("音质最好，需要 Key 和区域"),
          ),
          RadioListTile<String>(
            value: "sherpa",
            groupValue: mode,
            onChanged: (v) => setState(() => mode = v!),
            title: const Text("离线模式（sherpa-onnx，Android）"),
            subtitle: const Text("无网络也能朗读（中文模型需要你后续按说明部署）"),
          ),
          
const Divider(height: 32),

const Text("离线模型（sherpa-onnx）", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
const SizedBox(height: 8),
Text(
  ls.getSherpaModelDir() == null ? "当前：未导入/未选择模型" : "当前模型目录：\n${ls.getSherpaModelDir()}",
  style: const TextStyle(color: Colors.grey),
),
const SizedBox(height: 12),
Row(
  children: [
    Expanded(
      child: FilledButton.icon(
        onPressed: _importSherpaModel,
        icon: const Icon(Icons.folder_open),
        label: const Text("导入模型文件夹"),
      ),
    ),
    const SizedBox(width: 12),
    IconButton(
      tooltip: "复制路径",
      onPressed: _copySherpaPathToClipboard,
      icon: const Icon(Icons.copy),
    ),
    IconButton(
      tooltip: "清除",
      onPressed: _clearSherpaModels,
      icon: const Icon(Icons.delete_outline),
    ),
  ],
),
const SizedBox(height: 8),
const Text(
  "说明：请先把模型压缩包解压成文件夹，然后在这里选择该文件夹导入。\n"
  "导入后程序会把它复制到应用私有目录：tts_models/sherpa_matcha_zh/ 下（子文件夹名字不限制）。\n"
  "模型目录内至少需要包含：*.onnx / tokens.txt / lexicon.txt",
  style: TextStyle(color: Colors.grey, fontSize: 12),
),


          const Text("Azure 配置", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: keyCtrl,
            decoration: const InputDecoration(labelText: "Azure API Key", border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: regionCtrl,
            decoration: const InputDecoration(labelText: "Azure 区域（如 eastasia / japaneast）", border: OutlineInputBorder()),
          ),
          const Divider(height: 32),

          const Text("分角色音色（Azure Voice Name）", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: narratorVoiceCtrl,
            decoration: const InputDecoration(labelText: "旁白 Voice", border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: femaleVoiceCtrl,
            decoration: const InputDecoration(labelText: "女声 Voice", border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: maleVoiceCtrl,
            decoration: const InputDecoration(labelText: "男声 Voice", border: OutlineInputBorder()),
          ),

                    const Divider(height: 32),

          Row(
            children: [
              const Expanded(
                child: Text(
                  "角色列表（自动识别“角色名：台词”）",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              TextButton.icon(
                onPressed: () async {
                  final created = await _editRoleMapping(context, null);
                  if (created != null) {
                    setState(() {
                      roleMappings.removeWhere((e) => e.name == created.name);
                      roleMappings.add(created);
                    });
                  }
                },
                icon: const Icon(Icons.add),
                label: const Text("添加"),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (roleMappings.isEmpty)
            const Text(
              "你可以在这里添加角色名（如：金次、亚莉亚），当正文出现“角色名：xxx”时会自动切换到对应男/女/旁白音色（Azure 模式下生效最明显）。",
              style: TextStyle(color: Colors.grey),
            )
          else
            ...roleMappings.map((m) {
              final roleText = switch (m.role) {
                SpeakerRole.female => "女声",
                SpeakerRole.male => "男声",
                _ => "旁白",
              };
              final voiceText = (m.voiceOverride == null || m.voiceOverride!.isEmpty)
                  ? "（使用默认${roleText}音色）"
                  : m.voiceOverride!;
              return Card(
                child: ListTile(
                  title: Text(m.name),
                  subtitle: Text("$roleText  $voiceText"),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) async {
                      if (v == 'edit') {
                        final updated = await _editRoleMapping(context, m);
                        if (updated != null) {
                          setState(() {
                            roleMappings.removeWhere((e) => e.name == m.name);
                            roleMappings.add(updated);
                          });
                        }
                        return;
                      }
                      if (v == 'delete') {
                        setState(() => roleMappings.removeWhere((e) => e.name == m.name));
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'edit', child: Text("编辑")),
                      PopupMenuItem(value: 'delete', child: Text("删除")),
                    ],
                  ),
                ),
              );
            }),

const SizedBox(height: 20),
          FilledButton(onPressed: _save, child: const Text("保存")),
        ],
      ),
    );
  }
}
