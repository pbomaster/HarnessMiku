// Keep IPC in the isolated preload. Start capture only from the visible user control.
if (window.top===window && location.protocol==="dsh-app:" && location.hostname==="app") {
  // Capture before the upstream window-wide attachment overlay sees a file drag.
  let leaveTimer;
  for(const type of ["dragenter","dragover","dragleave","drop","dragend"]){
    window.addEventListener(type,event=>{
      const page=document.documentElement;
      if(!page?.classList.contains("miku-desktop"))return;
      const canvas=document.getElementById("dsc-stage"),dt=event.dataTransfer;
      if(!dt || (!Array.from(dt.types).includes("Files") && !canvas?.hasAttribute("data-miku-drop")))return;
      event.stopImmediatePropagation();
      clearTimeout(leaveTimer);
      if(type==="dragleave" || type==="dragend"){canvas?.removeAttribute("data-miku-drop");return;}
      event.preventDefault();
      const rect=canvas?.getBoundingClientRect();
      const card=document.querySelector('.dsc-composer[data-miku-drop-ready="true"]');
      const inside=!!(card && rect && event.clientX>=rect.left && event.clientX<rect.right &&
        event.clientY>=rect.top && event.clientY<rect.bottom);
      dt.dropEffect=inside?"copy":"none";
      canvas?.toggleAttribute("data-miku-drop",inside && type!=="drop");
      if(type==="drop" && inside){
        card.dispatchEvent(new DragEvent("miku-pet-files",{dataTransfer:dt}));
      }else if(inside)leaveTimer=setTimeout(()=>canvas.removeAttribute("data-miku-drop"),500);
    },true);
  }
  const mountVoice=()=>{
    const bar=document.createElement("div");
    bar.className="miku-voice";
    const button=document.createElement("button");
    const language=document.createElement("select");
    for(const [value,label] of [["ko","한국어"],["en","English"]]) language.add(new Option(label,value));
    language.setAttribute("aria-label","음성 인식 언어");
    const status=document.createElement("span");
    status.setAttribute("role","status");
    const backup=document.createElement("textarea");
    backup.readOnly=true;
    backup.hidden=true;
    backup.setAttribute("aria-label","인식 결과 · 복사 가능");
    bar.append(button,language,status,backup);
    button.type="button";
    button.setAttribute("aria-label","음성 입력");button.dataset.recording="false";
    button.title="최대 60초 · Mac에서 SenseVoice로 인식";
    let phase="idle", recorder, stream, timer, attached, startURL;
    const editor=card=>card?.querySelector('textarea:not(.miku-voice textarea),[contenteditable="true"]');
    function release(){
      clearTimeout(timer);
      stream?.getTracks().forEach(t=>t.stop());
      stream=null;
    }
    function idle(){
      phase="idle";button.disabled=false;language.disabled=false;button.setAttribute("aria-label","음성 입력");button.dataset.recording="false";
    }
    function stop(){
      if(phase!=="recording" || recorder?.state!=="recording")return;
      phase="processing";button.disabled=true;button.setAttribute("aria-label","인식 중");recorder.stop();
    }
    function place(){
      const card=[...document.querySelectorAll(".dsc-composer")].find(c=>c.getClientRects().length&&editor(c));
      if(card && bar.parentNode!==card){card.append(bar); setOptions(false); refreshBalance();}
      if(phase==="recording" && (!attached?.isConnected || startURL!==location.href)) stop();
    }
    const editPrompt=document.createElement("button");
    editPrompt.type="button";
    editPrompt.textContent="기본 시스템 프롬프트";
    const identityLabel=document.createElement("div");
    identityLabel.className="miku-identity";
    identityLabel.setAttribute("role","group");
    identityLabel.setAttribute("aria-label","정체성 모드");
    const identityHeading=document.createElement("strong");
    identityHeading.textContent="정체성 모드";
    identityLabel.append(identityHeading);
    const identityButtons=[];
    let savedIdentity=null, savingIdentity=false;
    function paintIdentity(){
      document.documentElement.dataset.mikuIdentity=savedIdentity || "";
      for(const control of identityButtons){
        control.disabled=savingIdentity;
        control.setAttribute("aria-pressed",String(control.value===savedIdentity));
      }
    }
    for(const [value,label] of [["miku","진짜 미쿠"],["coding","코딩 에이전트"]]){
      const control=document.createElement("button");
      control.type="button";control.textContent=label;control.value=value;
      control.onclick=async()=>{
        if(savingIdentity)return;
        savingIdentity=true;paintIdentity();
        try{
          savedIdentity=await electron.ipcRenderer.invoke("miku:identity-mode",value);
          status.textContent="정체성을 저장했어. 새 대화에서 확인해 줘.";
        }catch{status.textContent="정체성 설정을 저장하지 못했어.";}
        finally{savingIdentity=false;paintIdentity();}
      };
      identityButtons.push(control);identityLabel.append(control);
    }
    let initialIdentityRead=true;
    identityLabel.addEventListener("click",()=>{initialIdentityRead=false;},true);
    paintIdentity();
    electron.ipcRenderer.invoke("miku:identity-mode").then(value=>{
      if(initialIdentityRead){savedIdentity=value;paintIdentity();}
    }).catch(()=>{status.textContent="정체성 설정을 읽지 못했어. 원하는 모드를 눌러 줘.";});
    bar.append(editPrompt);
    editPrompt.onclick=async event=>{
      if(!event.isTrusted || editPrompt.disabled)return;
      editPrompt.disabled=true;
      const editMode=savedIdentity;
      const panel=document.createElement("dialog");
      panel.className="miku-prompt";
      const title=document.createElement("h2"),help=document.createElement("p"),field=document.createElement("textarea");
      title.textContent="기본 시스템 프롬프트";
      help.textContent="미쿠의 말투와 기본 지시를 적어 줘. 비워 저장하면 Harness 기본값으로 돌아가.";
      field.maxLength=16000;field.setAttribute("aria-label",title.textContent);
      field.placeholder="예: 한국어 반말로 답하고, 내가 비교를 부탁하면 차이부터 알려 줘.";
      const save=document.createElement("button"),cancel=document.createElement("button"),error=document.createElement("p");
      save.textContent="저장";cancel.textContent="취소";error.setAttribute("role","status");
      const preset=document.createElement("button");
      preset.textContent=editMode==="miku"?"방과 후 미쿠 프리셋":"윤회 미쿠 프리셋";
      preset.onclick=async()=>{
        try{field.value=await electron.ipcRenderer.invoke("miku:prompt-preset",editMode);field.focus();}
        catch(err){error.textContent=err.message;}
      };
      panel.append(title,help,field,error,preset,cancel,save);
      try {
        field.value=await electron.ipcRenderer.invoke("miku:prompt-get",editMode);
        panel.setAttribute("aria-label",title.textContent);
        document.body.append(panel);panel.showModal();field.focus();
        cancel.onclick=()=>panel.close();
        panel.onclose=()=>{panel.remove();editPrompt.disabled=false;editPrompt.focus();};
        save.onclick=async()=>{
          save.disabled=true;
          try {await electron.ipcRenderer.invoke("miku:prompt-save",field.value,editMode);panel.close();status.textContent="기본 지시를 저장했어.";}
          catch(err){error.textContent=err.message;save.disabled=false;}
        };
      } catch(err){panel.remove();editPrompt.disabled=false;status.textContent=err.message;}
    };
    /* MIKU_SPEECH_UI */
    button.onclick=async e=>{
      if(!e.isTrusted)return;
      if(phase==="recording"){stop();return;}
      if(phase!=="idle")return;
      halt();phase="arming";button.disabled=true;language.disabled=true;attached=bar.parentNode;startURL=location.href;
      status.textContent="마이크 준비 중";backup.hidden=true;
      try{
        if(!await electron.ipcRenderer.invoke("miku:voice-ready"))throw Error("시스템 설정에서 마이크 권한을 허용해 줘.");
        stream=await navigator.mediaDevices.getUserMedia({audio:true,video:false});
        if(!attached?.isConnected || startURL!==location.href)throw Error("대화가 바뀌었어. 다시 눌러 줘.");
        recorder=new MediaRecorder(stream,{mimeType:"audio/webm;codecs=opus",audioBitsPerSecond:64000});
        const chunks=[];
        recorder.ondataavailable=ev=>{if(ev.data.size)chunks.push(ev.data);};
        recorder.onstop=async()=>{
          release();
          try{
            const decoder=new OfflineAudioContext(1,1,16000);
            const decoded=await decoder.decodeAudioData(await new Blob(chunks).arrayBuffer());
            const mono=new Float32Array(decoded.length);
            for(let c=0;c<decoded.numberOfChannels;c++){
              const channel=decoded.getChannelData(c);
              for(let i=0;i<mono.length;i++)mono[i]+=channel[i]/decoded.numberOfChannels;
            }
            const pcm=Int16Array.from(mono,v=>Math.round(Math.max(-1,Math.min(1,v))*(v<0?32768:32767)));
            const transcript=await electron.ipcRenderer.invoke("miku:transcribe",pcm,language.value);
            const input=attached?.isConnected && startURL===location.href && editor(attached);
            let inserted=false;
            if(input){
              input.focus();
              inserted=document.execCommand("insertText",false,transcript);
            }
            if(!inserted){backup.value=transcript;backup.hidden=false;}
            status.textContent=inserted?"인식 완료 · 확인하고 보내 줘.":"아래 인식 결과를 복사해 줘.";
          }catch(err){status.textContent=err.message;}
          finally{idle();}
        };
        recorder.onerror=()=>{status.textContent="녹음 오류 · 마이크를 확인해 줘.";};
        recorder.start();
        phase="recording";button.disabled=false;button.setAttribute("aria-label","녹음 끝내기");button.dataset.recording="true";
        status.textContent="듣고 있어…";timer=setTimeout(stop,60000);
      }catch(err){release();idle();status.textContent=err.message;}
    };
    window.addEventListener("pagehide",()=>{if(recorder)recorder.onstop=null;release();},{once:true});
    new MutationObserver(place).observe(document.body,{childList:true,subtree:true,attributes:true,attributeFilter:["class"]});
    place();
  };
  if(document.readyState==="loading")addEventListener("DOMContentLoaded",mountVoice,{once:true});else mountVoice();
}

if(window.top===window && location.protocol==="dsh-app:" && location.hostname==="app"){
  let timer, sequence=0;
  document.addEventListener("click",async event=>{
    const button=event.target.closest?.("button[data-miku-codex]");
    if(!event.isTrusted || !button)return;
    const row=button.closest("section");
    const label=row.querySelector("[data-miku-codex-status]");
    const invoke=action=>electron.ipcRenderer.invoke("miku:codex",action);
    if(button.dataset.mikuCodex==="open"){await invoke("open");return;}
    const ticket=++sequence;
    clearTimeout(timer);
    const start=row.querySelector('[data-miku-codex="start"]');
    const cancel=row.querySelector('[data-miku-codex="cancel"]');
    const open=row.querySelector('[data-miku-codex="open"]');
    async function update(action){
      if(!row.isConnected || ticket!==sequence)return;
      try{
        start.disabled=true;
        const {phase,code}=await invoke(action);
        if(ticket!==sequence || !row.isConnected)return;
        start.disabled=phase==="waiting";cancel.hidden=!start.disabled;open.hidden=!start.disabled||!code;
        label.textContent=phase==="waiting" ? (code ? "OpenAI 인증 페이지에 입력할 코드: "+code : "인증 코드 준비 중…") :
          phase==="connected" ? "연결 완료 · 새 세션에서 ChatGPT (Codex) 모델을 선택하세요." :
          phase==="cancelled" ? "인증을 취소했어요." : "인증을 완료하지 못했어요. 계정의 기기 코드 인증 설정을 확인하고 다시 시도하세요.";
        if(phase==="waiting")timer=setTimeout(()=>update("status"),1200);
      }catch{start.disabled=false;cancel.hidden=open.hidden=true;label.textContent="Codex 인증 서비스를 확인할 수 없어요. 다시 시도하세요.";}
    }
    await update(button.dataset.mikuCodex);
  });
}
