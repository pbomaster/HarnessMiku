    const tts=document.createElement("button");
    tts.type="button";tts.textContent="미쿠 목소리 켜기";
    const voiceId=document.createElement("input");
    voiceId.setAttribute("aria-label","Fish Audio 음성 ID");
    voiceId.title="사용 권한이 있는 참조 음성 모델의 Fish Audio ID";
    voiceId.value=localStorage.getItem("miku.tts-id")||"";
    voiceId.placeholder="참조 음성 ID · 32자리";
    voiceId.hidden=true;
    const pick=document.createElement("button");pick.type="button";pick.textContent="음성 ID";
    voiceId.id="miku-voice-id";pick.setAttribute("aria-controls",voiceId.id);pick.setAttribute("aria-expanded","false");
    pick.onclick=()=>{voiceId.hidden=!voiceId.hidden;pick.setAttribute("aria-expanded",String(!voiceId.hidden));if(!voiceId.hidden)voiceId.focus();};
    const engine=document.createElement("select");
    engine.setAttribute("aria-label","Fish Audio 합성 모델");
    for(const [id,name] of [["s2.1-pro-free","S2.1 Pro Free"],["s2.1-pro","S2.1 Pro"],["drama-3","Drama 3"]]){
      engine.add(new Option(name,id));
    }
    engine.value=localStorage.getItem("miku.tts-engine")||"s2.1-pro-free";
    if(!engine.value)engine.value="s2.1-pro-free";
    const label=document.createElement("label");
    label.append("합성 모델 ",engine);
    const preview=document.createElement("button");
    preview.type="button";preview.textContent="샘플 듣기";preview.disabled=true;
    const sample="네 대답 칸은 비워 뒀어. 그 연필 자국? 아… 그건 신경 쓰지 마.";
    engine.onchange=()=>{
      halt();
      localStorage.setItem("miku.tts-engine",engine.value);
      status.textContent=engine.selectedOptions[0].text+" 선택";
    };
    preview.onclick=e=>{if(e.isTrusted)readLine(sample);};
    const keyButton=document.createElement("button");
    keyButton.type="button";keyButton.textContent="Fish API 키";
    keyButton.onclick=async event=>{
      if(!event.isTrusted || tts.disabled)return;
      keyButton.disabled=true;tts.disabled=true;
      try{
        if(await electron.ipcRenderer.invoke("miku:tts-enable",true)){
          status.textContent="Fish API 키를 저장했어.";
          if(!validVoiceId())showVoiceId();
        }
      }catch(err){status.textContent=err.message;}
      finally{keyButton.disabled=false;tts.disabled=false;}
    };
    function validVoiceId(){return /^[0-9a-f]{32}$/i.test(voiceId.value.trim());}
    function showVoiceId(){
      voiceId.hidden=false;pick.setAttribute("aria-expanded","true");voiceId.focus();
      status.textContent="사용할 Fish 참조 음성의 32자리 ID를 입력한 뒤 목소리를 켜 줘.";
    }
    bar.append(tts,keyButton,pick,voiceId,label,preview);
    let enabled=false, generation=0, ctx, playing;
    let lipFrame=0;
    function lipEvent(state){
      document.dispatchEvent(new CustomEvent("miku-audio-mouth",{detail:JSON.stringify(state)}));
    }
    function stopPlayback(){
      cancelAnimationFrame(lipFrame);
      if(playing){playing.onended=null;playing.stop();playing.disconnect();playing=null;}
      lipEvent(null);
    }
    // Use voiced time for vowel progression, so silence never consumes a vowel.
    function mouthTrack(audio){
      const size=Math.max(1,Math.round(audio.sampleRate*.02));
      const levels=new Float32Array(Math.ceil(audio.length/size));
      for(let ch=0;ch<audio.numberOfChannels;ch++){
        const pcm=audio.getChannelData(ch);
        for(let i=0;i<pcm.length;i+=size){
          const end=Math.min(i+size,pcm.length);
          let power=0;
          for(let j=i;j<end;j++)power+=pcm[j]*pcm[j];
          const k=Math.floor(i/size);
          levels[k]=Math.max(levels[k],Math.sqrt(power/(end-i)));
        }
      }
      let peak=0;
      for(const level of levels)peak=Math.max(peak,level);
      const positions=new Uint32Array(levels.length);
      let voiced=0;
      for(let i=0;i<levels.length;i++){
        positions[i]=voiced;
        levels[i]=levels[i]>Math.max(.001,peak*.045) ? Math.min(1,Math.sqrt(levels[i]/peak)*1.35) : 0;
        if(levels[i])voiced++;
      }
      return elapsed=>{
        const k=Math.floor(elapsed*audio.sampleRate/size);
        return {level:levels[k]||0,progress:((positions[k]||0)+.5)/Math.max(1,voiced)};
      };
    }
    function halt(){
      generation++;stopPlayback();
      electron.ipcRenderer.invoke("miku:tts-stop").catch(()=>{});
    }
    async function readLine(text,tone=null){
      if(!enabled || phase!=="idle" || !text.trim())return;
      const ticket=++generation;
      stopPlayback();lipEvent({text});
      try{
        const bytes=await electron.ipcRenderer.invoke("miku:tts",text,voiceId.value.trim().toLowerCase(),engine.value,tone);
        if(ticket!==generation)return;
        const audio=await ctx.decodeAudioData(new Uint8Array(bytes).buffer);
        if(ticket!==generation)return;
        const node=ctx.createBufferSource();node.buffer=audio;node.connect(ctx.destination);
        const sampleMouth=mouthTrack(audio);
        const start=ctx.currentTime;
        function frame(){
          if(playing!==node)return;
          lipEvent(sampleMouth(ctx.currentTime-start));
          lipFrame=requestAnimationFrame(frame);
        }
        node.onended=()=>{if(playing===node){playing=null;node.disconnect();cancelAnimationFrame(lipFrame);lipEvent(null);}};
        playing=node;node.start(start);frame();
      } catch(err){if(ticket===generation){stopPlayback();enabled=false;preview.disabled=true;tts.textContent="미쿠 목소리 켜기";status.textContent=err.message;}}
    }
    tts.onclick=async e=>{
      if(!e.isTrusted)return;
      if(enabled){enabled=false;preview.disabled=true;halt();tts.textContent="미쿠 목소리 켜기";return;}
      tts.disabled=true;keyButton.disabled=true;
      try{
        if(!await electron.ipcRenderer.invoke("miku:tts-enable"))return;
        if(!validVoiceId()){showVoiceId();return;}
        if(!confirm("말풍선 대사와 요약을 Fish Audio로 보내 한국어 음성을 합성할까요?"))return;
        ctx??=new AudioContext();await ctx.resume();
        enabled=true;preview.disabled=false;
        localStorage.setItem("miku.tts-id",voiceId.value.trim().toLowerCase());
        tts.textContent="미쿠 목소리 끄기";status.textContent="미쿠 목소리를 켰어.";readLine(sample);
      }catch(err){status.textContent=err.message;}finally{tts.disabled=false;keyButton.disabled=false;}
    };
    document.addEventListener("miku-spoken-line",ev=>{if(typeof ev.detail==="string")readLine(ev.detail);});
    document.addEventListener("miku-spoken-recap",ev=>{
      let recap;
      try{recap=JSON.parse(ev.detail);}catch{return;}
      if(typeof recap?.text==="string" && typeof recap.tone==="string")readLine(recap.text,recap.tone);
    });
    window.addEventListener("pagehide",()=>{enabled=false;halt();ctx?.close();},{once:true});
