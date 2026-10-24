import "package:file_picker/file_picker.dart";
import "package:flutter/material.dart";
import "package:mobile_scanner/mobile_scanner.dart";

import "../../ui/theme.dart";

/// Scans a QR code with the camera (or reads one from a picture) and pops its text.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});
  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _done = false;
  String? _note;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _finish(String? text) {
    if (_done) return;
    final t = text?.trim() ?? "";
    if (t.isEmpty) return;
    _done = true;
    Navigator.pop(context, t);
  }

  Future<void> _fromGallery() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = res?.files.single.path;
    if (path == null) return;
    final capture = await _controller.analyzeImage(path);
    final code = capture?.barcodes
        .map((b) => b.rawValue)
        .whereType<String>()
        .firstOrNull;
    if (code == null) {
      if (mounted) setState(() => _note = "No QR code found in that picture");
    } else {
      _finish(code);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text("Scan a QR code",
            style: TextStyle(color: Colors.white, fontSize: 18)),
        actions: [
          IconButton(
            tooltip: "Flashlight",
            icon: const Icon(Icons.flashlight_on_rounded),
            onPressed: _controller.toggleTorch,
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: (cap) => _finish(cap.barcodes
                .map((b) => b.rawValue)
                .whereType<String>()
                .firstOrNull),
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Text(
                  error.errorCode == MobileScannerErrorCode.permissionDenied
                      ? "Camera access is off. Allow it in Android settings, or pick a picture of the QR code."
                      : "The camera isn't available. You can pick a picture of the QR code instead.",
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, height: 1.5),
                ),
              ),
            ),
          ),
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: c.brand, width: 3),
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
          Positioned(
            left: 18,
            right: 18,
            bottom: 26,
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_note != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(_note!,
                          style: const TextStyle(color: Colors.white70)),
                    ),
                  FilledButton.icon(
                    onPressed: _fromGallery,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text("Pick a picture"),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
