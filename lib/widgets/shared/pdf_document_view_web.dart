// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;
import 'package:flutter/widgets.dart';

Widget buildPdfDocumentView(Uint8List bytes) => _BrowserPdfView(bytes: bytes);

class _BrowserPdfView extends StatefulWidget {
  const _BrowserPdfView({required this.bytes});
  final Uint8List bytes;
  @override
  State<_BrowserPdfView> createState() => _BrowserPdfViewState();
}

class _BrowserPdfViewState extends State<_BrowserPdfView> {
  static int _nextId = 0;
  late final String _viewType;
  late final String _objectUrl;
  late final html.IFrameElement _frame;

  @override
  void initState() {
    super.initState();
    _viewType = 'pdf-preview-${_nextId++}';
    _objectUrl = html.Url.createObjectUrlFromBlob(
      html.Blob([widget.bytes], 'application/pdf'),
    );
    _frame = html.IFrameElement()
      ..src = '$_objectUrl#view=FitH&toolbar=1'
      ..title = 'PDF preview of the exported Word document'
      ..style.border = '0'
      ..style.width = '100%'
      ..style.height = '100%';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (_) => _frame);
  }

  @override
  void dispose() {
    _frame.src = 'about:blank';
    html.Url.revokeObjectUrl(_objectUrl);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewType);
}
