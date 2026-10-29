import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'pdf_document_view.dart';
import 'package:webapp/services/dashboard_export_document_session.dart';
import 'package:webapp/services/docx_pdf_preview_service.dart';
import 'package:webapp/services/dashboard_docx_export_service.dart';
import 'package:webapp/services/dashboard_export_naming.dart';

/// Displays a PDF converted from the same DOCX bytes used for download.
class DashboardExportPreview extends StatefulWidget {
  const DashboardExportPreview({
    super.key,
    required this.payloads,
    this.documents,
    this.convertToPdf,
  }) : assert(payloads.length > 0);

  final List<DashboardDocxExportPayload> payloads;
  final DashboardExportDocumentSession? documents;
  final Future<Uint8List> Function(Uint8List)? convertToPdf;

  @override
  State<DashboardExportPreview> createState() => _DashboardExportPreviewState();
}

class _DashboardExportPreviewState extends State<DashboardExportPreview> {
  int _selectedIndex = 0;
  final Map<int, Future<Uint8List>> _pdfs = {};
  late final DashboardExportDocumentSession _documents;
  DocxPdfPreviewService? _converter;

  @override
  void initState() {
    super.initState();
    _documents = widget.documents ?? DashboardExportDocumentSession();
    if (widget.convertToPdf == null) _converter = DocxPdfPreviewService();
  }

  Future<Uint8List> _pdf(int index) => _pdfs.putIfAbsent(index, () async {
    final docx = await _documents.docxFor(widget.payloads[index]);
    return (widget.convertToPdf ?? _converter!.convert)(docx);
  });

  @override
  void dispose() {
    _converter?.close();
    if (widget.documents == null) _documents.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final payload = widget.payloads[_selectedIndex];
    return Dialog(
      insetPadding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(maxWidth: 1600),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox.expand(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 48,
              child: Padding(
                padding: const EdgeInsets.only(left: 4, right: 16),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Back to export',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const Text(
                      'Export Preview',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Tooltip(
                        message: dashboardExportFileName(payload.config),
                        child: Text(
                          dashboardExportFileName(payload.config),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (widget.payloads.length > 1)
              SizedBox(
                height: 40,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      for (var i = 0; i < widget.payloads.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(
                              widget.payloads[i].config.type.buttonLabel,
                            ),
                            selected: _selectedIndex == i,
                            visualDensity: VisualDensity.compact,
                            onSelected: (_) =>
                                setState(() => _selectedIndex = i),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            const Divider(height: 1),
            Expanded(
              child: FutureBuilder<Uint8List>(
                future: _pdf(_selectedIndex),
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Text(
                              snapshot.error is PdfPreviewException
                                  ? snapshot.error.toString()
                                  : 'Unable to build the PDF preview.',
                            ),
                          ),
                          TextButton(
                            onPressed: () => setState(() {
                              _pdfs.remove(_selectedIndex);
                            }),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    );
                  }
                  return PdfDocumentView(
                    key: ValueKey(_selectedIndex),
                    bytes: snapshot.requireData,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
