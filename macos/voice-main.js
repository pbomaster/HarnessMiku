// Registered inside the application's ready handler, next to its microphone policy.
function mikuTrusted(event) {
  if (event.sender !== mainWindow?.webContents || event.senderFrame !== event.sender.mainFrame ||
      !applicationFrame(event.senderFrame.url)) throw Error("허용되지 않은 창이에요.");
}
ipcMain.handle("miku:voice-ready", async (event) => {
  mikuTrusted(event);
  return process.platform==="darwin" ? systemPreferences.askForMediaAccess("microphone") : true;
});
const senseRoot=join(mikuSupportDir,"SenseVoice","1.12.14-20240717");
ipcMain.handle("miku:transcribe", async (event, pcm, language) => {
  mikuTrusted(event);
  if (!(pcm instanceof Int16Array) || !pcm.length || pcm.length > 16000*65 || !["ko","en"].includes(language))
    throw Error("녹음 길이 또는 언어를 확인해 줘.");
  const {mkdtemp}=await import("node:fs/promises");
  const folder=await mkdtemp(join(app.getPath("temp"),"miku-stt-"));
  const file=join(folder,"voice.wav");
  try {
    const wav=Buffer.alloc(44+pcm.byteLength);
    wav.write("RIFF");wav.writeUInt32LE(wav.length-8,4);wav.write("WAVEfmt ",8);
    wav.writeUInt32LE(16,16);wav.writeUInt16LE(1,20);wav.writeUInt16LE(1,22);
    wav.writeUInt32LE(16000,24);wav.writeUInt32LE(32000,28);
    wav.writeUInt16LE(2,32);wav.writeUInt16LE(16,34);wav.write("data",36);
    wav.writeUInt32LE(pcm.byteLength,40);Buffer.from(pcm.buffer,pcm.byteOffset,pcm.byteLength).copy(wav,44);
    await writeFile(file,wav,{mode:0o600});
    const args=["--sense-voice-model="+join(senseRoot,"model/model.int8.onnx"),
      "--tokens="+join(senseRoot,"model/tokens.txt"),"--sense-voice-language="+language,
      "--sense-voice-use-itn=true","--num-threads=4",file];
    const recognizer=join(senseRoot,"runtime/bin",process.platform==="win32"?"sherpa-onnx-offline.exe":"sherpa-onnx-offline");
    if(process.platform==="win32" && !existsSync(recognizer))throw Error("받아쓰기를 설치하려면 Install-Windows.cmd --speech 를 실행해 줘.");
    const diagnostic=await new Promise((resolve,reject)=>execFile(recognizer,
      args,{timeout:120000,maxBuffer:2*1024*1024},(err,stdout,stderr)=>err?
        reject(Error("로컬 SenseVoice 실행 실패. 설치기를 다시 실행해 줘.")):resolve(stderr)));
    const section=diagnostic.replaceAll("\r\n","\n").split(file+"\n").at(-1).split("\n----")[0];
    const text=JSON.parse(section).text.replace(/<\|[^|]*\|>/g,"").trim();
    if(!text)throw Error("목소리가 들리지 않았어. 다시 말해 줄래?");
    return text;
  } finally {await rm(folder,{recursive:true,force:true});}
});

const mikuFactoryPersona=MIKU_FACTORY_PERSONA;
async function activePromptProfile(expected){
  let mode;
  try { mode=(await readFile(identityPath,"utf8")).trim(); }
  catch(e){if(e.code!=="ENOENT")throw e;}
  mode=mode==="coding"?"coding":"miku";
  if(expected && expected!==mode)throw Error("정체성이 바뀌었어. 편집 창을 다시 열어 줘.");
  return mode==="coding"
    ? {path:join(mikuSupportDir,"system-prompt.txt"),preset:mikuFactoryPersona}
    : {path:join(mikuSupportDir,"miku-system-prompt.txt"),preset:AFTERSCHOOL_PERSONA};
}
ipcMain.handle("miku:prompt-preset",async(event,expected)=>{mikuTrusted(event);return (await activePromptProfile(expected)).preset;});
const mikuPromptDir=mikuSupportDir;

ipcMain.handle("miku:prompt-get",async(event,expected)=>{
  mikuTrusted(event);
  const profile=await activePromptProfile(expected);
  try {return await readFile(profile.path,"utf8");}
  catch(error){if(error.code==="ENOENT")return profile.preset;throw error;}
});
ipcMain.handle("miku:prompt-save",async(event,value,expected)=>{
  mikuTrusted(event);
  if(typeof value!=="string" || value.length>16000)throw Error("최대 16,000자까지 저장할 수 있어.");
  await mkdir(mikuPromptDir,{recursive:true});
  const {path:mikuPromptPath}=await activePromptProfile(expected);
  const tmp=mikuPromptPath+"."+randomUUID();
  try {
    await writeFile(tmp,value.trim(),{mode:0o600,flag:"wx"});
    await rename(tmp,mikuPromptPath);
  } finally {await rm(tmp,{force:true});}
});

// Inspect and restrict the same descriptor we read, including legacy key files.
async function readMikuCredentialFile(name){
  const {open}=await import("node:fs/promises");
  const {constants}=await import("node:fs");
  const file=await open(join(resolveDshHome(),name),constants.O_RDONLY|constants.O_NONBLOCK|constants.O_NOFOLLOW);
  try{
    const info=await file.stat();
    if(!info.isFile() || (process.platform!=="win32" && info.uid!==process.getuid()))throw Error("자격 증명 파일 소유자를 확인해 줘.");
    if(process.platform!=="win32" && (info.mode & 0o077))await file.chmod(info.mode & 0o700);
    return await file.readFile("utf8");
  }finally{await file.close();}
}
ipcMain.handle("miku:balance", async event=>{
  mikuTrusted(event);
  try {
    const ref=await welcomeBackend?.balanceRef();
    if(!ref)return {error:"DeepSeek 제공자를 확인해 줘."};
    let stored;
    try {
      const raw=await readMikuCredentialFile(".credentials.yaml");
      const doc=load(raw,{schema:FAILSAFE_SCHEMA});
      stored=(doc?.refs??doc)?.[ref];
    }catch(error){if(error.code!=="ENOENT")throw error;}
    let key=stored||process.env[ref];
    if(!key){
      const {parseEnv}=await import("node:util");
      try{key=parseEnv(await readMikuCredentialFile(".env"))[ref];}
      catch(error){if(error.code!=="ENOENT")throw error;}
    }
    if(typeof key!=="string" || !key)return {error:"설정 → 모델에서 DeepSeek 키를 저장해 줘."};
    const response=await fetch("https://api.deepseek.com/user/balance",{
      headers:{Authorization:"Bearer "+key},redirect:"error",signal:AbortSignal.timeout(10000)
    });
    if(!response.ok)return {error:"DeepSeek 잔액 조회 실패 (HTTP "+response.status+")"};
    const {balance_infos}=await response.json();
    const balances=balance_infos.filter(r=>["USD","CNY"].includes(r.currency) && typeof r.total_balance==="string" && /^-?\d+(\.\d+)?$/.test(r.total_balance))
      .map(r=>({currency:r.currency,amount:r.total_balance}));
    if(balances.length)return {balances};
  }catch{}
  return {error:"잔액을 확인할 수 없어. 눌러서 다시 조회해 줘."};
});

// Discover only on the user's own Mac. Never attach a hosted provider's credentials.
ipcMain.handle("miku:llama-models",async(event,port)=>{
  mikuTrusted(event);
  if(!Number.isInteger(port)||port<1||port>65535)throw Error("포트 번호를 확인하세요.");
  const base="http://127.0.0.1:"+port+"/v1";
  const res=await fetch(base+"/models",{redirect:"error",signal:AbortSignal.timeout(4000)});
  if(res.status===401)return {base,auth:true};
  if(!res.ok)throw Error("모델 목록 조회 실패");
  const {data}=await res.json();
  if(!Array.isArray(data))throw Error("모델 목록 형식 오류");
  return {base,ids:data.map(row=>row?.id).filter(id=>typeof id==="string" && id.length<=512)};
});

const mikuCodexOwner=randomUUID();
ipcMain.handle("miku:codex",async(event,action)=>{
  mikuTrusted(event);
  if(action==="open"){await shell.openExternal("https://auth.openai.com/codex/device");return;}
  if(!["start","status","cancel"].includes(action)||!welcomeBackend)throw Error("계정 서비스를 사용할 수 없어.");
  return welcomeBackend.mikuCodex(action,mikuCodexOwner);
});

const identityPath=join(mikuSupportDir,"identity-mode.txt");
ipcMain.handle("miku:identity-mode",async(event,value)=>{
  mikuTrusted(event);
  if(value===undefined){
    try{return (await readFile(identityPath,"utf8")).trim()==="coding"?"coding":"miku";}
    catch(err){if(err.code==="ENOENT")return "miku";throw err;}
  }
  if(value!=="miku" && value!=="coding")throw Error("지원하지 않는 정체성 모드야.");
  await mkdir(mikuSupportDir,{recursive:true});
  const tmp=identityPath+"."+randomUUID();
  try{await writeFile(tmp,value,{mode:0o600,flag:"wx"});await rename(tmp,identityPath);}
  finally{await rm(tmp,{force:true});}
  return value;
});

ipcMain.handle("miku:lite-mode",async(event,value)=>{
  mikuTrusted(event);
  const file=join(mikuSupportDir,"lite-mode.txt");
  if(value===undefined){
    try{return (await readFile(file,"utf8")).trim()==="on";}
    catch(e){if(e.code==="ENOENT")return false;throw e;}
  }
  if(typeof value!=="boolean")throw Error("잘못된 Lite 모드 값");
  await mkdir(mikuSupportDir,{recursive:true});
  const tmp=file+"."+randomUUID();
  try{await writeFile(tmp,value?"on":"off",{mode:0o600,flag:"wx"});await rename(tmp,file);}
  finally{await rm(tmp,{force:true});}
  return value;
});
