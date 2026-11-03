// Registered inside the application's ready handler, next to its microphone policy.
function mikuTrusted(event) {
  if (event.sender !== mainWindow?.webContents || event.senderFrame !== event.sender.mainFrame ||
      !applicationFrame(event.senderFrame.url)) throw Error("허용되지 않은 창이에요.");
}
ipcMain.handle("miku:voice-ready", async (event) => {
  mikuTrusted(event);
  return systemPreferences.askForMediaAccess("microphone");
});
const senseRoot=join(homedir(),"Library","Application Support","Harness Miku","SenseVoice","1.12.14-20240717");
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
    const diagnostic=await new Promise((resolve,reject)=>execFile(join(senseRoot,"runtime/bin/sherpa-onnx-offline"),
      args,{timeout:120000,maxBuffer:2*1024*1024},(err,stdout,stderr)=>err?
        reject(Error("로컬 SenseVoice 실행 실패. 설치기를 다시 실행해 줘.")):resolve(stderr)));
    const section=diagnostic.split(file+"\n").at(-1).split("\n----")[0];
    const text=JSON.parse(section).text.replace(/<\|[^|]*\|>/g,"").trim();
    if(!text)throw Error("목소리가 들리지 않았어. 다시 말해 줄래?");
    return text;
  } finally {await rm(folder,{recursive:true,force:true});}
});

const mikuFactoryPersona=MIKU_FACTORY_PERSONA;
ipcMain.handle("miku:prompt-preset",event=>{mikuTrusted(event);return mikuFactoryPersona;});
const mikuPromptDir=join(homedir(),"Library","Application Support","Harness Miku");
const mikuPromptPath=join(mikuPromptDir,"system-prompt.txt");
ipcMain.handle("miku:prompt-get",async event=>{
  mikuTrusted(event);
  try {return await readFile(mikuPromptPath,"utf8");}
  catch(error){if(error.code==="ENOENT")return mikuFactoryPersona;throw error;}
});
ipcMain.handle("miku:prompt-save",async(event,value)=>{
  mikuTrusted(event);
  if(typeof value!=="string" || value.length>16000)throw Error("최대 16,000자까지 저장할 수 있어.");
  await mkdir(mikuPromptDir,{recursive:true});
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
    if(!info.isFile() || info.uid!==process.getuid())throw Error("자격 증명 파일 소유자를 확인해 줘.");
    if(info.mode & 0o077)await file.chmod(info.mode & 0o700);
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
