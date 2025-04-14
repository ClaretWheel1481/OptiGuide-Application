import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:optiguide_application/pages/no_camera.dart';
import 'package:optiguide_application/pages/video_stream/main.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 获取可用摄像头列表
  final cameras = await availableCameras();
  if (cameras.isEmpty) {
    runApp(const NoCamera());
    return;
  }

  // 默认使用第一个摄像头
  final firstCamera = cameras.first;
  runApp(OptiGuideApp(camera: firstCamera));
}

class OptiGuideApp extends StatelessWidget {
  final CameraDescription camera;

  const OptiGuideApp({Key? key, required this.camera}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OptiGuide',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: VideoStreamPage(camera: camera),
    );
  }
}
