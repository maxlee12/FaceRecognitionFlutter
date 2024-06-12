import 'dart:io';
import 'dart:isolate';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:realtime_face_recognition/ML/Recognition.dart';

import '../ML/Recognizer.dart';

FaceDetector detector = FaceDetector(options: FaceDetectorOptions(performanceMode: FaceDetectorMode.fast));

Recognizer? recognizer;

bool isBusy = false;
Future<List<Recognition>> startRecognition(CameraImage cameraImage) async {
  print("isBusy:$isBusy");
  if (isBusy) return [];
  isBusy = true;
  List<Recognition> recognitions = [];
  InputImageRotation imageRotation = InputImageRotation.rotation270deg;
  print("object" + cameraImage.format.toString());

  final WriteBuffer allBytes = WriteBuffer();
  for (final Plane plane in cameraImage.planes) {
    allBytes.putUint8List(plane.bytes);
  }
  final bytes = allBytes.done().buffer.asUint8List();
  final Size imageSize = Size(cameraImage.width.toDouble(), cameraImage.height.toDouble());

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
  //
  img.Image image = convertYUV420ToImage(cameraImage);
  image = img.copyRotate(image, angle: 270);

  for (Face face in cropImage) {
    Rect faceRect = face.boundingBox;
    //TODO crop face
    img.Image croppedFace =
        img.copyCrop(image, x: faceRect.left.toInt(), y: faceRect.top.toInt(), width: faceRect.width.toInt(), height: faceRect.height.toInt());

    //TODO pass cropped face to face recognition model
    recognitions.add(recognizer!.recognize(croppedFace, face.boundingBox));
  }
  isBusy = false;
  return recognitions;
}

img.Image convertYUV420ToImage(CameraImage cameraImage) {
  final width = cameraImage.width;
  final height = cameraImage.height;
  final image = img.Image(width: width, height: height);

  if (cameraImage.planes.length > 1) {
    final yRowStride = cameraImage.planes[0].bytesPerRow;
    final uvRowStride = cameraImage.planes[1].bytesPerRow;
    final uvPixelStride = cameraImage.planes[1].bytesPerPixel!;
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
  }

  return image;
}

int yuv2rgb(int y, int u, int v) {
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

class MyTeHomePage extends StatefulWidget {
  final List<CameraDescription> cameras;
  MyTeHomePage({Key? key, required this.cameras}) : super(key: key);
  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyTeHomePage> {
  //TODO declare face detector
  late CameraController controller;
  List<Recognition> _scanResults = [];

  @override
  void initState() {
    super.initState();
    initCamera(widget.cameras[0]);
    //
    isBusy = true;
    recognizer = Recognizer();
    Future.delayed(const Duration(seconds: 3)).whenComplete(() {
      isBusy = false;
    });
  }

  Future initCamera(CameraDescription cameraDescription) async {
// create a CameraController
    controller = CameraController(cameraDescription, ResolutionPreset.high);
// Next, initialize the controller. This returns a Future.
    try {
      await controller.initialize().then((_) {
        if (!mounted) return;
        controller.startImageStream((image) async {
          // List<Recognition> rec = await compute(startRecognition,image);
          startRecognition(image).then((value) {
            print("startRecognition result:${value.length}");
            setState(() {
              _scanResults = value;
            });
          });
        });
        setState(() {});
      });
    } on CameraException catch (e) {
      debugPrint("camera error $e");
    }
  }

  //TODO close all resources
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Widget buildResult() {
    if (_scanResults == null || controller == null || !controller.value.isInitialized) {
      return const Center(child: Text('Camera is not initialized'));
    }
    final Size imageSize = Size(
      controller.value.previewSize!.height,
      controller.value.previewSize!.width,
    );
    CustomPainter painter = FaceDetectorPainter(imageSize, _scanResults, CameraLensDirection.front);
    return CustomPaint(
      painter: painter,
    );
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> stackChildren = [];
    Size size = MediaQuery.of(context).size;

    //TODO View for displaying the live camera footage
    stackChildren.add(
      Positioned(
        top: 0.0,
        left: 0.0,
        width: size.width,
        height: size.height,
        child: Container(
          child: (controller.value.isInitialized)
              ? AspectRatio(
                  aspectRatio: controller.value.aspectRatio,
                  child: CameraPreview(controller),
                )
              : Container(),
        ),
      ),
    );

    //TODO View for displaying rectangles around detected aces
    stackChildren.add(
      Positioned(top: 0.0, left: 0.0, width: size.width, height: size.height, child: buildResult()),
    );

    return SafeArea(
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Container(
            margin: const EdgeInsets.only(top: 0),
            color: Colors.black,
            child: Stack(
              children: stackChildren,
            )),
      ),
    );
  }
}

class FaceDetectorPainter extends CustomPainter {
  FaceDetectorPainter(this.absoluteImageSize, this.faces, this.camDire2);

  final Size absoluteImageSize;
  final List<Recognition> faces;
  CameraLensDirection camDire2;

  @override
  void paint(Canvas canvas, Size size) {
    final double scaleX = size.width / absoluteImageSize.width;
    final double scaleY = size.height / absoluteImageSize.height;

    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = Colors.indigoAccent;

    for (Recognition face in faces) {
      canvas.drawRect(
        Rect.fromLTRB(
          camDire2 == CameraLensDirection.front ? (absoluteImageSize.width - face.location.right) * scaleX : face.location.left * scaleX,
          face.location.top * scaleY,
          camDire2 == CameraLensDirection.front ? (absoluteImageSize.width - face.location.left) * scaleX : face.location.right * scaleX,
          face.location.bottom * scaleY,
        ),
        paint,
      );

      TextSpan span = TextSpan(style: const TextStyle(color: Colors.white, fontSize: 20), text: "${face.name}  ${face.distance.toStringAsFixed(2)}");
      TextPainter tp = TextPainter(text: span, textAlign: TextAlign.left, textDirection: TextDirection.ltr);
      tp.layout();
      tp.paint(canvas, Offset(face.location.left * scaleX, face.location.top * scaleY));
    }
  }

  @override
  bool shouldRepaint(FaceDetectorPainter oldDelegate) {
    return true;
  }
}
