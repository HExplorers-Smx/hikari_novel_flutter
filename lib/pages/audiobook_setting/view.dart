import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../service/local_storage_service.dart';

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
    Get.snackbar("已保存", "听书设置已保存");
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

          const SizedBox(height: 20),
          FilledButton(onPressed: _save, child: const Text("保存")),
        ],
      ),
    );
  }
}
