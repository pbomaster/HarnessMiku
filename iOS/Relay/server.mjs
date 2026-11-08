// Personal, single-device relay. Bind only to loopback behind your own HTTPS proxy.
import http from 'node:http';
import http2 from 'node:http2';
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

const env=process.env;
const pair=env.MIKU_PAIR_KEY, topic=env.APNS_TOPIC;
if (!pair || pair.length<32 || !topic || !env.APNS_TEAM || !env.APNS_KID || !env.APNS_P8)
  throw Error('Set MIKU_PAIR_KEY (at least 32 characters), APNS_TOPIC, APNS_TEAM, APNS_KID and APNS_P8.');
const key=crypto.createPrivateKey(await fs.readFile(env.APNS_P8));
const dir=path.join(os.homedir(),'Library','Application Support','Harness Miku','ReplyRelay');
await fs.mkdir(dir,{recursive:true,mode:0o700});
const jobs=new Map();
const ttl=24*3600_000;
const file=id=>path.join(dir,id+'.json');
const fingerprint=s=>crypto.createHash('sha256').update(s).digest();
const encode=o=>Buffer.from(JSON.stringify(o)).toString('base64url');
let jwt='',issued=0;
function bearer(){
  const now=Math.floor(Date.now()/1000);if(jwt && now-issued<2400)return jwt;
  const payload=encode({alg:'ES256',kid:env.APNS_KID})+'.'+encode({iss:env.APNS_TEAM,iat:now});
  jwt=payload+'.'+crypto.sign('sha256',Buffer.from(payload),{key,dsaEncoding:'ieee-p1363'}).toString('base64url');issued=now;return jwt;
}
async function notify(device,id){
  const origin=env.APNS_ENV==='production'?'https://api.push.apple.com':'https://api.sandbox.push.apple.com';
  const client=http2.connect(origin);
  try {await new Promise((resolve,reject)=>{
    client.on('error',reject);
    const req=client.request({':method':'POST',':path':'/3/device/'+device,authorization:'bearer '+bearer(),
      'apns-topic':topic,'apns-push-type':'alert','apns-priority':'10','apns-collapse-id':id,
      'apns-expiration':String(Math.floor((Date.now()+ttl)/1000))});
    let status=0;
    req.setTimeout(12000,()=>req.destroy(Error('timeout')));
    req.on('response',h=>status=h[':status']);req.on('error',reject);req.resume();
    req.on('end',()=>status===200?resolve():reject(Error('APNs HTTP '+status)));
    req.end(JSON.stringify({aps:{alert:{title:'Harness Miku',body:'미쿠의 답변이 도착했어.'},sound:'default'},job:id}));
  });} finally {client.destroy();}
}
export function replyText(kind,obj){
  const text=kind==='account'?obj.content?.filter(x=>x.type==='text').map(x=>x.text).join('\n'):obj.choices?.[0]?.message?.content;
  if(typeof text!=='string'||!text.trim())throw Error('빈 DeepSeek 응답');return text;
}
async function persist(id,result){
  const temp=file(id)+'.tmp';
  await fs.writeFile(temp,JSON.stringify({...result,created:Date.now()}),{mode:0o600});await fs.rename(temp,file(id));
}
async function work(id,p){
  const account=p.kind==='account';
  let result;
  try {
    const response=await fetch(account?'https://api.deepseek.com/anthropic/v1/messages':'https://api.deepseek.com/chat/completions',{
      method:'POST',redirect:'error',signal:AbortSignal.timeout(180000),headers:{'content-type':'application/json',
        ...(account?{'x-dsh-auth-token':p.credential,'anthropic-version':'2023-06-01'}:{authorization:p.credential})},body:JSON.stringify(p.request)});
    if(!response.ok)throw Error('DeepSeek HTTP '+response.status);
    result={state:'done',reply:replyText(p.kind,await response.json())};
  }catch(e){result={state:'failed',error:/^DeepSeek HTTP \d+$/.test(e.message)?e.message:'중계에서 답변을 받지 못했어.'};}
  delete p.credential;delete p.request;
  await persist(id,result);
  if(result.state==='done'){
    for(let i=0;i<3;i++){try{await notify(p.device,id);break;}catch{if(i===2)console.error('APNs delivery failed; reply remains available.');else await new Promise(r=>setTimeout(r,1500*(i+1)));}}
  }
}
async function existing(id){
  try{const r=JSON.parse(await fs.readFile(file(id),'utf8'));if(Date.now()-r.created<ttl)return r;await fs.unlink(file(id));}
  catch(e){if(e.code!=='ENOENT')throw e;}
  return jobs.has(id)?{state:'running'}:null;
}
async function sweep(){for(const name of await fs.readdir(dir)){if(!/^[\da-f-]{36}\.json$/i.test(name))continue;await existing(name.slice(0,-5));}}
await sweep();setInterval(()=>sweep().catch(()=>{}),3600_000).unref();
const server=http.createServer(async(req,res)=>{
  const send=(status,obj)=>{res.writeHead(status,{'content-type':'application/json','cache-control':'no-store'});res.end(JSON.stringify(obj));};
  try {
    if(!crypto.timingSafeEqual(fingerprint(req.headers.authorization||''),fingerprint('Bearer '+pair)))return send(401,{});
    const m=/^\/jobs\/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$/i.exec(req.url);
    if(!m)return send(404,{});
    const id=m[1].toLowerCase();
    if(req.method==='GET'){const r=await existing(id);return send(r?200:404,r||{});}
    if(req.method!=='POST')return send(405,{});
    let size=0,chunks=[];for await(const chunk of req){size+=chunk.length;if(size>2_000_000)return send(413,{});chunks.push(chunk);}
    const p=JSON.parse(Buffer.concat(chunks).toString('utf8'));
    if(!['account','api'].includes(p.kind)||typeof p.credential!=='string'||!p.credential||/[\r\n]/.test(p.credential)||
       !/^[a-f\d]{32,256}$/i.test(p.device)||!Array.isArray(p.request?.messages)||typeof p.request.model!=='string')return send(400,{});
    const prev=await existing(id);if(prev)return send(200,prev);
    if(jobs.has(id))return send(200,{state:'running'});
    if(jobs.size>=4)return send(429,{});
    jobs.set(id,true);work(id,p).catch(()=>console.error('Could not store reply.')).finally(()=>jobs.delete(id));
    return send(202,{state:'running'});
  }catch{return send(400,{});}
});
server.listen(Number(env.PORT||8787),'127.0.0.1');
