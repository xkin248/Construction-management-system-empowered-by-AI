// Stub for web platform — WebView is not supported in browser.
// The conditional export in webview.dart selects this file on web.

import 'package:flutter/material.dart';

/// A no-op widget that shows a placeholder when WebView is unavailable.
class WebViewWidget extends StatelessWidget {
  final dynamic controller;
  const WebViewWidget({super.key, required this.controller});

  @override
  Widget build(BuildContext context) => Container(
        color: const Color(0xFFF4F6FB),
        child: const Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.web_asset_off_outlined, size: 48, color: Color(0xFF9CA3AF)),
            SizedBox(height: 12),
            Text(
              'WebView not available on web platform',
              style: TextStyle(color: Color(0xFF6B7280), fontSize: 13),
            ),
          ]),
        ),
      );
}

class WebViewController {
  Future<void> loadRequest(Uri uri) async {}
  Future<void> loadHtmlString(String html) async {}
}
