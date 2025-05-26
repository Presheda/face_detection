import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:screenshot/screenshot.dart';



class CameraView extends StatefulWidget {
  const CameraView({
    Key? key,
    required this.onImage,
    this.onCameraFeedReady,
    this.onDetectorViewModeChanged,
    this.onCameraLensDirectionChanged,
    this.initialCameraLensDirection = CameraLensDirection.front,
    required this.circleKey,
    required this.faceInOval,
    required this.screenShotController,
  }) : super(key: key);

  final Function(InputImage inputImage, Size previewSize, CameraImage image,
      InputImageRotation rotation) onImage;
  final VoidCallback? onCameraFeedReady;
  final VoidCallback? onDetectorViewModeChanged;
  final Function(CameraLensDirection direction)? onCameraLensDirectionChanged;
  final CameraLensDirection initialCameraLensDirection;

  final GlobalKey circleKey;

  final ValueNotifier<bool> faceInOval;

  final ScreenshotController screenShotController;


  @override
  State<CameraView> createState() => _CameraViewState();
}

class _CameraViewState extends State<CameraView> {
  static List<CameraDescription> _cameras = [];
  CameraController? _controller;
  int _cameraIndex = -1;

  bool _changingCameraLens = false;

  @override
  void initState() {
    super.initState();

    _initialize();
  }

  void _initialize() async {
    if (_cameras.isEmpty) {
      _cameras = await availableCameras();
    }
    for (var i = 0; i < _cameras.length; i++) {
      if (_cameras[i].lensDirection == widget.initialCameraLensDirection) {
        _cameraIndex = i;
        break;
      }
    }
    if (_cameraIndex != -1) {
      _startLiveFeed();
    }
  }

  @override
  void dispose() {
    _stopLiveFeed();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _liveFeedBody();
  }

  Widget _liveFeedBody() {
    if (_cameras.isEmpty) return Container();
    if (_controller == null) return Container();
    if (_controller?.value.isInitialized == false) return Container();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ValueListenableBuilder<bool>(
            valueListenable: widget.faceInOval,
            builder: (c, value, _) {
              return Container(
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: value ? Colors.green : Colors.red, width: 4)),
                child: ClipOval(
                  child: Screenshot(
                    controller: widget.screenShotController,
                    child: SizedBox(
                      width: MediaQuery.of(context).size.width * .8,
                      height: MediaQuery.of(context).size.width * .8,
                      child: _changingCameraLens
                          ? const Center(child: Text('Changing camera lens'))
                          : FittedBox(
                              fit: BoxFit
                                  .cover, // This maintains aspect ratio and fills the circle
                              key: widget.circleKey,
                              child: SizedBox(
                                width: _controller!.value.previewSize!.height,
                                height: _controller!.value.previewSize!.width,
                                child: CameraPreview(
                                  _controller!,
                                  // child: widget.customPaint,
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
              );
            }),
        Align(
            alignment: Alignment.center,
            child: Padding(
              padding:  EdgeInsets.symmetric(
                horizontal: 20
              ),
              child: TextButton(onPressed: (){
                _switchLiveCamera();
              }, child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [


                  Icon(
                    Platform.isIOS
                        ? Icons.flip_camera_ios_outlined
                        : Icons.flip_camera_android_outlined,
                    size: 20,
                  ),
                  SizedBox(width: 10,),
                  Text(
                    "Switch Camera",
                    style: TextStyle(fontSize: 15),
                  )
                ],
              )),
            )),

      ],
    );
  }

  Future _startLiveFeed() async {
    final camera = _cameras[_cameraIndex];
    _controller = CameraController(
      camera,
      ResolutionPreset.high,

      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );

    _controller?.initialize().then((_) {
      if (!mounted) {
        return;
      }
      _controller?.startImageStream(_processCameraImage).then((value) {
        if (widget.onCameraLensDirectionChanged != null) {
          widget.onCameraLensDirectionChanged!(camera.lensDirection);
        }
      });
      setState(() {});
    });
  }

  Future _stopLiveFeed() async {
    await _controller?.stopImageStream();
    await _controller?.dispose();
    _controller = null;
  }

  Future _switchLiveCamera() async {
    setState(() => _changingCameraLens = true);
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;

    await _stopLiveFeed();
    await _startLiveFeed();
    setState(() => _changingCameraLens = false);
  }

  void _processCameraImage(CameraImage image) {
    final inputImage = _inputImageFromCameraImage(image);
    final rotation = _inputRotationCameraImage(image);
    if (inputImage == null || rotation == null) {

      return;
    }
    widget.onImage(
        inputImage, _controller!.value.previewSize!, image, rotation);
  }

  final _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    if (_controller == null) return null;

    // get image rotation
    // it is used in android to convert the InputImage from Dart to Java: https://github.com/flutter-ml/google_ml_kit_flutter/blob/master/packages/google_mlkit_commons/android/src/main/java/com/google_mlkit_commons/InputImageConverter.java
    // `rotation` is not used in iOS to convert the InputImage from Dart to Obj-C: https://github.com/flutter-ml/google_ml_kit_flutter/blob/master/packages/google_mlkit_commons/ios/Classes/MLKVisionImage%2BFlutterPlugin.m
    // in both platforms `rotation` and `camera.lensDirection` can be used to compensate `x` and `y` coordinates on a canvas: https://github.com/flutter-ml/google_ml_kit_flutter/blob/master/packages/example/lib/vision_detector_views/painters/coordinates_translator.dart
    final camera = _cameras[_cameraIndex];
    final sensorOrientation = camera.sensorOrientation;
    // print(
    //     'lensDirection: ${camera.lensDirection}, sensorOrientation: $sensorOrientation, ${_controller?.value.deviceOrientation} ${_controller?.value.lockedCaptureOrientation} ${_controller?.value.isCaptureOrientationLocked}');
    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      var rotationCompensation =
          _orientations[_controller!.value.deviceOrientation];
      if (rotationCompensation == null) return null;
      if (camera.lensDirection == CameraLensDirection.front) {
        rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
      } else {
        rotationCompensation =
            (sensorOrientation - rotationCompensation + 360) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
    }
    if (rotation == null) return null;
    final format = InputImageFormatValue.fromRawValue(image.format.raw);

    if (format == null ||
        (Platform.isAndroid && format != InputImageFormat.nv21) ||
        (Platform.isIOS && format != InputImageFormat.bgra8888)) {
      return null;
    }

    if (image.planes.length != 1) return null;
    final plane = image.planes.first;

    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation, // used only in Android
        format: format, // used only in iOS
        bytesPerRow: plane.bytesPerRow, // used only in iOS
      ),
    );
  }

  InputImageRotation? _inputRotationCameraImage(CameraImage image) {
    if (_controller == null) return null;

    // get image rotation
    // it is used in android to convert the InputImage from Dart to Java: https://github.com/flutter-ml/google_ml_kit_flutter/blob/master/packages/google_mlkit_commons/android/src/main/java/com/google_mlkit_commons/InputImageConverter.java
    // `rotation` is not used in iOS to convert the InputImage from Dart to Obj-C: https://github.com/flutter-ml/google_ml_kit_flutter/blob/master/packages/google_mlkit_commons/ios/Classes/MLKVisionImage%2BFlutterPlugin.m
    // in both platforms `rotation` and `camera.lensDirection` can be used to compensate `x` and `y` coordinates on a canvas: https://github.com/flutter-ml/google_ml_kit_flutter/blob/master/packages/example/lib/vision_detector_views/painters/coordinates_translator.dart
    final camera = _cameras[_cameraIndex];
    final sensorOrientation = camera.sensorOrientation;
    // print(
    //     'lensDirection: ${camera.lensDirection}, sensorOrientation: $sensorOrientation, ${_controller?.value.deviceOrientation} ${_controller?.value.lockedCaptureOrientation} ${_controller?.value.isCaptureOrientationLocked}');
    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      var rotationCompensation =
          _orientations[_controller!.value.deviceOrientation];
      if (rotationCompensation == null) return null;
      if (camera.lensDirection == CameraLensDirection.front) {
        // front-facing
        rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
      } else {
        // back-facing
        rotationCompensation =
            (sensorOrientation - rotationCompensation + 360) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
      // print('rotationCompensation: $rotationCompensation');
    }
    if (rotation == null) return null;
    // print('final rotation: $rotation');

    // get image format
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    // validate format depending on platform
    // only supported formats:
    // * nv21 for Android
    // * bgra8888 for iOS
    if (format == null ||
        (Platform.isAndroid && format != InputImageFormat.nv21) ||
        (Platform.isIOS && format != InputImageFormat.bgra8888)) {
      return null;
    }

    return rotation;
  }
}
