import 'package:optiguide_application/utils/detection_painter.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

class VideoStreamPage extends StatefulWidget {
  final CameraDescription camera;

  const VideoStreamPage({Key? key, required this.camera}) : super(key: key);

  @override
  _VideoStreamPageState createState() => _VideoStreamPageState();
}

class _VideoStreamPageState extends State<VideoStreamPage>
    with WidgetsBindingObserver {
  // 摄像头控制器
  late CameraController _cameraController;

  // Socket连接
  io.Socket? _socket;

  // 状态变量
  bool _isInitialized = false;
  bool _isConnected = false;
  bool _isStreaming = false;

  // 服务器地址
  String _serverAddress = '192.168.6.120:5000';
  TextEditingController _serverController = TextEditingController();

  // 视频流参数
  int _quality = 85; // JPEG压缩质量
  int _frameInterval = 150; // 帧间隔（毫秒）

  // 性能统计
  int _framesCount = 0;
  double _clientFps = 0;
  double _serverFps = 0;
  // String _lastServerTimestamp = '';
  String _lastImageSize = '';

  // 检测结果
  List<dynamic> _detections = [];

  // 定时器
  Timer? _frameTimer;
  Timer? _statsTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _serverController.text = _serverAddress;

    // 初始化摄像头
    _initializeCamera();

    // 启动FPS统计定时器
    _startStatsTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_cameraController.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _stopVideoStream();
      _disconnectSocket();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  // 初始化摄像头
  Future<void> _initializeCamera() async {
    _cameraController = CameraController(
      widget.camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    try {
      await _cameraController.initialize();

      // 设置摄像头曝光和对焦模式
      await _cameraController.setExposureMode(ExposureMode.auto);
      await _cameraController.setFocusMode(FocusMode.auto);

      setState(() {
        _isInitialized = true;
      });

      // 自动连接服务器
      _connectSocket();
    } catch (e) {
      debugPrint('摄像头初始化错误: $e');
    }
  }

  // 连接到WebSocket服务器
  void _connectSocket() {
    if (_socket != null) {
      _socket!.disconnect();
      _socket!.dispose();
    }

    try {
      final serverUrl = 'http://$_serverAddress';
      debugPrint('正在连接服务器: $serverUrl');

      _socket = io.io(serverUrl, <String, dynamic>{
        'transports': ['websocket'],
        'autoConnect': true,
        'reconnection': true,
        'reconnectionAttempts': 5,
        'reconnectionDelay': 1000,
        'reconnectionDelayMax': 5000,
        'timeout': 20000,
      });

      // 连接事件
      _socket!.onConnect((_) {
        debugPrint('与服务器连接成功');
        setState(() {
          _isConnected = true;
        });
      });

      // 服务器消息
      _socket!.on('message', (data) {
        debugPrint('服务器消息: $data');
      });

      _socket!.on('processedFrame', (data) {
        setState(() {
          // _lastServerTimestamp = data['timestamp'] ?? '';
          _serverFps = double.tryParse('${data['fps']}') ?? 0;
          _lastImageSize = data['size'] ?? '';
        });
      });

      // TODO: 检测结果
      // _socket!.on('detections', (data) {
      //   setState(() {
      //     _detections = data['detections'] ?? [];
      //   });
      // });

      // 服务器统计信息
      _socket!.on('serverStats', (data) {
        // 更新服务器统计数据
        debugPrint('服务器统计: $data');
      });

      // 断开连接事件
      _socket!.onDisconnect((_) {
        debugPrint('与服务器断开连接');
        setState(() {
          _isConnected = false;
          _isStreaming = false;
        });

        // 停止视频流
        _stopVideoStream();

        // TODO: 延迟5秒后尝试重新连接
        // Future.delayed(const Duration(seconds: 5), () {
        //   if (mounted && _socket != null && !_socket!.connected) {
        //     _connectSocket();
        //   }
        // });
      });

      _socket!.onError((error) {
        debugPrint('Socket错误: $error');
      });

      _socket!.on('connect_error', (error) {
        debugPrint('Socket连接错误: $error');
      });

      _socket!.on('connect_timeout', (timeout) {
        debugPrint('连接超时: $timeout');
      });

      _socket!.connect();
    } catch (e) {
      debugPrint('Socket连接错误: $e');
    }
  }

  // 断开Socket连接
  void _disconnectSocket() {
    if (_socket != null) {
      _socket!.disconnect();
    }

    setState(() {
      _isConnected = false;
      _isStreaming = false;
    });
  }

  // 开始传输
  void _startVideoStream() {
    if (_isStreaming || !_isConnected || !_isInitialized) return;

    setState(() {
      _isStreaming = true;
      _framesCount = 0;
    });

    // 启动定时发送帧的计时器
    _frameTimer = Timer.periodic(Duration(milliseconds: _frameInterval), (_) {
      _captureAndSendFrame();
    });
  }

  // 停止传输
  void _stopVideoStream() {
    _frameTimer?.cancel();
    _frameTimer = null;

    setState(() {
      _isStreaming = false;
    });
  }

  // 捕获并发送单帧
  Future<void> _captureAndSendFrame() async {
    if (!_isStreaming || !_isConnected || !_isInitialized) return;

    try {
      // 捕获图像
      final XFile imageFile = await _cameraController.takePicture();
      final bytes = await imageFile.readAsBytes();

      // 发送Base64编码的图像数据
      if (_socket != null && _socket!.connected) {
        final base64Image = 'data:image/jpeg;base64,${base64Encode(bytes)}';
        _socket!.emit('videoFrame', {'frame': base64Image});

        // 更新帧计数
        _framesCount++;
      }
    } catch (e) {
      debugPrint('捕获或发送帧错误: $e');
    }
  }

  // 启动统计定时器
  void _startStatsTimer() {
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          // 计算客户端FPS
          _clientFps = _framesCount.toDouble();
          _framesCount = 0;
        });
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopVideoStream();
    _frameTimer?.cancel();
    _statsTimer?.cancel();
    _cameraController.dispose();
    _socket?.disconnect();
    _socket?.dispose();
    _serverController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OptiGuide'),
        actions: [
          // 连接状态指示器
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
          // 摄像头预览区域
          Expanded(
            child:
                _isInitialized
                    ? Stack(
                      fit: StackFit.expand,
                      children: [
                        // 摄像头预览
                        CameraPreview(_cameraController),

                        // 检测结果绘制
                        if (_detections.isNotEmpty)
                          CustomPaint(
                            painter: DetectionPainter(
                              detections: _detections,
                              previewSize: _cameraController.value.previewSize!,
                              screenSize: MediaQuery.of(context).size,
                            ),
                          ),

                        // 状态信息显示
                        Positioned(
                          top: 10,
                          right: 10,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  'Client FPS: ${_clientFps.toStringAsFixed(1)}',
                                  style: const TextStyle(color: Colors.white),
                                ),
                                Text(
                                  'Server FPS: ${_serverFps.toStringAsFixed(1)}',
                                  style: const TextStyle(color: Colors.white),
                                ),
                                Text(
                                  'Size: $_lastImageSize',
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                    : const Center(child: CircularProgressIndicator()),
          ),

          // 控制面板
          Container(
            color: Colors.black54,
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 服务器地址输入
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _serverController,
                        decoration: const InputDecoration(
                          labelText: '服务器地址',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        style: const TextStyle(fontSize: 14),
                        onChanged: (value) {
                          _serverAddress = value;
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed:
                          _isConnected
                              ? null
                              : () {
                                _connectSocket();
                              },
                      child: const Text('连接'),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // 流参数控制
                Row(
                  children: [
                    // 质量控制滑块
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '质量: $_quality%',
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

                    // 帧间隔控制滑块
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '帧间隔: $_frameInterval ms',
                            style: const TextStyle(color: Colors.white),
                          ),
                          Slider(
                            value: _frameInterval.toDouble(),
                            min: 10,
                            max: 500,
                            divisions: 15,
                            label: _frameInterval.toString(),
                            onChanged: (value) {
                              setState(() {
                                _frameInterval = value.toInt();

                                // 若正在流传输，重启流以应用新设置
                                if (_isStreaming) {
                                  _stopVideoStream();
                                  _startVideoStream();
                                }
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // 控制按钮
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
                      onPressed:
                          !_isConnected
                              ? _connectSocket
                              : () {
                                _disconnectSocket();
                              },
                      child: Text(_isConnected ? '断开连接' : '重新连接'),
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
