// The login job identifies itself explicitly. A normal Finder launch opens the chat.
let mikuLoginLaunch=process.argv.includes("--miku-login");
let mikuPet=false, mikuOldBounds, mikuOldMax=false;
const mikuAgentDir=join(homedir(),"Library","LaunchAgents");
const mikuAgentFile=join(mikuAgentDir,"local.harnessmiku.desktop-pet.plist");
const {screen:mikuScreen}=await import("electron");
let mikuPetFrame="bust", mikuPetSize=100, mikuDockInset=0, mikuDisplayId;
function mikuAnchor(){
  if(!mikuPet || !mainWindow || mainWindow.isDestroyed())return;
  const display=mikuScreen.getAllDisplays().find(item=>item.id===mikuDisplayId) ?? mikuScreen.getPrimaryDisplay();
  mikuDisplayId=display.id;
  const {bounds,workArea:area}=display;
  const screenBottom=bounds.y+bounds.height;
  mikuDockInset=process.platform==="win32"?0:Math.max(0,screenBottom-area.y-area.height);
  const full=mikuPetFrame==="full";
  const extra=Math.round((full?474:237)*Math.max(0,mikuPetSize/100-1));
  const width=Math.min(Math.max(346,Math.ceil(237*mikuPetSize/100)+24),area.width),height=Math.min((full?652:415)+extra,area.height);
  mainWindow.setBounds({x:area.x+area.width-width,y:(process.platform==="win32"?area.y+area.height:screenBottom)-height,width,height});
  mainWindow.webContents.send("miku:pet-dock-inset",mikuDockInset);
}
ipcMain.on("miku:pet-size",(event,value,frame)=>{
  mikuTrusted(event);
  if(mikuPet && [50,75,100,125,150].includes(value) && ["full","bust"].includes(frame) && (value!==mikuPetSize || frame!==mikuPetFrame)){
    mikuPetSize=value;mikuPetFrame=frame;
    mikuAnchor();
  }
});
for(const event of ["display-added","display-removed","display-metrics-changed"])mikuScreen.on(event,mikuAnchor);
function mikuMode(on){
  const win=mainWindow;
  if(!win || win.isDestroyed() || mikuPet===on)return;
  if(on && win.isFullScreen()){
    win.once("leave-full-screen",()=>mikuMode(true));
    win.setFullScreen(false);
    return;
  }
  mikuPet=on;
  if(on){
    mikuDisplayId=mikuScreen.getDisplayMatching(win.getBounds()).id;
    mikuOldMax=win.isMaximized();
    if(mikuOldMax)win.unmaximize();
    mikuOldBounds=win.getNormalBounds();
    win.setMinimumSize(220,240);
    if(process.platform==="darwin")win.setVibrancy(null);
    win.setBackgroundColor("#00000000");
    win.setHasShadow(false);
    if(process.platform==="darwin")win.setWindowButtonVisibility(false);
    win.setResizable(false);
    win.setAlwaysOnTop(true,"floating");
    if(process.platform==="darwin")win.setVisibleOnAllWorkspaces(true,{skipTransformProcessType:true});
    if(process.platform==="darwin")win.setHiddenInMissionControl?.(true);
    mikuAnchor();
    petCursorTimer=setInterval(updatePetPointer,32);
  }else{
    clearInterval(petCursorTimer);petRegions=[];petPass=null;
    win.setIgnoreMouseEvents(false);
    if(process.platform==="darwin")win.setVisibleOnAllWorkspaces(false,{skipTransformProcessType:true});
    win.setAlwaysOnTop(false);
    if(process.platform==="darwin")win.setHiddenInMissionControl?.(false);
    win.setResizable(true);
    win.setMinimumSize(520,600);
    if(mikuOldBounds)win.setBounds(mikuOldBounds);
    if(mikuOldMax)win.maximize();
    if(process.platform==="darwin")win.setVibrancy("sidebar");
    win.setHasShadow(true);
    if(process.platform==="darwin")win.setWindowButtonVisibility(true);
  }
  win.webContents.send("miku:desktop-mode",on);
}
ipcMain.handle("miku:desktop-state",e=>{mikuTrusted(e);return {pet:mikuPet,dockInset:mikuDockInset,login:process.platform==="win32"?app.getLoginItemSettings({args:["--miku-login"]}).openAtLogin:existsSync(mikuAgentFile)};});
ipcMain.handle("miku:desktop-mode", (e,on)=>{
  mikuTrusted(e);
  if(typeof on!=="boolean")throw Error("잘못된 창 모드");
  if(!on && !enteredWorkspace){focusPrimaryWindow();return;}
  mikuMode(on);
});
// Finder drags need not generate ordinary renderer mousemove events.
let petRegions=[], petPass=null, petCursorTimer;
function updatePetPointer(){
  if(!mikuPet || !mainWindow || mainWindow.isDestroyed())return;
  const cursor=mikuScreen.getCursorScreenPoint(), origin=mainWindow.getContentBounds();
  const zoom=mainWindow.webContents.getZoomFactor();
  const x=(cursor.x-origin.x)/zoom, y=(cursor.y-origin.y)/zoom;
  const pass=!petRegions.some(([l,t,r,b])=>x>=l && x<r && y>=t && y<b);
  if(pass!==petPass){mainWindow.setIgnoreMouseEvents(pass,{forward:true});petPass=pass;}
}
ipcMain.on("miku:pet-regions",(event,regions)=>{
  mikuTrusted(event);
  if(!mikuPet || !Array.isArray(regions) || regions.length>64 ||
     !regions.every(r=>Array.isArray(r)&&r.length===4&&r.every(Number.isFinite)))return;
  petRegions=regions;updatePetPointer();
});
ipcMain.handle("miku:desktop-login",async(e,on)=>{
  mikuTrusted(e);
  if(typeof on!=="boolean")throw Error("잘못된 로그인 설정");
  if(process.platform==="win32"){
    app.setLoginItemSettings({openAtLogin:on,args:["--miku-login"]});
    return app.getLoginItemSettings({args:["--miku-login"]}).openAtLogin;
  }
  if(on){
    const bundle=resolve(dirname(process.execPath),"../..");
    if(!bundle.endsWith(".app"))throw Error("설치된 앱에서 켜 줘.");
    const path=bundle.replaceAll("&","&amp;").replaceAll("<","&lt;").replaceAll(">","&gt;");
    const plist='<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>Label</key><string>local.harnessmiku.desktop-pet</string><key>LimitLoadToSessionType</key><string>Aqua</string><key>RunAtLoad</key><true/><key>ProgramArguments</key><array><string>/usr/bin/open</string><string>-g</string><string>-a</string><string>'+path+'</string><string>--args</string><string>--miku-login</string></array></dict></plist>';
    await mkdir(mikuAgentDir,{recursive:true});
    const tmp=mikuAgentFile+"."+randomUUID();
    try{await writeFile(tmp,plist,{mode:0o600,flag:"wx"});await rename(tmp,mikuAgentFile);}
    finally{await rm(tmp,{force:true});}
  }else await rm(mikuAgentFile,{force:true});
  return existsSync(mikuAgentFile);
});
