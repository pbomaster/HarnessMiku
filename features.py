import json
from pathlib import Path
import re
import shutil

KIT=Path(__file__).parent
MODULES=Path("dsh/node_modules/@deepseek-ai")
PROMPT=MODULES/"dsh-system-prompt/lib/index.js"


def adapt_prompt(js):
    # Add a live, literal section wherever the backend assembles its standard system prompt.
    pattern=r"""super\(\s*([\w$]+)\s*,\s*["']systemPrompt["']\s*\)\s*;?"""
    addition=""";
        this.section({name:"miku:user-default",order:10210,interpolate:false,text:()=>{
          try {return mikuRead(mikuJoin(process.platform==="win32" ? (process.env.APPDATA || mikuJoin(mikuHome(),"AppData","Roaming")) : mikuJoin(mikuHome(),"Library","Application Support"),"Harness Miku","system-prompt.txt"),"utf8");}
          catch(error){if(error.code==="ENOENT")return "";throw error;}
        }});
"""
    default=json.dumps((KIT/"retry-persona.txt").read_text().strip(),ensure_ascii=False)
    addition=addition.replace('if(error.code==="ENOENT")return "";', 'if(error.code==="ENOENT")return '+default+';')
    rule="일반 대화의 최종 답변은 빈 줄 뒤에 짧은 마지막 문단으로 마쳐라. 그 문단은 미쿠 말풍선에도 그대로 표시된다. 현재 시스템 지시의 말투·언어를 본문과 동일하게 사용해, 이번 질문에 대한 결론이나 대화의 요지를 독립적으로 이해할 수 있는 한두 문장으로 직접 써라. 별도 제목이나 요약 표지는 붙이지 말라. 이미 짧은 답은 그 자체가 말풍선이므로 반복하지 말라. 최종 사용자용 마무리 문단을 반드시 새 줄에서 <!--miku-recap-->와 <!--/miku-recap--> 사이에 적고 그 뒤에는 아무것도 쓰지 마라. 짧은 답은 그 답 하나만 이 표지로 감싸라. 분석, 사고 메모, 도구 호출, 중간 진행 보고에서는 표지를 쓰지 마라. 사용자가 코드만, JSON만 등 엄격한 형식을 지정하면 표지를 생략하고 그 형식을 우선하라."
    tones=json.loads((KIT/"recap-tones.json").read_text())
    rule=rule.replace("사이에 적고 그 뒤에는 아무것도 쓰지 마라.", "사이에 적어라.")
    rule+=" 요약 닫는 표지 바로 뒤에 <!--miku-tone:TAG-->를 하나 붙여 마쳐라. TAG는 이번 요약의 의미에 맞는 Drama 3 연기 태그 이름 하나로 바꿔라. " + " ".join(f"{key} = {value}" for key,value in tones.items())
    rule+=" 표지 안 요약에는 실제로 입 밖에 낼 말만 써라. 연기 설명, 괄호 지문, 태그, 필드 이름은 대사에 넣지 마라. 예: <!--miku-recap-->첫 번째 파일은 돌아왔어. 두 번째 칸은 아직 비워 둘게.<!--/miku-recap--><!--miku-tone:slow-->"
    addition+='this.section({name:"miku:bubble-format",order:10211,interpolate:false,text:'+json.dumps(rule,ensure_ascii=False)+'});'
    mac_tools = ("On macOS, the confined bash shell may reject Apple Events (-10004) and screen capture "
                 "even when macOS has granted Harness Miku access. For a requested app-control or screen/system-audio "
                 "capture that fails under confinement, retry only the affected command using bash with "
                 "sandbox_permissions=danger-full-access and a specific justification via the normal approval flow. "
                 "If that call still fails, check Automation for the specific target or Screen & System Audio Recording "
                 "for Harness Miku, as appropriate. Do not reset grants or re-sign the running app.")
    addition+='this.section({name:"miku:mac-permissions",order:10212,interpolate:false,text:process.platform==="darwin"?'+json.dumps(mac_tools)+':""});'
    js,n=re.subn(pattern,lambda m:m.group()+addition,js)
    if n!=1: raise ValueError("Harness 시스템 프롬프트 생성자를 식별하지 못했습니다.")
    return 'import {readFileSync as mikuRead} from "node:fs";\nimport {homedir as mikuHome} from "node:os";\nimport {join as mikuJoin} from "node:path";\n'+js


def adapt_ui(overlay,dest):
    shutil.copyfile(KIT/"miku-mark.svg",dest/"miku-mark.svg")
    def module(name):return overlay/MODULES/("dsh-client-ui-"+name)/"lib/client.js"
    # Render the upstream account component with its own auth service and locale.
    account=module("settings-account")
    source=account.read_text()
    anchor='ctx.slots.inject("settings.models.sign-in",'
    if source.count(anchor)!=1:
        raise ValueError("지원하지 않는 계정 설정 모듈")
    source=source.replace(anchor,'''ctx.slots.inject("settings.models.footer", () => ctx.slots.register({
                name: "settings.models.footer",
                id: "miku.deepseek-account",
                locale: "settings.account",
                inject: () => operations
            }, props => (0,react_jsx_runtime.jsxs)(react.Fragment,{children:[
                (0,react_jsx_runtime.jsx)(AccountSection,props),
                (0,react_jsx_runtime.jsxs)("section",{"aria-label":"ChatGPT 구독",children:[
                    (0,react_jsx_runtime.jsx)("button",{type:"button","data-miku-codex":"start",children:"ChatGPT 구독으로 로그인"}),
                    (0,react_jsx_runtime.jsx)("span",{role:"status","data-miku-codex-status":""}),
                    (0,react_jsx_runtime.jsx)("button",{hidden:true,type:"button","data-miku-codex":"open",children:"OpenAI 인증 페이지 열기"}),
                    (0,react_jsx_runtime.jsx)("button",{hidden:true,type:"button","data-miku-codex":"cancel",children:"취소"})
                ]})
            ]})));
            '''+anchor)
    account.write_text(source)
    sidebar=module("sidebar")
    js=sidebar.read_text()
    def logo(size):
        return '(0, react_jsx_runtime.jsx)("img",{src:"/assets/dsc/miku-mark.svg",alt:"Harness Miku",width:'+str(size)+',height:'+str(size)+'})'
    mark='renderSlot("sidebar.brand.mark", { size: 24 }, { fallback: (0, react_jsx_runtime.jsx)(_deepseek_ai_dsh_client_ui_primitives.FishLogo, { size: 24 }) })'
    if js.count(mark)!=2: raise ValueError("Sidebar branding mismatch")
    js=js.replace(mark,logo(24))
    a=js.index('children: renderSlot("sidebar.brand.name"');b=js.index('}) })',a)+5
    js=js[:a]+'children: (0, react_jsx_runtime.jsx)("span",{className:"miku-wordmark",children:"Harness Miku"})'+js[b:]
    hook="const panels = usePanels((snapshot) => snapshot);"
    start=js.index('children: renderSlot("sidebar.workspaces", {')
    end=js.index("\n",js.index("})",js.index("if (collapsed) toggleSidebar();",start))+2)
    slot=js[start+len("children: "):end]
    if js.count(hook)!=1 or not slot.endswith("})"):raise ValueError("Workspace slot mismatch")
    js=js[:start]+"children: !petMode ? "+slot+' : petHost ? require("react-dom").createPortal(renderSlot("sidebar.workspaces",{wide:true,expandSidebar:()=>{}}),petHost) : null'+js[end:]
    js=js.replace(hook,hook+"""
            const petState=react.useSyncExternalStore(callback=>{
                document.addEventListener("miku-workspace-menu",callback);
                return ()=>document.removeEventListener("miku-workspace-menu",callback);
            },()=>document.documentElement.classList.contains("miku-desktop") ?
                (document.getElementById("miku-pet-menu")?.hidden===false ? "open" : "closed") : "chat");
            const petMode=petState!=="chat";
            const petHost=petState==="open" && document.getElementById("miku-pet-workspaces");
""")
    sidebar.write_text(js)
    hero=module("conversation");js=hero.read_text()
    a=js.index('renderSlot("conversation.hero.brand.mark"');b=js.index('HeroFish, { hovering }) })',a)+len('HeroFish, { hovering }) })')
    js=js[:a]+logo(34)+js[b:]
    trigger="const pickerAnchor = (0, react.useRef)(null);"
    ref="anchorRef: pickerAnchor,"
    if js.count(trigger)!=1 or js.count(ref)!=1:raise ValueError("Workspace picker anchor mismatch")
    js=js.replace(trigger,trigger+"""
            const visiblePickerAnchor=react.useMemo(()=>({
                get current(){
                    const chip=pickerAnchor.current;
                    if(!document.documentElement.classList.contains("miku-desktop"))return chip;
                    const seat=chip?.closest("[data-composer-seat]");
                    return seat?.querySelector("[data-composer-card]") ?? document.querySelector(".dsc-composer") ?? chip;
                }
            }),[]);
""").replace(ref,"anchorRef: visiblePickerAnchor,")
    anchor="const fileInputRef = (0, react.useRef)(null);"
    if js.count(anchor)!=1:raise ValueError("Composer file intake mismatch")
    hero.write_text(js.replace(anchor,anchor+"""
            react.useEffect(()=>{
                const card=cardRef.current;
                if(!card || !canAcceptDrop)return;
                card.dataset.mikuDropReady="true";
                const receive=e=>{
                    if(!document.documentElement.classList.contains("miku-desktop"))return;
                    const files=[],directories=new Set();
                    for(const item of e.dataTransfer.items){
                        if(item.kind!=="file")continue;
                        const file=item.getAsFile();
                        if(!file)continue;
                        files.push(file);
                        if(item.webkitGetAsEntry?.()?.isDirectory)directories.add(file);
                    }
                    intakeFiles(files.length?files:Array.from(e.dataTransfer.files),directories);
                };
                card.addEventListener("miku-pet-files",receive);
                return ()=>{delete card.dataset.mikuDropReady;card.removeEventListener("miku-pet-files",receive);};
            },[canAcceptDrop,intakeFiles]);
"""))
    chat=module("chat");js=chat.read_text()
    anchor='"data-actions-reveal": endsWithResponse ? "always" : "hover",'
    if js.count(anchor)!=1:raise ValueError("Turn tail mismatch")
    tail="branchUnavailable: closing === null || latestTranscriptSeq !== closing.finalNode.seq,"
    helper="function assistantText(blocks) {"
    if js.count(tail)!=1 or js.count(helper)!=1: raise ValueError("Turn completion mismatch")
    js=js.replace(tail,tail+'\n                mikuFinished: closing !== null && closing === finalized.at(-1) && !["error","aborted","interrupted","max-tokens"].includes(end.event.data.reason.kind),')
    view=js.index("function AssistantMarkdown(")
    insertion=js.index("const last = blocks.length - 1;",view)
    js=js[:insertion]+"blocks = mikuDisplayBlocks(blocks, streaming);\n            "+js[insertion:]
    js=js.replace(helper,helper+"\n            blocks = mikuDisplayBlocks(blocks);")
    js=js.replace(helper,(KIT/"recap.js").read_text().replace("MIKU_TONE_NAMES",json.dumps(list(json.loads((KIT/"recap-tones.json").read_text()))))+"\n"+helper)
    chat.write_text(js.replace(anchor,anchor+'\n                "data-miku-final": endsWithResponse && data.mikuFinished && !data.branchUnavailable && !hasLaterChatNode ? mikuSpokenRecap(closing.blocks) || undefined : undefined,\n                "data-miku-id":messageId,'))
    index=dest.parent.parent/"index.html"
    index.write_text(index.read_text().replace("<title>DeepSeek Harness</title>","<title>Harness Miku</title>").replace("./favicon-dark.svg","./assets/dsc/miku-mark.svg").replace("./favicon.svg","./assets/dsc/miku-mark.svg"))


def adapt_bubble(js):
    js=js.replace("      let curK =",(KIT/"pinned-recap.js").read_text()+"\n      let curK =")
    js=js.replace('veil.style.cssText =', 'veil.id="miku-intro-veil"; veil.style.cssText =')
    # In chat, react only to a completed click on exposed background. Never cancel
    # Harness input. The floating pet retains its original model hit testing.
    js=js.replace("      let swallowClick = false;", """      document.addEventListener("click", e => {
        if (document.documentElement.classList.contains("miku-desktop") ||
            e.defaultPrevented || e.button !== 0 || !mikuChatBackdrop(e.target)) return;
        if (!pinnedRecap.hidden && document.elementsFromPoint(e.clientX,e.clientY).includes(pinnedRecap)) {
          clearRecap();
          return;
        }
        if (intro.phase === "center") { intro.skip = true; return; }
        const hit = hitAt(e.clientX, e.clientY);
        if (hit) onTouch(...hit);
      });
      let swallowClick = false;""")
    js=js.replace("if (e.button !== 0) return;", """if (!document.documentElement.classList.contains("miku-desktop") ||
            e.button !== 0 || e.target.closest?.("#miku-pinned-recap,#miku-pet-dock,.dsc-composer")) return;""")
    js=js.replace('if (now - hoverCheck < 80) return;', 'if (!document.documentElement.classList.contains("miku-desktop") && now - hoverCheck < 80) return;')
    js=js.replace('const over = !!hitAt(e.clientX, e.clientY);', 'const over = (document.documentElement.classList.contains("miku-desktop") || mikuChatBackdrop(e.target)) && !!hitAt(e.clientX, e.clientY);')
    # Remove the upstream reasoning-DOM reader and its observer call entirely.
    a=js.index("      // 추론 혼잣말:")
    b=js.index("      // 시작 인사",a)
    js=js[:a]+js[b:]
    js=js.replace("if (nowRunning && !waitingKind) mutterCheck();","")
    start=js.index("      const homePose =")
    end=js.index("      const centerPose =", start)
    js=js[:start]+(KIT/"layout.js").read_text()+"""
      const homePose=()=>mikuHome(innerWidth,innerHeight,document.querySelector(".dsc-composer"),W,H,visW,visH,fleeX);
"""+js[end:]
    js=js.replace('let introOn = intro.phase', 'if(intro.phase!=="done" && (document.documentElement.classList.contains("miku-desktop") || document.querySelector("[data-chat-flow]"))){intro.phase="done";veil.remove();setRes(1);bubble.style.fontSize="";bubble.style.padding="";} let introOn = intro.phase')
    start=js.index("        const show = introOn ||")
    end=js.index("        curK = k;",start)
    js=js[:start]+'        canvas.style.display = bubble.style.display = "block";\n'+js[end:]
    start=js.index("        const card = home.card;")
    end=js.index("      const raf =", start)
    js=js[:start]+"""        const lane=mikuBubbleLane(home.card);
        mikuPlaceBubble(bubble, innerWidth, innerHeight, headTop, x+W*k/2, home.card,lane);
        if (!pinnedRecap.hidden) {
          const anchor=bubble.classList.contains("show") && bubble.style.display!=="none" ? Math.min(headTop,bubble.getBoundingClientRect().top) : headTop;
          mikuPlaceBubble(pinnedRecap,innerWidth,innerHeight,anchor,Math.min(innerWidth-12,x+W*k/2),home.card,lane);
        }
      };
"""+js[end:]
    code="""
      const lastFinal=()=>[...document.querySelectorAll("[data-miku-final]")].at(-1);
      const keyOf=node=>node && JSON.stringify([node.dataset.mikuId,node.dataset.turnTail,node.dataset.mikuFinal]);
      let priorFinal=keyOf(lastFinal()), turnLocation=location.href, generation=0;
      function recapWhenReady(token, epoch, tries=0){
        if(epoch!==inputEpoch || token!==generation || running || turnLocation!==location.href)return;
        const node=lastFinal();
        if(node && keyOf(node)!==priorFinal && node.dataset.mikuFinal.trim()){
          const {text:summary,tone}=JSON.parse(node.dataset.mikuFinal);
          if(summary){
            hush();
            pinRecap(summary,tone);
            startTalk(summary, Math.min(8000, summary.length*100), false);
            return;
          }
        }
        if(tries<10)setTimeout(()=>recapWhenReady(token,epoch,tries+1),150);

      }
"""
    js=js.replace('      window.__dsc =',code+'\n      window.__dsc =')
    js=js.replace('running = true; lastError', 'clearRecap(); generation++; priorFinal=keyOf(lastFinal()); turnLocation=location.href; running = true; lastError')
    js=js.replace('running = false;\n          setExp', 'const finishedGeneration=generation; const finishedEpoch=inputEpoch; running = false;\n          setExp').replace('if (running) return;\n            if (performance.now()', 'if (running || generation!==finishedGeneration || turnLocation!==location.href) return;\n            if (performance.now()')
    js=js.replace('say(TEXT.done, 4000);','recapWhenReady(finishedGeneration,finishedEpoch);')
    marker="setInterval(() => {\n        const nowRunning"
    if js.count(marker)!=1: raise ValueError("Completion observer mismatch")
    js=js.replace(marker,"const observeWork = () => {\n        const nowRunning")
    return js.replace("      }, 400);", """      };
      setInterval(observeWork,400);
      // Observe the send/stop swap too, including responses shorter than one polling interval.
      const fastWork=new MutationObserver(()=>{
        if (!!document.querySelector(UI.stop)!==running) observeWork();
      });
      fastWork.observe(document.body,{subtree:true,childList:true,attributes:true,attributeFilter:["aria-label"]});""")
