import {test} from 'node:test';
import assert from 'node:assert/strict';
import {once} from 'node:events';
import {createPreviewServer} from './server.mjs';
const mime = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
const docx = Buffer.from('PK\x03\x04test-word-document');
const pdf = Buffer.from('%PDF-1.7\ntest PDF');
async function fixture(t, options = {}) {
  const server = createPreviewServer({convert: async () => pdf, ...options});
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(() => {server.closeAllConnections(); server.close();});
  return `http://127.0.0.1:${server.address().port}`;
}
const post = (url, body = docx, headers = {}) => fetch(`${url}/convert`, {
  method: 'POST', headers: {'Content-Type': mime, ...headers}, body,
});
test('passes original DOCX bytes to conversion and returns PDF without caching', async t => {
  let received;
  const url = await fixture(t, {convert: async bytes => {received = bytes; return pdf;}});
  const response = await post(url);
  assert.equal(response.status, 200);
  assert.deepEqual(received, docx);
  assert.equal(response.headers.get('content-type'), 'application/pdf');
  assert.equal(response.headers.get('cache-control'), 'no-store');
  assert.deepEqual(Buffer.from(await response.arrayBuffer()), pdf);
});
test('allows configured production origin and optional random localhost ports', async t => {
  const url = await fixture(t, {allowLocalhost: true});
  for (const origin of ['https://paltranco.vercel.app', 'http://localhost:53670']) {
    const response = await post(url, docx, {Origin: origin});
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('access-control-allow-origin'), origin);
  }
  assert.equal((await post(url, docx, {Origin: 'https://unknown.example'})).status, 403);
  const options = await fetch(`${url}/convert`, {method: 'OPTIONS', headers: {Origin: 'http://localhost:53670'}});
  assert.equal(options.status, 204);
});
test('rejects wrong type, invalid DOCX, and oversized documents', async t => {
  let calls = 0;
  const url = await fixture(t, {maxBytes: 32, convert: async () => {calls++; return pdf;}});
  assert.equal((await post(url, 'not a docx')).status, 422);
  assert.equal((await post(url, Buffer.alloc(33))).status, 413);
  assert.equal((await post(url, docx, {'Content-Type': 'text/html'})).status, 415);
  assert.equal(calls, 0);
});
test('bounds concurrent conversion and releases the slot after failure', async t => {
  let release;
  const waiting = new Promise(resolve => release = resolve);
  let entered;
  const started = new Promise(resolve => entered = resolve);
  let attempts = 0;
  const url = await fixture(t, {convert: async () => {
    attempts++;
    if (attempts === 1) {entered(); await waiting; throw new Error('conversion failed');}
    return pdf;
  }});
  const first = post(url);
  await started;
  assert.equal((await post(url)).status, 429);
  release();
  assert.equal((await first).status, 422);
  assert.equal((await post(url)).status, 200);
});
test('does not return an HTML or DOCX response as PDF', async t => {
  const url = await fixture(t, {convert: async () => Buffer.from('<html>error</html>')});
  assert.equal((await post(url)).status, 502);
});
