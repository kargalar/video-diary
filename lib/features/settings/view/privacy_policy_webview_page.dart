import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class PrivacyPolicyWebViewPage extends StatefulWidget {
  static const route = '/privacy-policy';
  const PrivacyPolicyWebViewPage({super.key});

  @override
  State<PrivacyPolicyWebViewPage> createState() => _PrivacyPolicyWebViewPageState();
}

class _PrivacyPolicyWebViewPageState extends State<PrivacyPolicyWebViewPage> {
  late final WebViewController controller;
  bool isLoading = true;

  final String privacyPolicyUrl = 'https://kargalar.github.io/videodiary_privacy/';

  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            if (progress == 100) {
              setState(() => isLoading = false);
            }
          },
          onPageStarted: (String url) {
            setState(() => isLoading = true);
          },
          onPageFinished: (String url) {
            setState(() => isLoading = false);
          },
          onWebResourceError: (WebResourceError error) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading page: ${error.description}'), backgroundColor: Colors.red));
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(privacyPolicyUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy Policy'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.of(context).pop()),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: controller),
          if (isLoading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
