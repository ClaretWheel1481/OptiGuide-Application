import 'package:flutter/material.dart';

// 没有摄像头时显示的应用
class NoCamera extends StatelessWidget {
  const NoCamera({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OptiGuide',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const Scaffold(body: Center(child: Text('未找到可用的摄像头!'))),
    );
  }
}
