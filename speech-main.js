// Register alongside the existing primary-frame IPC handlers.
let fishKey="", fishLoading, rejectedFishEnv=false;
const mikuSupportDir=process.platform==="win32" ? join(app.getPath("appData"),"Harness Miku") : join(homedir(),"Library","Application Support","Harness Miku");
const fishDir=join(mikuSupportDir,"Credentials");
const fishPath=join(fishDir,"fish-key.enc");
async function askWindowsFishKey(){
  const prompt=new BrowserWindow({parent:mainWindow,modal:true,show:false,width:480,height:240,
    resizable:false,autoHideMenuBar:true,title:"Fish Audio API 키",
    webPreferences:{sandbox:true,contextIsolation:true,nodeIntegration:false,devTools:false,partition:"miku-key-entry"}});
  prompt.removeMenu();
  prompt.webContents.setWindowOpenHandler(()=>({action:"deny"}));
  prompt.webContents.on("will-navigate",event=>event.preventDefault());
  const closed=new Promise(resolve=>prompt.once("closed",()=>resolve("")));
  const html=`<!doctype html><html lang="ko"><meta charset="utf-8">
    <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; form-action 'none'; base-uri 'none'">
    <style>body{font:14px system-ui;color:#263d3a;margin:24px;background:#f4fcf9}
    label{display:block;font-weight:650}input{width:100%;box-sizing:border-box;padding:8px;margin:8px 0}
    p{margin:2px 0 18px}footer{text-align:right}button{padding:5px 14px;margin-left:6px}</style>
    <form><label for="key">Fish Audio API 키</label>
    <input id="key" type="password" maxlength="4096" autocomplete="off" spellcheck="false" required>
    <p>이 Windows 계정에 암호화해 저장해. 음성 ID는 앱에서 따로 입력해 줘.</p>
    <footer><button type="button" id="cancel">취소</button><button type="submit">저장</button></footer></form></html>`;
  try{
    await prompt.loadURL("data:text/html;charset=utf-8,"+encodeURIComponent(html));
    if(prompt.isDestroyed())return "";
    const answer=prompt.webContents.executeJavaScript(`new Promise(resolve=>{
      const key=document.getElementById("key");
      function finish(value){key.value="";resolve(value);}
      document.querySelector("form").onsubmit=e=>{e.preventDefault();finish(key.value.trim());};
      document.getElementById("cancel").onclick=()=>finish("");
      document.onkeydown=e=>{if(e.key==="Escape")finish("");};
      key.focus();
    })`);
    prompt.show();
    return await Promise.race([closed,answer]);
  }catch{if(prompt.isDestroyed())return "";throw Error("Fish API 키 입력창을 열 수 없어.");}
  finally{if(!prompt.isDestroyed())prompt.destroy();}
}
async function loadFishKey(replace=false){
  const {safeStorage}=await import("electron");
  if(!safeStorage.isEncryptionAvailable())throw Error("운영체제 자격 증명 저장소를 잠금 해제한 뒤 다시 시도해 줘.");
  let encrypted;
  try {encrypted=await readFile(fishPath);}
  catch(err){if(err.code!=="ENOENT")throw Error("저장된 Fish 키 파일을 읽을 수 없어.");}
  if(encrypted && !replace){
    try {fishKey=safeStorage.decryptString(encrypted);return true;}
    catch {throw Error("저장된 Fish 키를 열 수 없어. 운영체제 자격 증명 저장소 접근을 확인해 줘.");}
  }
  let candidate=replace || rejectedFishEnv ? "" : process.env.FISH_API_KEY?.trim();
  if(!candidate && process.platform==="win32"){
    candidate=await askWindowsFishKey();
  }else if(!candidate){
    const script='text returned of (display dialog "Fish Audio API 키를 입력하세요. 이 Mac에 암호화하여 저장합니다." default answer "" with hidden answer buttons {"취소","확인"} default button "확인" cancel button "취소" with title "미쿠 목소리")';
    candidate=await new Promise(resolve=>execFile("/usr/bin/osascript",["-e",script],{env:{LANG:"en_US.UTF-8"}},(err,out)=>resolve(err?"":out.trim())));
  }
  if(!candidate)return false;
  if(!/^[!-~]{1,4096}$/.test(candidate))throw Error("Fish 키의 입력 형식을 확인해 줘.");
  const tmp=fishPath+"."+randomUUID();
  try{
    await mkdir(fishDir,{mode:0o700,recursive:true});
    await writeFile(tmp,safeStorage.encryptString(candidate),{mode:0o600,flag:"wx"});
    await rename(tmp,fishPath);
  }catch{throw Error("Fish 키를 안전하게 저장할 수 없어. 키체인과 폴더 권한을 확인해 줘.");}
  finally{await rm(tmp,{force:true});}
  fishKey=candidate;
  return true;
}
let fishJob;

// Only locally authored presets can supply markup for a fixed line.
const fixedVoice=new Map(MIKU_FIXED_VOICE.map(([script,direction])=>[
  script.replace(/<\/?(?:soft|slow|whisper|emphasis)>/g,""), {script,direction}
]));
function directMikuSpeech(text,model){
  const preset=fixedVoice.get(text.trim());
  if(!preset)throw Error("이 대사의 음성 프리셋을 찾지 못했어.");
  return model==="drama-3" ? preset.script : "["+preset.direction+"] "+text.trim();
}
ipcMain.handle("miku:tts-enable",async(event,replace=false)=>{
  mikuTrusted(event);
  if(typeof replace!=="boolean")throw Error("키 설정 요청을 확인해 줘.");
  if(fishKey && !replace)return true;
  fishLoading??=loadFishKey(replace).finally(()=>{fishLoading=null;});
  return fishLoading;
});
ipcMain.handle("miku:tts-stop",event=>{mikuTrusted(event);fishJob?.abort();});
ipcMain.handle("miku:tts",async(event,text,id,model="s2.1-pro-free",tone=null)=>{
  mikuTrusted(event);
  if(!["s2.1-pro-free","s2.1-pro","drama-3"].includes(model))throw Error("지원하지 않는 합성 모델이야.");
  if(!fishKey||typeof text!=="string"||!text.trim()||text.length>4000||!/^([0-9a-f]{32})$/.test(id))throw Error("음성 설정을 확인해 줘.");
  let script;
  if(tone===null)script=directMikuSpeech(text,model);
  else {
    if(!MIKU_TONE_NAMES.includes(tone) || text.length>400 || /&(?:#|[a-z]+;)/i.test(text) || /[<>\[\](){}［］（）【】\x60\r\n]/u.test(text))
      throw Error("요약 음성 형식을 확인해 줘.");
    script=model==="drama-3" ? "<"+tone+">"+text+"</"+tone+">" : text;
  }
  fishJob?.abort();
  const job=new AbortController();fishJob=job;
  const timer=setTimeout(()=>job.abort(),60000);
  try {
    const requestKey=fishKey;
    const r=await fetch("https://api.fish.audio/v1/tts",{method:"POST",redirect:"error",signal:job.signal,
      headers:{Authorization:"Bearer "+requestKey,"Content-Type":"application/json",model},
      body:JSON.stringify({text:script,reference_id:id,format:"mp3"})});
    if(!r.ok){if(r.status===401 && fishKey===requestKey){
      rejectedFishEnv=true;
      await rm(fishPath,{force:true});
      fishKey="";
    }throw Error("Fish Audio "+r.status+" · API 키, 사용 한도 또는 음성 ID를 확인해 줘.");}
    const bytes=await r.arrayBuffer();
    if(!bytes.byteLength)throw Error("받은 음성이 비어 있어.");
    return new Uint8Array(bytes);
  } finally{clearTimeout(timer);if(fishJob===job)fishJob=null;}
});
