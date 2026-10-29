import http from 'node:http';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {mkdtemp, mkdir, readFile, writeFile, rm, stat} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';

const runFile = promisify(execFile);
const DOCX = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
const MAX_DOCX = 20 * 1024 * 1024;
const MAX_PDF = 32 * 1024 * 1024;
class RequestError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}

async function readBody(request, maximum) {
  if (Number(request.headers['content-length'] || 0) > maximum) {
    throw new RequestError(413, 'Document too large');
  }
  const chunks = [];
  let length = 0;
  for await (const chunk of request) {
    length += chunk.length;
    if (length > maximum) throw new RequestError(413, 'Document too large');
    chunks.push(chunk);
  }
  return Buffer.concat(chunks);
}

export async function convertWithLibreOffice(docx) {
  const directory = await mkdtemp(join(tmpdir(), 'paltranco-preview-'));
  try {
    const source = join(directory, 'document.docx');
    await writeFile(source, docx, {mode: 0o600});
    // Reject malformed archives and highly expanded input before Office opens it.
    const {stdout: listing} = await runFile('unzip', ['-l', source], {
      timeout: 5000, maxBuffer: 1024 * 1024,
    });
    const summary = listing.trim().split('\n').at(-1).trim().match(/^(\d+)\s+(\d+)\s+files?$/);
    if (!summary || Number(summary[1]) > 200 * 1024 * 1024 ||
        Number(summary[2]) > 5000 || !listing.includes('word/document.xml') ||
        !listing.includes('[Content_Types].xml')) {
      throw new RequestError(422, 'Invalid Word document');
    }
    const profile = join(directory, 'profile');
    await mkdir(join(profile, 'user'), {recursive: true});
    await writeFile(join(profile, 'user', 'registrymodifications.xcu'),
      '<?xml version="1.0"?><oor:items xmlns:oor="http://openoffice.org/2001/registry">' +
      '<item oor:path="/org.openoffice.Office.Common/Security/Scripting"><prop oor:name="MacroSecurityLevel" oor:op="fuse"><value>3</value></prop></item>' +
      '</oor:items>');
    await runFile(process.env.SOFFICE_BIN || 'soffice', [
      `-env:UserInstallation=${pathToFileURL(profile).href}`,
      '--headless', '--nologo', '--nodefault', '--nofirststartwizard',
      '--convert-to', 'pdf:writer_pdf_Export', '--outdir', directory, source,
    ], {timeout: 45000, killSignal: 'SIGKILL', maxBuffer: 1024 * 1024});
    const target = join(directory, 'document.pdf');
    if ((await stat(target)).size > MAX_PDF) throw new RequestError(413, 'PDF too large');
    const pdf = await readFile(target);
    if (pdf.subarray(0, 5).toString() !== '%PDF-') throw new Error('Invalid converter output');
    return pdf;
  } finally {
    await rm(directory, {recursive: true, force: true});
  }
}

export function createPreviewServer({
  convert = convertWithLibreOffice,
  origins = (process.env.CORS_ORIGINS || 'https://paltranco.vercel.app').split(',').map(x => x.trim()).filter(Boolean),
  allowLocalhost = process.env.ALLOW_LOCALHOST === 'true',
  maxBytes = MAX_DOCX,
  maxConcurrent = 1,
} = {}) {
  let active = 0;
  const server = http.createServer(async (request, response) => {
    response.setHeader('Cache-Control', 'no-store');
    response.setHeader('X-Content-Type-Options', 'nosniff');
    const origin = request.headers.origin;
    const local = origin && /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin);
    if (origin && !origins.includes(origin) && !(allowLocalhost && local)) {
      response.writeHead(403).end('Origin not allowed'); return;
    }
    if (origin) {
      response.setHeader('Access-Control-Allow-Origin', origin);
      response.setHeader('Vary', 'Origin');
    }
    if (request.method === 'OPTIONS' && request.url === '/convert') {
      response.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
      response.setHeader('Access-Control-Allow-Headers', 'Content-Type, Accept');
      response.writeHead(204).end(); return;
    }
    if (request.method === 'GET' && request.url === '/health') {
      response.writeHead(200, {'Content-Type': 'application/json'}).end('{"status":"ok"}'); return;
    }
    if (request.method !== 'POST' || request.url !== '/convert') {
      response.writeHead(404).end(); return;
    }
    if (request.headers['content-type']?.split(';')[0] !== DOCX) {
      response.writeHead(415).end('Expected a Word document'); return;
    }
    if (active >= maxConcurrent) {
      response.setHeader('Retry-After', '3');
      response.writeHead(429).end('Converter busy'); return;
    }
    active++;
    try {
      const body = await readBody(request, maxBytes);
      if (body.length < 4 || body.subarray(0, 4).toString('hex') !== '504b0304') {
        throw new RequestError(422, 'Invalid Word document');
      }
      const pdf = await convert(body);
      if (pdf.length > MAX_PDF || pdf.subarray(0, 5).toString() !== '%PDF-') {
        throw new RequestError(502, 'Invalid conversion response');
      }
      response.writeHead(200, {
        'Content-Type': 'application/pdf',
        'Content-Disposition': 'inline; filename="preview.pdf"',
        'Content-Length': pdf.length,
      }).end(pdf);
    } catch (error) {
      // Document contents, filenames and customer information never go to logs.
      const status = error.status || (error.code === 'ENOENT' ? 503 : 422);
      response.writeHead(status).end(status === 503 ? 'Converter unavailable' : 'Could not convert document');
    } finally { active--; }
  });
  server.requestTimeout = 65000;
  server.headersTimeout = 10000;
  return server;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const port = Number(process.env.PORT || 8784);
  const host = process.env.HOST || '127.0.0.1';
  createPreviewServer().listen(port, host, () => console.log(`DOCX preview service listening on ${host}:${port}`));
}
