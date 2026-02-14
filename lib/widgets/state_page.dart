import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import 'package:wx_divider/wx_divider.dart';

class ErrorMessage extends StatelessWidget {
  const ErrorMessage({super.key, required this.msg, required this.action, this.buttonText = "retry", this.iconData = Icons.refresh});

  final String msg;
  final Function()? action;
  final String buttonText;
  final IconData iconData;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            "error".tr,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary),
          ),
          Padding(padding: EdgeInsets.symmetric(vertical: 10, horizontal: 20), child: _buildErrorInfo()),
          action == null ? Container() : FilledButton.icon(onPressed: action, icon: Icon(iconData), label: Text(buttonText.tr)),
        ],
      ),
    );
  }

  Widget _buildErrorInfo() {
    if (msg.contains("Cloudflare Challenge Detected")) {
      return _getCommonErrorInfoView(msg);
    } else {
      return SingleChildScrollView(child: Text(msg));
    }
  }
}

class LoadingPage extends StatelessWidget {
  const LoadingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}

class LogoPage extends StatelessWidget {
  const LogoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(child: Image.asset("assets/images/logo_transparent.png", width: 150, height: 150));
  }
}

class PleaseSelectPage extends StatelessWidget {
  const PleaseSelectPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Symbols.web_traffic, size: 48),
          const SizedBox(height: 16),
          Text("please_select_type".tr, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class EmptyPage extends StatelessWidget {
  final Function()? onRefresh;

  const EmptyPage({super.key, this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inbox, size: 48),
          const SizedBox(height: 16),
          Text("empty_content".tr, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          onRefresh != null ? TextButton.icon(onPressed: onRefresh, icon: Icon(Icons.refresh), label: Text("refresh".tr)) : const SizedBox(),
        ],
      ),
    );
  }
}

Widget _getCommonErrorInfoView(String msg) => SingleChildScrollView(
  child: Column(
    children: [
      Text("cloudflare_challenge_exception_tip".tr),
      const WxDivider(pattern: WxDivider.dashed, child: Text("Raw Message")),
      const SizedBox(height: 6),
      Text(msg),
    ],
  ),
);

Future showErrorDialog(String msg, List<Widget> actions) {
  late Widget content;
  if (msg.contains("Cloudflare Challenge Detected")) {
    content = _getCommonErrorInfoView(msg);
  } else {
    content = SingleChildScrollView(child: Text(msg));
  }

  return Get.dialog(AlertDialog(title: Text("error".tr), content: content, actions: actions));
}