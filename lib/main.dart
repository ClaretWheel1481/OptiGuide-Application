import 'dart:async';
import 'dart:convert';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  final firstCamera = cameras.first;
  runApp(MyApp(camera: firstCamera));
}

class MyApp extends StatelessWidget {
  final CameraDescription camera;
  const MyApp({Key? key, required this.camera}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OptiGuide',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: VideoStreamPage(camera: camera),
    );
  }
}

class VideoStreamPage extends StatefulWidget {
  final CameraDescription camera;
  const VideoStreamPage({Key? key, required this.camera}) : super(key: key);

  @override
  _VideoStreamPageState createState() => _VideoStreamPageState();
}

class _VideoStreamPageState extends State<VideoStreamPage> {
  late CameraController _controller;
  late IO.Socket _socket;
  bool _isConnected = false;
  bool _isStreaming = false;
  List<dynamic> _detections = [];
  int _framesCount = 0;
  int _quality = 85; // JPEG压缩质量，可调整
  int _frameInterval = 100; // 帧发送间隔(毫秒)，可调整
  String _serverAddress = '192.168.6.120:5000';

  // 性能监控
  Stopwatch _stopwatch = Stopwatch();
  DateTime _lastFpsUpdate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _connectSocket();
  }

  Future<void> _initializeCamera() async {
    _controller = CameraController(
      widget.camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    try {
      await _controller.initialize();
      setState(() {});
    } catch (e) {
      debugPrint('Error initializing camera: $e');
    }
  }

  // TODO: 诡异的一直断开重连
  void _connectSocket() {
    try {
      debugPrint(
        'Attempting to connect to Socket.IO server at $_serverAddress',
      );

      _socket = IO.io('http://$_serverAddress', <String, dynamic>{
        'transports': ['websocket'],
        'autoConnect': true,
        'forceNew': true,
      });

      _socket.onConnect((_) {
        debugPrint('Socket.IO connection established');
        setState(() {
          _isConnected = true;
        });

        if (!_isStreaming) {
          _startVideoStream();
        }
      });

      _socket.on('message', (data) {
        debugPrint('Server message: $data');
      });

      _socket.on('detections', (data) {
        setState(() {
          _detections = data['detections'] ?? [];
        });
      });

      _socket.onDisconnect((_) {
        debugPrint('Socket.IO disconnected');
        setState(() {
          _isConnected = false;
          _isStreaming = false;
        });

        // 添加一个延迟再尝试重连，避免立即重连
        Future.delayed(const Duration(seconds: 5), () {
          if (mounted && !_socket.connected) {
            _connectSocket();
          }
        });
      });

      _socket.onError((error) {
        debugPrint('Socket.IO error: $error');
        setState(() {
          _isConnected = false;
        });
      });

      _socket.connect();
    } catch (e) {
      debugPrint('Failed to connect to Socket.IO: $e');
      // 重试连接
      Future.delayed(const Duration(seconds: 3), _connectSocket);
    }
  }

  void _startVideoStream() {
    if (_isStreaming) return;

    setState(() {
      _isStreaming = true;
    });

    _stopwatch.start();

    // 启动视频帧捕获和发送
    _captureAndSendFrames();
  }

  Future<void> _captureAndSendFrames() async {
    if (!_isStreaming || !_isConnected) {
      return;
    }

    try {
      // 捕获视频帧
      final XFile imageFile = await _controller.takePicture();
      final bytes = await imageFile.readAsBytes();

      // 发送视频帧
      if (_isConnected) {
        final base64Image = 'data:image/jpeg;base64,${base64Encode(bytes)}';
        _socket.emit('videoFrame', {'frame': base64Image});

        // 更新计数器
        _framesCount++;
      }

      // 控制发送频率，防止过载
      await Future.delayed(Duration(milliseconds: _frameInterval));

      // 继续捕获下一帧
      if (_isStreaming) {
        _captureAndSendFrames();
      }
    } catch (e) {
      debugPrint('Error capturing video frame: $e');
      // 短暂延迟后重试
      await Future.delayed(const Duration(milliseconds: 500));
      if (_isStreaming) {
        _captureAndSendFrames();
      }
    }
  }

  void _stopVideoStream() {
    setState(() {
      _isStreaming = false;
    });
    _stopwatch.stop();
    _stopwatch.reset();
  }

  @override
  void dispose() {
    _stopVideoStream();
    _controller.dispose();
    _socket.disconnect();
    _socket.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.value.isInitialized) {
      return Scaffold(
        appBar: AppBar(title: const Text('OptiGuide')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('OptiGuide'),
        actions: [
          Container(
            margin: const EdgeInsets.all(16.0),
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isConnected ? Colors.green : Colors.red,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                CameraPreview(_controller),
                CustomPaint(
                  painter: DetectionPainter(
                    detections: _detections,
                    previewSize: _controller.value.previewSize!,
                    screenSize: MediaQuery.of(context).size,
                  ),
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            color: Colors.black54,
            padding: const EdgeInsets.all(8.0),
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Status: ${_isConnected ? "Connected" : "Disconnected"} / ${_isStreaming ? "Streaming" : "Not Streaming"}',
                  style: const TextStyle(color: Colors.white),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Quality: $_quality%',
                            style: const TextStyle(color: Colors.white),
                          ),
                          Slider(
                            value: _quality.toDouble(),
                            min: 10,
                            max: 100,
                            divisions: 9,
                            label: _quality.toString(),
                            onChanged: (value) {
                              setState(() {
                                _quality = value.toInt();
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Frame Interval: $_frameInterval ms',
                            style: const TextStyle(color: Colors.white),
                          ),
                          Slider(
                            value: _frameInterval.toDouble(),
                            min: 50,
                            max: 500,
                            divisions: 9,
                            label: _frameInterval.toString(),
                            onChanged: (value) {
                              setState(() {
                                _frameInterval = value.toInt();
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton(
                      onPressed:
                          _isConnected && !_isStreaming
                              ? _startVideoStream
                              : null,
                      child: const Text('开始流传输'),
                    ),
                    ElevatedButton(
                      onPressed: _isStreaming ? _stopVideoStream : null,
                      child: const Text('停止流传输'),
                    ),
                    ElevatedButton(
                      onPressed: !_isConnected ? _connectSocket : null,
                      child: const Text('重新连接'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class DetectionPainter extends CustomPainter {
  final List<dynamic> detections;
  final Size previewSize;
  final Size screenSize;

  DetectionPainter({
    required this.detections,
    required this.previewSize,
    required this.screenSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0
          ..color = Colors.red;

    final Paint textBgPaint =
        Paint()
          ..style = PaintingStyle.fill
          ..color = Colors.red.withOpacity(0.7);

    final textStyle = const TextStyle(color: Colors.white, fontSize: 14.0);

    for (final detection in detections) {
      // Scale detection coordinates to the screen size
      final double xmin =
          detection['xmin'] * screenSize.width / previewSize.width;
      final double ymin =
          detection['ymin'] * screenSize.height / previewSize.height;
      final double xmax =
          detection['xmax'] * screenSize.width / previewSize.width;
      final double ymax =
          detection['ymax'] * screenSize.height / previewSize.height;

      final Rect rect = Rect.fromLTRB(xmin, ymin, xmax, ymax);

      // Draw the bounding box
      canvas.drawRect(rect, paint);

      // Draw the label
      final String label =
          "${detection['name']} ${(detection['confidence'] * 100).toStringAsFixed(1)}%";
      final textSpan = TextSpan(text: label, style: textStyle);
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      // Draw text background
      canvas.drawRect(
        Rect.fromLTWH(
          xmin,
          ymin - textPainter.height,
          textPainter.width,
          textPainter.height,
        ),
        textBgPaint,
      );

      // Draw text
      textPainter.paint(canvas, Offset(xmin, ymin - textPainter.height));
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}
