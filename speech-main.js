// Register alongside the existing primary-frame IPC handlers.
let fishKey="", fishLoading, rejectedFishEnv=false;
const fishDir=join(homedir(),"Library","Application Support","Harness Miku","Credentials");
const fishPath=join(fishDir,"fish-key.enc");
async function loadFishKey(){
  const {safeStorage}=await import("electron");
  if(!safeStorage.isEncryptionAvailable())throw Error("macOS 키체인을 잠금 해제한 뒤 다시 시도해 줘.");
  let encrypted;
  try {encrypted=await readFile(fishPath);}
  catch(err){if(err.code!=="ENOENT")throw Error("저장된 Fish 키 파일을 읽을 수 없어.");}
  if(encrypted){
    try {fishKey=safeStorage.decryptString(encrypted);return true;}
    catch {throw Error("저장된 Fish 키를 열 수 없어. macOS 키체인 접근을 확인해 줘.");}
  }
  let candidate=rejectedFishEnv ? "" : process.env.FISH_API_KEY?.trim();
  if(!candidate){
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
ipcMain.handle("miku:tts-enable",async event=>{
  mikuTrusted(event);
  if(fishKey)return true;
  fishLoading??=loadFishKey().finally(()=>{fishLoading=null;});
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
