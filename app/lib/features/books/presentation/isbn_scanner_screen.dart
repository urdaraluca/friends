import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:friends/features/books/domain/isbn.dart';
import 'package:friends/l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Scans a book's barcode with the camera and pops its ISBN-13, or null.
///
/// Opened with [scanIsbn]. A book's barcode is an EAN-13 starting with 978
/// or 979; other barcodes (prices, shops' labels) are ignored.
class IsbnScannerScreen extends StatefulWidget {
  const new({super.key});

  @override
  State<IsbnScannerScreen> createState() => _IsbnScannerScreenState();
}

/// Opens the scanner; the ISBN-13 it read, or null when cancelled.
Future<String?> scanIsbn(BuildContext context) {
  if (kIsWeb) {
    // The browser's own BarcodeDetector: the CSP (script-src 'self') blocks
    // the CDN scripts of the other readers. Where the browser has none, the
    // scanner says so, and typing the ISBN still works.
    MobileScannerPlatform.instance.setWebBarcodeReader(
      WebBarcodeReader.barcodeDetector,
    );
  }
  return Navigator.of(context).push<String>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const IsbnScannerScreen(),
    ),
  );
}

class _IsbnScannerScreenState extends State<IsbnScannerScreen> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.ean13],
  );
  bool _done = false;

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final barcode in capture.barcodes) {
      final isbn = normalizeIsbn(barcode.rawValue ?? '');
      if (isbn != null) {
        _done = true;
        Navigator.of(context).pop(isbn);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.scanIsbn)),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => _ScannerError(error: error),
          ),
          IgnorePointer(
            child: Center(
              child: Container(
                width: 280,
                height: 140,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 3),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 32,
            child: Text(
              l10n.scanIsbnHelp,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.white,
                shadows: const [Shadow(blurRadius: 4)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScannerError extends StatelessWidget {
  const new({required this.error});

  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colors.surface,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.no_photography_outlined,
                size: 56,
                color: colors.outline,
              ),
              const SizedBox(height: 16),
              Text(
                error.errorCode == MobileScannerErrorCode.permissionDenied
                    ? l10n.cameraPermissionDenied
                    : l10n.cameraUnavailable,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.typeIsbnInstead),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
