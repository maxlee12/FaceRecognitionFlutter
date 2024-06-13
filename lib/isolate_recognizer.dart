import 'dart:async';
import 'dart:isolate';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:realtime_face_recognition/ML/Recognition.dart';

import 'ML/Recognizer.dart';

enum IsolateRecognizerState {
  idle,
  loading,
}

class Example {
  final ReceivePort _receivePort = ReceivePort();
  SendPort? _sendPort;

  Example() {
    // 接收识别数据
    _receivePort.listen((message) {
      if (message is SendPort) {
        _sendPort = message;
      }
      // 识别结果
      if (message is Recognition) {}
    });
    // start
    IsolateRecognizer.startRecognizer(_receivePort.sendPort);
  }

  // 发送识别数据
  void sendRecognizeData(RecognizeData data) {
    _sendPort?.send(data);
  }
}

class RecognizeData {
  final Recognizer recognizer;
  final CameraImage cameraImage;
  final CameraDescription camera;

  RecognizeData({
    required this.cameraImage,
    required this.camera,
    required this.recognizer,
  });
}

class ExampleWorker {
  RecognizerWorker? _recognizerWorker;

  Future<List<Recognition>> requestWithRecognizeData(RecognizeData data) async {
    _recognizerWorker ??= await RecognizerWorker.create();
    return _recognizerWorker!.getRecognizeResult(data);
  }
}

class RecognizerWorker {
  final ReceivePort rp;
  final Stream<dynamic> broadcastRp;
  final SendPort communicatorSendPort;

  RecognizerWorker({
    required this.rp,
    required this.broadcastRp,
    required this.communicatorSendPort,
  });

  static Future<RecognizerWorker> create() async {
    final rp = ReceivePort();
    Isolate.spawn(
      _communicator,
      rp.sendPort,
    );

    final broadcastRp = rp.asBroadcastStream();
    final SendPort communicatorSendPort = await broadcastRp.first;

    return RecognizerWorker(
      rp: rp,
      broadcastRp: broadcastRp,
      communicatorSendPort: communicatorSendPort,
    );
  }

  Future<List<Recognition>> getRecognizeResult(RecognizeData data) async {
    print("getRecognizeResult");
    communicatorSendPort.send(data);
    return broadcastRp.takeWhile((element) => element is List<Recognition>).cast<List<Recognition>>().take(1).first;
  }

  static _communicator(SendPort sp) async {
    final faceRecognizer = FaceRecognizer();
    final rp = ReceivePort();
    sp.send(rp.sendPort);
    final messages = rp.takeWhile((element) => element is RecognizeData).cast<RecognizeData>();

    await for (final message in messages) {
      print("message:$message");
      List<Recognition> result = await faceRecognizer.recognizerWith(message.cameraImage, message.camera,message.recognizer);
      sp.send(result);
      continue;
    }
  }
}

class IsolateRecognizer {
  static IsolateRecognizer? _isolateRecognizer;
  static final _receivePort = ReceivePort();
  static bool _busy = false;
  //
  static Isolate? _isolate;
  static FaceRecognizer? _faceRecognizer;

  static startRecognizer(SendPort sendPort) {
    _faceRecognizer = FaceRecognizer();
    sendPort.send(_receivePort.sendPort);
    Isolate.spawn(_mainIsolate, sendPort, debugName: "IsolateRecognizer").then((value) {
      _isolate = value;
    });
  }

  // 要为静态方法
  static Future<void> _mainIsolate(SendPort sendPort) async {
    print("IsolateRecognizer spawn _mainIsolate");
    _receivePort.listen((message) {
      print("IsolateRecognizer listen:$message");
      //
      if (message is RecognizeData) {
        if (_isolateRecognizer != null) {
          if (!_busy) {
            _busy = true;
            _faceRecognizer?.recognizerWith(message.cameraImage, message.camera,Recognizer()).then((value) {
              sendPort.send(value);
              _busy = false;
            });
          }
        }
      }
    });
  }

  static Future<void> close() async {
    _isolate?.kill();
  }
}

class FaceRecognizer {
  late FaceDetector detector;
  late Recognizer _recognizer;
  List<Recognition> recognitions = [];
  CameraLensDirection camDirec = CameraLensDirection.front;

  bool inited = false;

  FaceRecognizer() {
    detector = FaceDetector(options: FaceDetectorOptions(performanceMode: FaceDetectorMode.fast));

  }

  Future<List<Recognition>> recognizerWith(CameraImage cameraImage, CameraDescription camera,Recognizer recognizer) async {
    _recognizer = recognizer;
    if (!inited) {
      await Future.delayed(const Duration(seconds: 3));
      inited = true;
    }

    print("object" + cameraImage.format.toString());

    final WriteBuffer allBytes = WriteBuffer();
    for (final Plane plane in cameraImage.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();
    final Size imageSize = Size(cameraImage.width.toDouble(), cameraImage.height.toDouble());
    final imageRotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation);
    // if (imageRotation == null) return;

    final inputImageFormat = InputImageFormatValue.fromRawValue(cameraImage.format.raw);
    // if (inputImageFormat == null) return null;

    final planeData = cameraImage.planes.map(
      (Plane plane) {
        return InputImagePlaneMetadata(
          bytesPerRow: plane.bytesPerRow,
          height: plane.height,
          width: plane.width,
        );
      },
    ).toList();

    final inputImageData = InputImageData(
      size: imageSize,
      imageRotation: imageRotation!,
      inputImageFormat: inputImageFormat!,
      planeData: planeData,
    );

    final inputImage = InputImage.fromBytes(bytes: bytes, inputImageData: inputImageData);

    List<Face> cropImage = await detector.processImage(inputImage);
    for (Face face in cropImage) {
      print("count=${(face.boundingBox.toString())}");
    }

    _performFaceRecognition(cropImage, cameraImage);

    return recognitions;
  }

  _performFaceRecognition(List<Face> faces, CameraImage cameraImage) {
    recognitions.clear();
    //TODO convert CameraImage to Image and rotate it so that our frame will be in a portrait
    img.Image image = Utils.convertYUV420ToImage(cameraImage);
    image = img.copyRotate(image, angle: camDirec == CameraLensDirection.front ? 270 : 90);

    for (Face face in faces) {
      Rect faceRect = face.boundingBox;
      img.Image croppedFace =
          img.copyCrop(image, x: faceRect.left.toInt(), y: faceRect.top.toInt(), width: faceRect.width.toInt(), height: faceRect.height.toInt());
      Recognition recognizer = _recognizer.recognize(croppedFace, face.boundingBox);
      recognitions.add(recognizer);
    }
  }
}

class Utils {
  static img.Image convertYUV420ToImage(CameraImage cameraImage) {
    final width = cameraImage.width;
    final height = cameraImage.height;

    final yRowStride = cameraImage.planes[0].bytesPerRow;
    final uvRowStride = cameraImage.planes[1].bytesPerRow;
    final uvPixelStride = cameraImage.planes[1].bytesPerPixel!;

    final image = img.Image(width: width, height: height);

    for (var w = 0; w < width; w++) {
      for (var h = 0; h < height; h++) {
        final uvIndex = uvPixelStride * (w / 2).floor() + uvRowStride * (h / 2).floor();
        final index = h * width + w;
        final yIndex = h * yRowStride + w;

        final y = cameraImage.planes[0].bytes[yIndex];
        final u = cameraImage.planes[1].bytes[uvIndex];
        final v = cameraImage.planes[2].bytes[uvIndex];

        image.data!.setPixelR(w, h, yuv2rgb(y, u, v)); //= yuv2rgb(y, u, v);
      }
    }
    return image;
  }

  static int yuv2rgb(int y, int u, int v) {
    // Convert yuv pixel to rgb
    var r = (y + v * 1436 / 1024 - 179).round();
    var g = (y - u * 46549 / 131072 + 44 - v * 93604 / 131072 + 91).round();
    var b = (y + u * 1814 / 1024 - 227).round();

    // Clipping RGB values to be inside boundaries [ 0 , 255 ]
    r = r.clamp(0, 255);
    g = g.clamp(0, 255);
    b = b.clamp(0, 255);

    return 0xff000000 | ((b << 16) & 0xff0000) | ((g << 8) & 0xff00) | (r & 0xff);
  }
}
