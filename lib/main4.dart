import 'dart:async';
import 'dart:isolate';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:realtime_face_recognition/ML/Recognition.dart';
import 'ML/Recognizer.dart';

late List<CameraDescription> cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key? key}) : super(key: key);
  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  //dynamic controller;
  late Size size;
  late CameraDescription description = cameras[0];
  CameraLensDirection camDirec = CameraLensDirection.front;
  late List<Recognition> recognitions = [];

  //TODO declare face detector
  late CameraController controller;

  bool isDetecting = false;

  late IsolateImageConvertWorker _imageConvertWorker;

  @override
  void initState() {
    super.initState();
    createWorker();
    initCamera(cameras[0]);
  }

  void createWorker() async {
    _imageConvertWorker = await IsolateImageConvertWorker.create();
  }

  Future initCamera(CameraDescription cameraDescription) async {
// create a CameraController
    controller = CameraController(cameraDescription, ResolutionPreset.medium);
// Next, initialize the controller. This returns a Future.
    try {
      await controller.initialize().then((_) {
        if (!mounted) return;
        controller.startImageStream((image) async {
          if (!isDetecting) {
            isDetecting = true;

            // recognitions = await _faceRecognitionWorker.isolateRecognitionWithImage(image);
            recognitions = await FaceRecognitionWorker.recognitionWithImage(image,_imageConvertWorker);
            if(register && recognitions.isNotEmpty){
              showFaceRegistrationDialogue(recognitions[0].embeddings);
              register=false;
            }
            print("recognitionWithImage:$recognitions");

            setState(() {
              _scanResults = recognitions;
              isDetecting = false;
            });
          }
        });
        setState(() {});
      });
    } on CameraException catch (e) {
      debugPrint("camera error $e");
    }
  }

  //TODO code to initialize the camera feed
  initializeCamera() async {}

  //TODO close all resources
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  //TODO face detection on a frame
  dynamic _scanResults;
  bool register = false;

  //TODO Face Registration Dialogue
  TextEditingController textEditingController = TextEditingController();
  showFaceRegistrationDialogue(embeddings) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Face Registration", textAlign: TextAlign.center),
        alignment: Alignment.center,
        content: SizedBox(
          height: 300,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(
                height: 40,
              ),
              SizedBox(
                width: 200,
                child: TextField(
                    controller: textEditingController, decoration: const InputDecoration(fillColor: Colors.white, filled: true, hintText: "Enter Name")),
              ),
              const SizedBox(
                height: 40,
              ),
              ElevatedButton(
                  onPressed: () {
                    MyFaceFaceRecognition(_imageConvertWorker).registerFaceInDB(textEditingController.text, embeddings);
                    textEditingController.text = "";
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text("Face Registered"),
                    ));
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, minimumSize: const Size(200, 40)),
                  child: const Text("Register"))
            ],
          ),
        ),
        contentPadding: EdgeInsets.zero,
      ),
    );
  }

  // TODO Show rectangles around detected faces
  Widget buildResult() {
    if (_scanResults == null || controller == null || !controller.value.isInitialized) {
      return const Center(child: Text('Camera is not initialized'));
    }
    final Size imageSize = Size(
      controller.value.previewSize!.height,
      controller.value.previewSize!.width,
    );
    CustomPainter painter = FaceDetectorPainter(imageSize, _scanResults, camDirec);
    return CustomPaint(
      painter: painter,
    );
  }

  //TODO toggle camera direction
  void _toggleCameraDirection() async {
    if (camDirec == CameraLensDirection.back) {
      camDirec = CameraLensDirection.front;
      description = cameras[0];
    } else {
      camDirec = CameraLensDirection.back;
      description = cameras[0];
    }
    await controller.stopImageStream();
    setState(() {
      controller;
    });

    initializeCamera();
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> stackChildren = [];
    size = MediaQuery.of(context).size;
    if (controller != null) {
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
    }

    //TODO View for displaying the bar to switch camera direction or for registering faces
    stackChildren.add(Positioned(
      top: size.height - 140,
      left: 0,
      width: size.width,
      height: 80,
      child: Card(
        margin: const EdgeInsets.only(left: 20, right: 20),
        color: Colors.blue,
        child: Center(
          child: Container(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.cached,
                        color: Colors.white,
                      ),
                      iconSize: 40,
                      color: Colors.black,
                      onPressed: () {
                        _toggleCameraDirection();
                      },
                    ),
                    Container(
                      width: 30,
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.face_retouching_natural,
                        color: Colors.white,
                      ),
                      iconSize: 40,
                      color: Colors.black,
                      onPressed: () {
                        register = true;
                      },
                    )
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ));

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

// 画人脸到屏幕
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

class IsolateImageConvertWorker {
  final ReceivePort rp;
  final Stream<dynamic> broadcastRp;
  final SendPort communicatorSendPort;

  IsolateImageConvertWorker({
    required this.rp,
    required this.broadcastRp,
    required this.communicatorSendPort,
  });

  Future<img.Image> getYUV420RotateImage(CameraImage cameraImage) async {
    communicatorSendPort.send(cameraImage);
    return broadcastRp.takeWhile((element) => element is img.Image).cast<img.Image>().take(1).first;
  }

  static Future<IsolateImageConvertWorker> create() async {
    final rp = ReceivePort();
    Isolate.spawn(_communicator, rp.sendPort);
    //
    final broadcastRp = rp.asBroadcastStream();
    final SendPort communicatorSendPort = await broadcastRp.first;
    //
    return IsolateImageConvertWorker(
      rp: rp,
      broadcastRp: broadcastRp,
      communicatorSendPort: communicatorSendPort,
    );
  }

  static _communicator(SendPort sp) async {
    final rp = ReceivePort();
    sp.send(rp.sendPort);

    final messages = rp.takeWhile((element) => element is CameraImage).cast<CameraImage>();

    await for (final message in messages) {
      final result = img.copyRotate(_convertYUV420ToImage(message), angle: 270);
      sp.send(result);
      continue;
    }
  }

  static img.Image _convertYUV420ToImage(CameraImage cameraImage) {
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

        image.data!.setPixelR(w, h, _yuv2rgb(y, u, v)); //= yuv2rgb(y, u, v);
      }
    }
    return image;
  }

  static int _yuv2rgb(int y, int u, int v) {
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

class FaceRecognitionWorker {

  static Future<List<Recognition>> recognitionWithImage(CameraImage cameraImage,IsolateImageConvertWorker imageConvertWorker) async {
    print("do recognitionWithImage");

    final time1 = DateTime.now().millisecondsSinceEpoch;

    final WriteBuffer allBytes = WriteBuffer();
    for (final Plane plane in cameraImage.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();
    final Size imageSize = Size(cameraImage.width.toDouble(), cameraImage.height.toDouble());
    final imageRotation = InputImageRotationValue.fromRawValue(270);
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
    // 检测人脸
    final time2 = DateTime.now().millisecondsSinceEpoch;
    List<Face> cropImage = await MyFaceDetector.getFaceFromImage(inputImage);
    final time3 = DateTime.now().millisecondsSinceEpoch;
    //
    for (Face face in cropImage) {
      print("count=${(face.boundingBox.toString())}");
    }
    // 识别人脸
    List<Recognition> recognitions = await MyFaceFaceRecognition(imageConvertWorker).getFaceRecognitionFromFaces(cropImage, cameraImage);
    final time4 = DateTime.now().millisecondsSinceEpoch;
    print("processData time:${time2 - time1} processImage time:${time3 - time2} Recognition time:${time4 - time3}");

    return recognitions;
  }
}

class MyFaceDetector {
  static FaceDetector detector = FaceDetector(options: FaceDetectorOptions(performanceMode: FaceDetectorMode.fast));
  static Future<List<Face>> getFaceFromImage(InputImage inputImage) async {
    List<Face> cropImage = await detector.processImage(inputImage);
    return cropImage;
  }
}

class MyFaceFaceRecognition {
  static final Recognizer _recognizer = Recognizer();
  final IsolateImageConvertWorker imageConvertWorker;

  MyFaceFaceRecognition(this.imageConvertWorker);

  Future<List<Recognition>> getFaceRecognitionFromFaces(List<Face> faces, CameraImage cameraImage) async{
    final time1 = DateTime.now().millisecondsSinceEpoch;

    List<Recognition> recognitions = [];
    // 耗时严重
    img.Image image = await imageConvertWorker.getYUV420RotateImage(cameraImage);

    final time2 = DateTime.now().millisecondsSinceEpoch;
    print("getFaceRecognitionFromFaces time1:${time2 - time1}");
    for (Face face in faces) {
      final time3 = DateTime.now().millisecondsSinceEpoch;
      Rect faceRect = face.boundingBox;
      img.Image croppedFace =
      img.copyCrop(image, x: faceRect.left.toInt(), y: faceRect.top.toInt(), width: faceRect.width.toInt(), height: faceRect.height.toInt());
      // recognitions.add(Recognition("", face.boundingBox, [], -5));
      final time4 = DateTime.now().millisecondsSinceEpoch;
      Recognition recognizer = _recognizer.recognize(croppedFace, face.boundingBox);
      recognitions.add(recognizer);
      final time5 = DateTime.now().millisecondsSinceEpoch;
      print("getFaceRecognitionFromFaces time3:${time4 - time3} time4:${time5 - time4}");
    }
    return recognitions;
  }

  registerFaceInDB(String name, List<double> embedding) {
    _recognizer.registerFaceInDB(name, embedding);
  }
}
