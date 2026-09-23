import {spawn} from 'node:child_process';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
const dir=process.env.PTC_REPORT_DIR || `/tmp/ptc-emulator-browser-${Date.now()}`;
await mkdir(dir,{recursive:true});
const delay=ms=>new Promise(r=>setTimeout(r,ms));
const port=Number(process.env.PTC_TEST_PORT || 31882);
const reset=await fetch('http://127.0.0.1:18081/emulator/v1/projects/demo-paltranco-regression/databases/(default)/documents',{method:'DELETE'});
if(!reset.ok)throw Error(`Demo emulator reset failed: ${reset.status}`);
const origin=`http://paltranco.test:${port}`;
const server=spawn('python3',['-m','http.server',String(port),'--bind','127.0.0.1','--directory',process.env.PTC_BUILD_DIR || '/tmp/ptc-emulator-release-validation'],{stdio:'ignore'});
const chrome=spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',[
 '--headless=new','--use-angle=swiftshader','--enable-unsafe-swiftshader','--disable-background-timer-throttling','--disable-renderer-backgrounding','--disable-backgrounding-occluded-windows',`--user-data-dir=${dir}/profile`,'--remote-debugging-port=0',
 '--no-first-run','--no-default-browser-check','--no-proxy-server',
 '--host-resolver-rules=MAP paltranco.test 127.0.0.1',
 `--unsafely-treat-insecure-origin-as-secure=${origin}`,'about:blank'
],{stdio:['ignore','ignore','pipe']});
let chromeLog='';chrome.stderr.on('data',d=>chromeLog+=d);
const report={scope:'Demo Firestore emulator, release harness, native CDP offline/online transitions',phases:[],errors:[],consoleErrors:[],crashes:[]};
let ws;
try {
 let devPort;
 for(let i=0;i<100;i++){try{devPort=(await readFile(`${dir}/profile/DevToolsActivePort`,'utf8')).split('\n')[0];break;}catch{} await delay(100);}
 if(!devPort) throw Error('Chrome did not expose DevTools');
 const targets=await (await fetch(`http://127.0.0.1:${devPort}/json/list`)).json();
 const original=targets.find(t=>t.type==='page');
 ws=new WebSocket(original.webSocketDebuggerUrl);
 await new Promise((resolve,reject)=>{ws.onopen=resolve;ws.onerror=reject;});
 let id=0;const pending=new Map();
 ws.onmessage=e=>{const m=JSON.parse(e.data);if(m.id){const p=pending.get(m.id);if(p){pending.delete(m.id);clearTimeout(p.timer);m.error?p.reject(Error(JSON.stringify(m.error))):p.resolve(m.result);}}else{
  if(m.method==='Runtime.bindingCalled' && m.params.name==='ptcChangeNetwork'){const v=JSON.parse(m.params.payload);call('Network.emulateNetworkConditions',{offline:!v.online,latency:0,downloadThroughput:-1,uploadThroughput:-1}).then(()=>call('Runtime.evaluate',{expression:`window.__networkResolvers[${v.id}]()`,contextId:m.params.executionContextId})).catch(e=>console.error(e));}
  if(m.method==='Runtime.exceptionThrown')report.errors.push(m.params.exceptionDetails);
  if(m.method==='Runtime.consoleAPICalled'&&m.params.type==='log')console.log(m.params.args.map(a=>a.value||a.description));
  if(m.method==='Runtime.consoleAPICalled'&&m.params.type==='error')report.consoleErrors.push(m.params.args.map(a=>a.value||a.description));
  if(m.method==='Inspector.targetCrashed')report.crashes.push(m.params);
 }};
 const call=(method,params={})=>new Promise((resolve,reject)=>{const k=++id;const timer=setTimeout(()=>{pending.delete(k);reject(Error(`CDP timed out: ${method}`));},20000);pending.set(k,{resolve,reject,timer});ws.send(JSON.stringify({id:k,method,params}));});
 const evaluate=async expression=>{const r=await call('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true});if(r.exceptionDetails)throw Error(JSON.stringify(r.exceptionDetails));return r.result.value;};
 await call('Page.enable');await call('Runtime.enable');await call('Network.enable');await call('Performance.enable');
 await call('Emulation.setDeviceMetricsOverride',{width:1440,height:1000,deviceScaleFactor:1,mobile:false});
 await call('Page.addScriptToEvaluateOnNewDocument',{source:`window.__ptcPerf={longTasks:[],frames:0,maxFrameGap:0};new PerformanceObserver(l=>l.getEntries().forEach(e=>window.__ptcPerf.longTasks.push({start:e.startTime,duration:e.duration}))).observe({type:'longtask',buffered:true});let prev;function tick(t){window.__ptcPerf.frames++;if(prev)window.__ptcPerf.maxFrameGap=Math.max(window.__ptcPerf.maxFrameGap,t-prev);prev=t;requestAnimationFrame(tick)}requestAnimationFrame(tick);`});
 await call('Runtime.addBinding',{name:'ptcChangeNetwork'});
 await call('Page.addScriptToEvaluateOnNewDocument',{source:`window.__networkResolvers={};let n=0;window.ptcNetwork=online=>new Promise(resolve=>{let id=++n;window.__networkResolvers[id]=()=>{delete window.__networkResolvers[id];resolve(null)};window.ptcChangeNetwork(JSON.stringify({id,online}));});`});
 await call('Page.navigate',{url:origin});
 for(let i=0;i<150;i++) {
   await delay(1000);
   const raw=await evaluate(`document.body?.getAttribute('data-emulator-report')`);
   if(raw){report.validation=JSON.parse(raw);console.log(JSON.stringify(report.validation));break;}
 }
 if(!report.validation)throw Error('Release validation timed out');
 report.success=report.validation.success;
} catch(e){report.failure=String(e);console.error(e);} finally{
 await writeFile(`${dir}/report.json`,JSON.stringify(report,null,2));
 await writeFile(`${dir}/chrome.log`,chromeLog);
 ws?.close();chrome.kill();server.kill();
}

console.log(`Report: ${dir}/report.json`);
if(!report.success || report.errors.length || report.crashes.length)process.exitCode=1;
