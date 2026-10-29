# DOCX-to-PDF export preview

The app creates an editable DOCX from the existing templates, sends those exact
bytes here, and displays the returned PDF in the browser's PDF viewer. Download
continues to use the original DOCX bytes. No HTML-to-PDF reconstruction is used.

The converter uses LibreOffice Writer. Preview layout is fixed in the resulting
PDF. Word may reflow the editable DOCX if the recipient uses different fonts or
Word settings. Install the same licensed fonts used by the templates for closest
results. The container includes Liberation, Carlito and Caladea substitute fonts;
it does not include Microsoft's proprietary font files.

## Local development

Requirements: Node 22+ and LibreOffice (`soffice`), plus `unzip`.
On macOS the helper also finds `/Applications/LibreOffice.app`.

From the repository root:

```sh
zsh scripts/run_web_with_pdf_preview.zsh
```

Or use two terminals:

```sh
ALLOW_LOCALHOST=true node services/docx-preview/server.mjs
flutter run -d chrome --dart-define=DOCX_PREVIEW_ENDPOINT=http://127.0.0.1:8784/convert
```

For local Chrome debug, the app defaults to `http://127.0.0.1:8784/convert`
when no endpoint flag is supplied. The converter still needs to be running.
Production builds require an explicit endpoint.

Use `SOFFICE_BIN=/path/to/soffice` if LibreOffice is outside PATH. Add your current
`--web-port` to the Flutter command if you want to retain the same local origin.

## Container / production

The converter was deployed and verified on October 29, 2026 in project
`ptc-mvp`, region `asia-southeast1`:

- Health: `https://paltranco-docx-preview-3um7vhe3ca-as.a.run.app/health`
- Conversion: `https://paltranco-docx-preview-3um7vhe3ca-as.a.run.app/convert`

All four live export conversion tests passed against this endpoint. Production
CORS allows `https://paltranco.vercel.app`. Deploying the converter does not
rebuild or publish the Flutter frontend; supply this endpoint when building it:

```sh
export DOCX_PREVIEW_ENDPOINT=https://paltranco-docx-preview-3um7vhe3ca-as.a.run.app/convert
```

The frontend is statically hosted on Vercel and cannot run LibreOffice. Deploy
this separate converter first, then build the frontend with its `/convert` URL.
The Dockerfile can run on Cloud Run; the included deployment script defaults to
project `ptc-mvp`, region `asia-southeast1`. Running it creates a billed cloud
service and enables its public HTTP endpoint. It is not run automatically.

```sh
zsh services/docx-preview/deploy_cloud_run.zsh
DOCX_PREVIEW_ENDPOINT=https://YOUR-SERVICE.run.app/convert zsh scripts/deploy_web.zsh
```

The web deployment script also commits and pushes, matching the repository's
existing release workflow. To build without publishing:

```sh
flutter build web --release --dart-define=DOCX_PREVIEW_ENDPOINT=https://YOUR-SERVICE.run.app/convert
```

Configuration:

- `HOST`: defaults to `127.0.0.1`; the container sets `0.0.0.0`.
- `PORT`: defaults to `8784`; the container uses `8080`.
- `SOFFICE_BIN`: defaults to `soffice`.
- `CORS_ORIGINS`: comma-separated exact origins; default `https://paltranco.vercel.app`.
- `ALLOW_LOCALHOST=true`: permit local Chrome development on arbitrary HTTP ports.

POST raw DOCX bytes to `/convert` with the Word MIME type. Successful responses
are `application/pdf`; `/health` is available for liveness checks. Maximum input
is 20 MiB, expanded archive 200 MiB/5,000 entries, output 32 MiB; one conversion
runs at a time per process. Temporary files and isolated LibreOffice profiles are
removed after conversion. Responses disable HTTP caching and documents are not
written to a business database or logged. PDF preview needs a connection to this
service; DOCX download continues to work without the converter.

## Verification

```sh
node --test services/docx-preview/server.test.mjs
flutter test test/docx_pdf_preview_service_test.dart test/dashboard_export_preview_test.dart
```

For real conversions with a running local converter:

```sh
flutter test --dart-define=PDF_PREVIEW_TEST_ENDPOINT=http://127.0.0.1:8784/convert test/docx_pdf_live_conversion_test.dart
```
