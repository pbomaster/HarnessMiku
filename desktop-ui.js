    const login=document.createElement("input");
    login.type="checkbox";
    const loginLabel=document.createElement("label");
    loginLabel.append(login," 로그인할 때 미쿠 띄우기");
    const petButton=document.createElement("button");
    petButton.type="button";petButton.textContent="바탕화면 미쿠";
    bar.append(loginLabel,petButton);
    const localPanel=document.createElement("details");
    const localTitle=document.createElement("summary");localTitle.textContent="llama.cpp 연결";
    const portField=document.createElement("input");
    portField.type="number";portField.min="1";portField.max="65535";portField.value="8080";
    portField.setAttribute("aria-label","로컬 llama-server 포트");
    const discover=document.createElement("button");discover.type="button";discover.textContent="모델 확인";
    const guidance=document.createElement("p");guidance.setAttribute("role","status");
    discover.onclick=async()=>{
      discover.disabled=true;
      try{
        const result=await electron.ipcRenderer.invoke("miku:llama-models",portField.valueAsNumber);
        guidance.textContent="설정 → 모델 → 사용자 지정 API에 "+result.base+" 및 OpenAI Chat Completions를 등록하세요. "+
          (result.auth?"이 서버에 설정한 전용 키와 모델 ID를 입력하세요.":"모델 ID: "+(result.ids.join(", ")||"없음"));
      }catch{guidance.textContent="llama-server 실행 상태와 포트를 확인하세요.";}
      finally{discover.disabled=false;}
    };
    localPanel.append(localTitle,portField,discover,guidance);bar.append(localPanel);
    const dock=document.createElement("nav");
    dock.id="miku-pet-dock";
    const full=document.createElement("button");
    full.textContent="전체 채팅";
    const petMenu=document.createElement("div"),petToggle=document.createElement("button");
    petMenu.id="miku-pet-menu";petMenu.hidden=true;
    petToggle.id="miku-pet-toggle";petToggle.type="button";
    petToggle.title="미쿠 메뉴";petToggle.setAttribute("aria-label","미쿠 메뉴");
    petToggle.setAttribute("aria-controls",petMenu.id);
    petToggle.setAttribute("aria-expanded","false");
    petToggle.innerHTML='<svg aria-hidden="true" width="16" height="16" viewBox="0 0 16 16"><path d="m3 10 5-5 5 5" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>';
    const workspaceHost=document.createElement("div");
    workspaceHost.id="miku-pet-workspaces";
    petMenu.append(full,workspaceHost);dock.append(petToggle,petMenu);document.body.append(dock);
    function showPetMenu(open){
      if(open)dock.style.setProperty("--miku-pet-input-height",((document.querySelector(".dsc-composer")?.offsetHeight||32)+6)+"px");
      petMenu.hidden=!open;
      document.dispatchEvent(new Event("miku-workspace-menu"));
      petToggle.setAttribute("aria-expanded",String(open));
    }
    petToggle.onclick=()=>showPetMenu(petMenu.hidden);
    document.addEventListener("pointerdown",event=>{
      if(!petMenu.hidden && !dock.contains(event.target) && !event.target.closest?.('[role="menu"],[role="dialog"],[role="listbox"],[popover]'))showPetMenu(false);
    },true);
    window.addEventListener("blur",()=>{if(!petMenu.hidden)showPetMenu(false);});
    document.addEventListener("keydown",event=>{
      if(event.key==="Escape" && !event.defaultPrevented && !petMenu.hidden){showPetMenu(false);petToggle.focus();}
    });
    const page=document.documentElement;
    const sizeLabel=document.createElement("label"),sizeSelect=document.createElement("select");
    sizeLabel.className="miku-size-control";
    sizeLabel.append("미쿠 크기 ",sizeSelect);
    for(const value of [50,75,100,125,150])sizeSelect.add(new Option(value+"%",String(value)));
    sizeSelect.setAttribute("aria-label","미쿠 크기");
    const frameLabel=document.createElement("label"),frameSelect=document.createElement("select");
    frameLabel.className="miku-size-control";
    frameLabel.append("표시 범위 ",frameSelect);
    frameSelect.setAttribute("aria-label","미쿠 표시 범위");
    frameSelect.add(new Option("상반신","bust"));frameSelect.add(new Option("전신","full"));
    function frameKey(){return page.classList.contains("miku-desktop")?"miku.frame.pet":"miku.frame.chat";}
    frameSelect.onchange=()=>{
      localStorage.setItem(frameKey(),frameSelect.value);
      applySize(sizeSelect.value);
    };
    function sizeKey(){return page.classList.contains("miku-desktop")?"miku.size.pet":"miku.size.chat";}
    function applySize(value){
      sizeSelect.value=value;
      if(!sizeSelect.value)sizeSelect.value="100";
      page.dataset.mikuSize=sizeSelect.value;
      page.dataset.mikuFrame=frameSelect.value;
      if(page.classList.contains("miku-desktop"))ipc.send("miku:pet-size",Number(sizeSelect.value),frameSelect.value);
    }
    sizeSelect.onchange=()=>{
      localStorage.setItem(sizeKey(),sizeSelect.value);
      applySize(sizeSelect.value);
    };
    let regionTimer, regionSignature;
    function setDesktop(on){
      page.classList.toggle("miku-desktop",on);
      showPetMenu(false);
      (on?petMenu:options).append(sizeLabel,frameLabel);
      frameSelect.value=localStorage.getItem(frameKey())==="full"?"full":"bust";
      applySize(localStorage.getItem(sizeKey())||"100");

      clearInterval(regionTimer);regionSignature=null;
      if(on){publishPetRegions();regionTimer=setInterval(publishPetRegions,80);}
    }
    const ipc=electron.ipcRenderer;
    function setDockInset(value){page.style.setProperty("--miku-dock-inset",Math.max(0,Number(value)||0)+"px");}
    ipc.on("miku:pet-dock-inset",(_,value)=>setDockInset(value));
    ipc.on("miku:desktop-mode",(_,on)=>setDesktop(on));
    ipc.invoke("miku:desktop-state").then(state=>{login.checked=state.login;setDockInset(state.dockInset);setDesktop(state.pet);}).catch(e=>status.textContent=e.message);
    login.onchange=async()=>{
      const requested=login.checked;login.disabled=true;
      try{login.checked=await ipc.invoke("miku:desktop-login",requested);}
      catch(e){login.checked=!requested;status.textContent=e.message;}
      finally{login.disabled=false;}
    };
    petButton.onclick=()=>ipc.invoke("miku:desktop-mode",true);
    full.onclick=()=>ipc.invoke("miku:desktop-mode",false);
    function publishPetRegions(){
      if(!petMenu.hidden){
        const height=((document.querySelector(".dsc-composer")?.offsetHeight||32)+6)+"px";
        if(dock.style.getPropertyValue("--miku-pet-input-height")!==height)dock.style.setProperty("--miku-pet-input-height",height);
      }
      const selectors=["#dsc-stage","#miku-pet-toggle","#miku-pet-menu","#miku-pinned-recap",".dsc-composer"];
      const pickerOpen=document.querySelector('.dsc-composer [aria-haspopup="menu"][aria-expanded="true"]');
      if(pickerOpen || !petMenu.hidden)selectors.push('[role="menu"]','[role="dialog"]','[role="listbox"]','[popover]:popover-open');
      const regions=[];
      for(const el of document.querySelectorAll(selectors.join(","))){
        if(!el.checkVisibility({visibilityProperty:true}))continue;
        const r=el.getBoundingClientRect();
        if(r.width && r.height)regions.push([r.left,r.top,r.right,r.bottom]);
      }
      const signature=JSON.stringify(regions);
      if(signature!==regionSignature){regionSignature=signature;ipc.send("miku:pet-regions",regions);}
    }

    const options=document.createElement("div");
    options.id="miku-options";
    options.append(...Array.from(bar.children).filter(el=>el!==button && el!==petButton));
    const toggle=document.createElement("button"),balance=document.createElement("button");
    toggle.type=balance.type="button";
    function icon(control,label,paths){
      control.title=label;control.setAttribute("aria-label",label);
      control.classList.add("miku-icon");
      control.innerHTML='<svg aria-hidden="true" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">'+paths+'</svg>';
    }
    icon(button,"음성 입력",'<rect x="9" y="2" width="6" height="13" rx="3"/><path d="M5 11a7 7 0 0 0 14 0M12 18v4m-3 0h6"/>');
    icon(toggle,"입력 옵션",'<path d="m6 9 6 6 6-6"/>');
    icon(petButton,"바탕화면 미쿠",'<rect x="2" y="3" width="20" height="14" rx="2"/><path d="M12 17v4m-4 0h8"/>');
    petButton.classList.add("miku-monitor");
    balance.className="miku-balance";balance.textContent="—";
    bar.append(button,toggle,petButton,balance,options);
    toggle.setAttribute("aria-controls",options.id);
    function setOptions(open){
      options.hidden=!open;
      toggle.setAttribute("aria-expanded",String(open));
      bar.closest(".dsc-composer")?.toggleAttribute("data-miku-options",open);
    }
    bar.addEventListener("click",event=>event.stopPropagation());
    setOptions(false);
    toggle.onclick=()=>setOptions(options.hidden);
    bar.addEventListener("keydown",e=>{if(e.key==="Escape"&&!options.hidden){setOptions(false);toggle.focus();}});
    function compactAmount(value){
      const n=Number(value);
      if(!Number.isFinite(n))return "—";
      const units=["","K","M","B","T"];
      for(let i=0;i<units.length;i++){
        const scaled=n/1000**i;
        if(Math.abs(scaled)>=1000)continue;
        for(let digits=2;digits>=0;digits--){
          const rounded=Number(scaled.toFixed(digits));
          if(Math.abs(rounded)>=1000)break;
          const label=String(rounded)+units[i];
          if(label.replace(".","").length<=4)return label;
        }
      }
      return "∞";
    }
    let balanceBusy=false,lastCheck=0;
    async function refreshBalance(force=false){
      if(balanceBusy||(!force && Date.now()-lastCheck<60000))return;
      balanceBusy=true;lastCheck=Date.now();
      try{
        const result=await ipc.invoke("miku:balance");
        const rows=result.balances||[];
        const main=rows.find(r=>Number(r.amount)>0)||rows[0];
        balance.textContent=main?compactAmount(main.amount):"—";
        balance.title=main?"DeepSeek · "+rows.map(r=>r.currency+" "+r.amount).join(" / ")+" · 클릭해서 새로고침":result.error;
      }catch{balance.textContent="—";balance.title="잔액 조회 실패 · 클릭해서 다시 시도";}
      finally{balanceBusy=false;balance.setAttribute("aria-label",balance.title);}
    }
    balance.onclick=()=>refreshBalance(true);
    setInterval(()=>{if(!document.hidden && !page.classList.contains("miku-desktop") && bar.isConnected)refreshBalance();},60000);
    new MutationObserver(()=>{
      button.title=button.getAttribute("aria-label")+" · "+status.textContent;
      if(!backup.hidden || /실패|오류|권한|다시|확인해 줘/.test(status.textContent))setOptions(true);
    }).observe(status,{childList:true,subtree:true,characterData:true});
