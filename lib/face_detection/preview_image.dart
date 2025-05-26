import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';

Future<void> showImagePreview(
    {Uint8List? image,
    required Function() confirmUpload,
    required BuildContext context}) async {
  return showModalBottomSheet(
    context: context,
    builder: (
      context,
    ) {
      return Material(
        color: Colors.transparent,
        child: StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    Icon(
                      Icons.remove,
                      color: Colors.grey[600],
                    ),
                    ListTile(
                      contentPadding:
                          const EdgeInsets.only(left: 16, right: 16),
                      title: Text('Your Picture',
                          style: TextStyle(color: Colors.white)),
                    ),
                    Expanded(
                        child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: _PreviewPickedImage(image: image))),
                    if (image != null)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(15.0),
                            child: Text(
                              'Re-take Picture',
                              style:
                                  TextStyle(color: Colors.blue, fontSize: 14),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    if (image == null) const SizedBox(height: 20),
                    if (image != null) ...[
                      SafeArea(
                        child: Align(
                            alignment: Alignment.center,
                            child: ElevatedButton(
                              onPressed: () {
                                confirmUpload();
                              },
                              style: ButtonStyle(
                                  backgroundColor:
                                      MaterialStateProperty.all(Colors.red)),
                              child: Text(
                                "Confirm Upload",
                                style: TextStyle(color: Colors.white),
                              ),
                            )),
                      ),
                    ],
                    SizedBox(height: 40),
                  ],
                ),
              ),
            );
          },
        ),
      );
    },
  );
}

class _PreviewPickedImage extends StatefulWidget {
  final Uint8List? image;
  const _PreviewPickedImage({super.key, this.image});

  @override
  State<_PreviewPickedImage> createState() => _PreviewPickedImageState();
}

class _PreviewPickedImageState extends State<_PreviewPickedImage> {
  Uint8List? byteData;

  @override
  void initState() {
    // TODO: implement initState
    super.initState();

    convertByteData();
  }

  void convertByteData() async {
    byteData = widget.image; //await widget.image!.readAsBytes();

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (widget.image == null) {
      return Center(
          child: Center(
              child: Text(
        "Error No Image Selected",
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      )));
    }

    if (byteData == null) {
      return Center(
          child: Text(
        "Error No Image Selected",
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ));
    }

    return Semantics(
      label: 'custom_camera',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: MediaQuery.of(context).size.width * .5,
          height: MediaQuery.of(context).size.width * .5,
          child: Image.memory(
            byteData!,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}
