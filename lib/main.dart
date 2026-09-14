import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:webview_flutter_windows/webview_windows.dart';

import 'screens/home_screen.dart';
import 'services/inbox_server.dart';
import 'services/share_receiver_service.dart';

/// 自定义的 WebView2 用户数据目录（规避默认 profile 权限/损坏问题）。
const String kFluxioWebView2UserData =
    r'C:\Users\iyaba\AppData\Local\com.plbear\fluxio_webview2_v2';

/// 全局收件服务单例（设置页与主页共用）。
final InboxServer inboxServer = InboxServer();

/// 全局分享接收服务单例（Share Extension + 剪贴板检测）。
final ShareReceiverService shareReceiver = ShareReceiverService();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) {
    try {
      await WebviewController.initializeEnvironment(
        userDataPath: kFluxioWebView2UserData,
      );
    } catch (_) {
      // 初始化失败不阻塞应用启动；WebView 会走默认路径。
    }
  }
  // 启动本地收件服务；失败不阻塞应用（设置页会显示未运行）。
  try {
    await inboxServer.start();
  } catch (e) {
    debugPrint('InboxServer start failed: $e');
  }
  // 初始化分享接收服务（Share Extension + 剪贴板检测）。
  shareReceiver.init();
  runApp(const FluxioApp());
}

class FluxioApp extends StatelessWidget {
  const FluxioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fluxio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 1,
          centerTitle: false,
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal, brightness: Brightness.dark),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E1E1E),
          foregroundColor: Colors.white,
          elevation: 1,
          centerTitle: false,
        ),
      ),
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}
