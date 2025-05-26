import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:screenshot/screenshot.dart';

class TimedProgressIndicator extends StatefulWidget {
  final ValueNotifier<bool> faceInOval;
  final ScreenshotController screenshotController;
  final Function(Uint8List image) pictureTakenOther;
  const TimedProgressIndicator(
      {super.key,
      required this.faceInOval,
      required this.screenshotController,
      required this.pictureTakenOther});

  @override
  State<TimedProgressIndicator> createState() => _TimedProgressIndicatorState();
}

class _TimedProgressIndicatorState extends State<TimedProgressIndicator>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  static const int maxSeconds = 4;
  static const double minPictureSeconds = 2;
  static const double maxPictureSeconds = 3.5;
  Duration _elapsed = Duration.zero;
  bool _isRunning = false;

  Uint8List? image;
  bool capturing = false;
  @override
  void initState() {
    super.initState();
    _ticker = Ticker((Duration elapsed) {
      if (!_isRunning) return;

      _elapsed = elapsed;

      if (_elapsed.inMilliseconds >= maxSeconds * 1000) {
        _elapsed = Duration(milliseconds: maxSeconds * 1000);
        _ticker.stop();
        _isRunning = false;

        if (image != null) {
          widget.pictureTakenOther(image!);
        }
      }

      if (_elapsed.inMilliseconds >= minPictureSeconds * 1000 &&
          _elapsed.inMilliseconds <= maxPictureSeconds * 1000 &&
          image == null) {


        if (!capturing) {
          capturing = true;

          widget.screenshotController.capture().then((file) {
            if (file != null) {
              image = file;
            }
            capturing = false;
          });
        }

        setState(() {});
      }
    });

    widget.faceInOval.addListener(_ovalListener);
  }

  void _ovalListener() {
    if (widget.faceInOval.value) {
      _start();
    } else {
      _pause();
    }
  }

  void _start() {
    if (!_isRunning) {
      image = null;
      _isRunning = true;
      _ticker.start();
    }
  }

  void _pause() {
    if (_isRunning) {
      _isRunning = false;
      _elapsed = Duration.zero;
      _ticker.stop();
      setState(() {});
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    widget.faceInOval.removeListener(_ovalListener);
    super.dispose();
  }

  double get _progress {
    return _elapsed.inMilliseconds / (maxSeconds * 1000);
  }

  int get _percentage => (_progress * 100).clamp(0, 100).toInt();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: LinearProgressIndicator(value: _progress),
        ),
        const SizedBox(height: 16),
        Text('Capturing ( $_percentage% )',
            style: const TextStyle(fontSize: 18)),
      ],
    );
  }
}
