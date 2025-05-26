import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:face_detection/timer_progress_indicator.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:screenshot/screenshot.dart';

import 'camera_view.dart';
import 'cordinate_translator.dart';
import 'preview_image.dart';

class FaceDetectorScreen extends StatefulWidget {
  @override
  State<FaceDetectorScreen> createState() => _FaceDetectorScreenState();
}

class _FaceDetectorScreenState extends State<FaceDetectorScreen> {
  final GlobalKey _circleKey = GlobalKey();
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
        enableContours: true,
        enableLandmarks: true,
        enableClassification: true,
        minFaceSize: .9),
  );

  String? _text = "No Face Found";
  var _cameraLensDirection = CameraLensDirection.front;

  final ValueNotifier<bool> _faceInOval = ValueNotifier(false);

  ScreenshotController screenshotController = ScreenshotController();

  Rect? boundPainter;

  @override
  void dispose() {
    _faceDetector.close();
    _faceInOval.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white,
          title: Text("Scan Face"),
        ),
        backgroundColor: Colors.white,
        body: Column(
          children: [
            Expanded(
              child: SizedBox(
                height: 1,
              ),
            ),
            Center(
              child: CameraView(
                screenShotController: screenshotController,
                circleKey: _circleKey,
                onImage: _processImage,
                initialCameraLensDirection: _cameraLensDirection,
                onCameraLensDirectionChanged: (value) =>
                    _cameraLensDirection = value,
                faceInOval: _faceInOval,
              ),
            ),
            SizedBox(
              height: 20,
            ),
            ValueListenableBuilder<bool>(
                valueListenable: _faceInOval,
                builder: (c, value, _) {
                  return Column(
                    children: [
                      Text(
                        _text!,
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            color:
                                _faceInOval.value ? Colors.green : Colors.red),
                      ),
                    ],
                  );
                }),
            TimedProgressIndicator(
              faceInOval: _faceInOval,
              screenshotController: screenshotController,
              pictureTakenOther: (Uint8List image) {
                showImagePreview(
                    confirmUpload: () {}, image: image, context: context);
              },
            ),
            Expanded(
              child: SizedBox(
                height: 1,
              ),
            ),
            Expanded(
              child: SizedBox(
                height: 1,
              ),
            ),
          ],
        ));
  }


  /// This process the image
  Future<void> _processImage(InputImage inputImage, Size previewSize,
      CameraImage cameraImage, InputImageRotation rotation) async {
    final faces = await _faceDetector.processImage(inputImage);

    /// we return early if no face is detected or face is smiling or eyes not opened
    if (faces.isEmpty) {
      _text = "No Faces Found";
      _faceInOval.value = false;
      setState(() {});
    } else {
      if (faces.length > 1) {
        _text = "More Than One Face Detected";
        _faceInOval.value = false;
        setState(() {});
        return;
      }

      final face = faces[0];
      bool isRightFace = isFaceProperlyAligned(face);

      final isSmiling = (face.smilingProbability ?? 0.0) > 0.6;
      if (!isRightFace || isSmiling) {
        _text = "Keep Face Straight And Upright";
        _faceInOval.value = false;
        setState(() {});
        return;
      }

      final leftEyeOpen = (face.leftEyeOpenProbability ?? 0.4) > 0.7;
      final rightEyeOpen = (face.rightEyeOpenProbability ?? 0.4) > 0.7;

      final anyEyeClosed = !leftEyeOpen || !rightEyeOpen;

      if (anyEyeClosed) {
        _text = "Keep Eyes Open";
        _faceInOval.value = false;
        setState(() {});
        return;
      }

      final isNoseVisible = face.landmarks[FaceLandmarkType.noseBase] != null;

      final isMouthAvailable =
          face.landmarks[FaceLandmarkType.bottomMouth] != null &&
              face.landmarks[FaceLandmarkType.rightMouth] != null &&
              face.landmarks[FaceLandmarkType.leftMouth] != null;

      if (!isNoseVisible || !isMouthAvailable) {
        _text = "Nose And Mouth Unavailable";
        _faceInOval.value = false;
        setState(() {});
        return;
      }

      /// Now we check if the face is in oval
      _checkFaceInOval(
          faces[0], previewSize, inputImage.metadata!.rotation, inputImage);
    }
  }

  Rect? _getCircleBounds() {
    final RenderBox? renderBox =
        _circleKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return null;

    // Get the circle's position relative to the screen
    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    return Rect.fromLTWH(
      position.dx,
      position.dy,
      size.width,
      size.height,
    );
  }

  Rect convertBoundingBox({
    required Face face,
    required Size size,
    required Size imageSize,
    required CameraLensDirection cameraDirection,
    required InputImageRotation rotation,
  }) {
    final left = translateX(
        face.boundingBox.left, size, imageSize, rotation, cameraDirection);
    final top = translateY(
        face.boundingBox.top, size, imageSize, rotation, cameraDirection);
    final right = translateX(
        face.boundingBox.right, size, imageSize, rotation, cameraDirection);
    final bottom = translateY(
        face.boundingBox.bottom, size, imageSize, rotation, cameraDirection);

    var rect = Rect.fromLTRB(left, top, right, bottom);

    return rect;
  }

  bool isFaceUpright(Face face, {double maxTiltDegrees = 10}) {
    final double tilt = face.headEulerAngleZ ?? 0.0;
    return tilt.abs() <= maxTiltDegrees;
  }

  bool isFaceFacingForward(Face face, {double maxRotation = 10}) {
    final x = face.headEulerAngleX ?? 0.0;
    final y = face.headEulerAngleY ?? 0.0;
    return x.abs() <= maxRotation && y.abs() <= maxRotation;
  }

  bool isFaceProperlyAligned(Face face) {
    return isFaceUpright(face) && isFaceFacingForward(face);
  }

  void _checkFaceInOval(Face face, Size previewSize,
      InputImageRotation rotation, InputImage inputImage) {

    /// First we want to get the bounds of the circle relative to the screen
    final circleBounds = _getCircleBounds();

    /// If for some reason it's null, we just return early
    if (circleBounds == null) {
      boundPainter = null;
      _text = "Keep Face In The Center";
      _faceInOval.value = false;
      return;
    }

    /// Next we want to get the rect of the face relative to the screen.
    /// [face.boundingBox] is the rect relative to the camera preview size and not the screen
    Rect faceBoxOnScreen = convertBoundingBox(
      face: face,
      imageSize: inputImage.metadata!.size,
      size: MediaQuery.of(context).size,
      cameraDirection: _cameraLensDirection,
      rotation: rotation,
    );


    /// Next we want to check if the the image is centered properly on the oval rect
    final isInCircle = isRectBCenteredWithSimilarity(
        rectA: circleBounds,
        rectB: faceBoxOnScreen,
        minSimilarity: .2,
        minCoverage: .55,
        expandPercent: .2);

    switch (isInCircle) {
      case FaceStatus.tooBig:
        _text = "Face is too big";
        _faceInOval.value = false;

      case FaceStatus.tooSmall:
        _text = "Face is too small";
        _faceInOval.value = false;
      case FaceStatus.notInCenter:
        _text = "Face is not in center";
        _faceInOval.value = false;
      case FaceStatus.success:
        _text = "Hold Still";
        _faceInOval.value = true;
    }
    setState(() {});
  }

  Rect expandRect(Rect rect, double percent) {
    final dx = rect.width * percent / 2;
    final dy = rect.height * percent / 2;
    return Rect.fromLTRB(
      rect.left - dx,
      rect.top - dy,
      rect.right + dx,
      rect.bottom + dy,
    );
  }

  Rect expandRectCustom(
    Rect rect, {
    double horizontalPercent = .3,
    double verticalPercent = .55,
  }) {
    final dx = rect.width * horizontalPercent / 2;
    final dy = rect.height * verticalPercent / 2;
    return Rect.fromLTRB(
      rect.left - dx,
      rect.top - dy,
      rect.right + dx,
      rect.bottom + dy,
    );
  }

  FaceStatus isRectBCenteredWithSimilarity({
    required Rect rectA,
    required Rect rectB,
    double expandPercent = 0.2,
    double minSimilarity = 0.9,
    double minCoverage = 0.6,
  }) {
    /// first we need to expand the image/face rect because the bounding box provided by the ml_kit only detects faces
    /// and does not account for head/hairstyle, so we are just to expand a bit
    final Rect expandedFaceBounds =
        expandRectCustom(rectB, verticalPercent: .35, horizontalPercent: .25);

    /// Ensure the newly expanded box is not too big
    if (expandedFaceBounds.width > rectA.width ||
        expandedFaceBounds.height > rectA.height) {
      return FaceStatus.tooBig;
    }

    /// create an ideal rectB using rect a center and expandedFaceBounds properties
    final Rect idealRectB = Rect.fromCenter(
      center: rectA.center,
      width: expandedFaceBounds.width,
      height: expandedFaceBounds.height,
    );

    //
    final double areaB = idealRectB.width * idealRectB.height;
    final double areaA = rectA.width * rectA.height;
    final double coverageRatio = areaB / areaA;
    if (coverageRatio < minCoverage) {
      return FaceStatus.tooSmall;
    }


    final Offset centerA = rectA.center;
    final Offset centerB = expandedFaceBounds.center;
    final double centerDistance = (centerA - centerB).distance;
    final double centerTolerance = rectA.shortestSide * 0.8;
    if (centerDistance > centerTolerance) {
      return FaceStatus.notInCenter;
    }


    double similarity(double a, double b) {
      if (a == 0 && b == 0) return 1.0;
      final diff = (a - b).abs();
      final maxSide = a.abs() > b.abs() ? a.abs() : b.abs();
      return 1.0 - (diff / maxSide); // closer to 1 = more similar
    }

    final double leftSim = similarity(expandedFaceBounds.left, idealRectB.left);
    final double topSim = similarity(expandedFaceBounds.top, idealRectB.top);
    final double rightSim =
        similarity(expandedFaceBounds.right, idealRectB.right);
    final double bottomSim =
        similarity(expandedFaceBounds.bottom, idealRectB.bottom);


    final double avgSimilarity =
        (leftSim + topSim + rightSim + bottomSim) / 4.0;

    return avgSimilarity >= minSimilarity
        ? FaceStatus.success
        : FaceStatus.notInCenter;
  }
}

enum FaceStatus { tooBig, tooSmall, notInCenter, success }
