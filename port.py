"""Build a patched ASAR in the copied upstream macOS app; preserve native unpacked files."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import struct
import sys
import zipfile
from features import adapt_bubble, adapt_prompt, adapt_ui, PROMPT

FRONT = Path("dsh/node_modules/@deepseek-ai/dsh-web-frontend/dist/assets/dsc")
PREFIX = "RetrynowMiku/VTS Model File/"
EXP = {"loading":"side Blush","heart":"Star","blush":"Blush","sweat":"Sweat Drop",
       "dizzy":"Dead Eyes","tears":"Tears","squint":"Squinny Eyes","smug":"Fanged Smile","dark":"Gloom"}
REGIONS = {"head":["Part2","Part3","Part66","Part19","Part27","Part28"],
           "arm":["Part16","Part17","Part122","Part127","Part145","Part133"],
           "chest":["ArtMesh85_Skinning","ArtMesh86_Skinning"]}


def adapt_desktop(src,kit):
    def patch(old,new):
        nonlocal src
        if src.count(old)!=1: raise ValueError("Desktop window patch mismatch: "+old)
        src=src.replace(old,new)
    patch("async save(apiKey) {","async balanceRef(){return (await settingsAndReference()).ref;},\n        async save(apiKey) {")
    patch("width: 1280,","transparent: primary, acceptFirstMouse:true, width: 1280,")
    patch('const applyBackdrop = () => {','const applyBackdrop = () => { if(window.isAlwaysOnTop()){window.setVibrancy(null);window.setBackgroundColor("#00000000");return;}')
    patch('const shortcuts = installDesktopShortcuts(', (kit/"desktop-main.js").read_text()+'\nconst shortcuts = installDesktopShortcuts(')
    patch('if (activate) window.show();','if(mikuLoginLaunch){mikuLoginLaunch=false;mikuMode(true);window.showInactive();} else if (activate) window.show();')
    patch('await showWelcome();\n\t\t} else await enterWorkspace();','if(mikuLoginLaunch){mikuLoginLaunch=false;mikuMode(true);mainWindow.showInactive();}else await showWelcome();\n\t\t} else await enterWorkspace();')
    patch('const hide = () => {\n\t\t\t\tif (!quitting', 'if(enteredWorkspace && !mikuPet){mikuMode(true);return;}\n            const hide = () => {\n\t\t\t\tif (!quitting')
    patch('if (window === mainWindow && !enteredWorkspace) return;', 'if(mikuPet){mikuMode(false);if(!enteredWorkspace){openInitialWindow().catch(console.error);return;}} if (window === mainWindow && !enteredWorkspace) return;')
    patch('if (!hasVisibleWindows) focusPrimaryWindow();','if (!hasVisibleWindows || mikuPet) focusPrimaryWindow();')
    return src


def prepare(overlay, archive):
    dest = overlay / FRONT
    folder = dest / "miku"
    folder.mkdir()
    with zipfile.ZipFile(archive) as z:
        def get(name):
            info = z.getinfo(PREFIX+name)
            if info.file_size > 16*1024**2:
                raise ValueError("Unexpected model size")
            return z.read(info)
        doc = json.loads(get("RetrynowMiku.model3.json"))
        refs = doc["FileReferences"]
        # Read only the known model paths from the uploaded release.
        textures = [f"RetrynowMiku.4096/texture_{i:02}.png" for i in range(17)]
        if refs["Textures"] != textures or refs["Moc"] != "RetrynowMiku.moc3":
            raise ValueError("New1007-RetrynowMiku.zip 원본을 선택해 주세요.")
        paths = ["RetrynowMiku.moc3","RetrynowMiku.physics3.json","RetrynowMiku.cdi3.json",*textures]
        expected = json.loads(Path(__file__).with_name("hashes.json").read_text())
        for name in [*paths,*(name+".exp3.json" for name in EXP.values())]:
            if hashlib.sha256(get(name)).hexdigest()!=expected[name]:
                raise ValueError("지원하는 원본 모델 버전을 선택해 주세요.")
        # Preserve the creator's complete model directory, names and metadata.
        for info in z.infolist():
            if not info.filename.startswith(PREFIX) or info.is_dir():
                continue
            name=info.filename[len(PREFIX):]
            if not name or any(part in ("",".","..") for part in name.split("/")):
                raise ValueError("모델 경로가 올바르지 않습니다.")
            path=folder/name
            path.parent.mkdir(exist_ok=True,parents=True)
            path.write_bytes(get(name))
    js = dest/"dsc.js"
    s = js.read_text()
    def change(a,b):
        nonlocal s
        if s.count(a)!=1:
            raise RuntimeError("지원하지 않는 overlay 버전: "+a[:60])
        s=s.replace(a,b)
    kit = Path(__file__).parent
    # Only the upstream overlay supplies the original avatar and wallpaper.
    shutil.rmtree(dest/"model")
    (dest/"wallpaper.png").unlink()
    change('BASE + "model/model.model3.json"', 'BASE + "miku/RetrynowMiku.model3.json"')
    change('${BASE}model/exp/${f}', '${BASE}miku/${encodeURIComponent(('+json.dumps(EXP)+')[f])}')
    dialogue = json.loads((kit/"lines.json").read_text())
    for key, value in dialogue.items():
        original = re.search(r"const " + key + r" = \{.*?\n *\};", s, re.S)
        if not original:
            raise ValueError("Missing dialogue section " + key)
        change(original.group(), "const " + key + " = " + json.dumps(value, ensure_ascii=False) + ";")
    change("const W = 300, H = 300;", "const W = 300; let H = 300;")
    change("const visW = bw * s, visH = H * 0.95;", """let visW=bw*s, visH=H*.95, fullFrame=false;
      function syncFrame(){
        const full=document.documentElement.dataset.mikuFrame==="full";
        if(full===fullFrame)return;
        fullFrame=full;
        H=full?600:300;
        const w=full?maxX-minX:bw;
        const h=full?maxY-minY:bh;
        const scale=full?Math.min(W*.98/w,H*.95/h):s;
        model.scale.set(scale);
        model.x=W/2-((full?minX:ux0)+w/2)*scale;
        model.y=(full?H-h*scale:H*.05)-minY*scale;
        visW=w*scale;visH=full?h*scale:H*.95;
        app.renderer.resize(W,H);
      }""")
    change("const home = homePose();","syncFrame(); const home = homePose();")
    change("const x = (cx - r.left) / curK, y = (cy - r.top) / curK;",
           "const x=(cx-r.left)*W/r.width, y=(cy-r.top)*H/r.height;")
    regions = {p:r for r,parts in REGIONS.items() for p in parts}
    a=s.index("const PART_REGION = {")
    b=s.index("const DR =",a)
    change(s[a:b], "const PART_REGION = "+json.dumps(regions)+";\n      ")
    # The bow knot and upper loops belong to this model's outfit. Its long
    # ribbon tails extend to the waist and must not enlarge the touch target.
    a=s.index("      const chestDraw =")
    b=s.index("      const AN =",a)
    change(s[a:b],"""      const bowIds=new Set(["ArtMesh84","ArtMesh87"]);
      const upperBow=[];
      for(let i=0;i<DR.count;i++){
        if(bowIds.has(DR.ids[i]) || drawRegion[i]==="chest")upperBow.push(i);
      }
      """)
    a=s.index("      const touchRegion =")
    b=s.index("      //",a)
    change(s[a:b],"""      const touchRegion=(x,y,d)=>{
        const region=drawRegion[d];
        if(region==="arm" || region==="head")return region;
        if(fullFrame){
          const id=DR.ids[d];
          if(["ArtMesh82","ArtMesh83","ArtMesh107","ArtMesh108","ArtMesh610","ArtMesh611","ArtMesh106"].includes(id))return "leg";
          if(["ArtMesh91","ArtMesh92","ArtMesh93","ArtMesh94","ArtMesh95","ArtMesh96","ArtMesh97"].includes(id) ||
             ["ArtMesh119_Skinning","ArtMesh118_Skinning","ArtMesh120_Skinning","ArtMesh117_Skinning"].includes(PT.ids[DR.parentPartIndices[d]]))return "lower";
        }
        if(region==="chest" || bowIds.has(DR.ids[d]))return "chest";
        // Accept the garment between the loops only inside the moving bow.
        const px=(x-model.x)/model.scale.x, py=(y-model.y)/model.scale.y;
        let left=Infinity,right=-Infinity,top=Infinity,bottom=-Infinity;
        for(const i of upperBow){
          if(DR.opacities[i]<.05 || !(DR.dynamicFlags[i]&1))continue;
          const v=im.getDrawableVertices(i);
          for(let j=0;j<v.length;j+=2){
            left=Math.min(left,v[j]);right=Math.max(right,v[j]);
            top=Math.min(top,v[j+1]);bottom=Math.max(bottom,v[j+1]);
          }
        }
        if(right>left && bottom>top){
          const dx=(2*px-left-right)/(right-left),dy=(2*py-top-bottom)/(bottom-top);
          if(dx*dx+dy*dy<=1)return "chest";
        }
        return (py-minY)/(maxY-minY)<.17 ? "head" : "body";
      };
""")
    for axis in "XYZ":
        change('["Position'+axis+'", clamp(body', '["ParamBodyAngle'+axis+'", clamp(body')
    change('["LeanInput", clamp(lean','["ParamBodyAngleY", clamp(lean')
    # Resolve each written vowel, including standalone and decomposed Hangul.
    change('String(text).split', 'String(text).normalize("NFC").split')
    a=s.index("            if (c >= 0xac00")
    b=s.index("            } else if (/[.,!?",a)
    change(s[a:b],"""            const medial=c>=0xac00 && c<=0xd7a3 ? Math.floor((c-0xac00)%588/28)
              : c>=0x314f && c<=0x3163 ? c-0x314f : c>=0x1161 && c<=0x1175 ? c-0x1161 : -1;
            const shape=medial>=0 ? JUNG[medial] : /^[aeiouy]$/i.test(ch) ? (ch.toUpperCase()==="Y"?"I":ch.toUpperCase()) : null;
            if(shape){
              syl.push({v:shape,d:.14,amp:.9,stress:first});
              first=false;
""")
    change("let first = true, prevVowel = false;", "let first = true;")
    change("            prevVowel = false;", "")
    a=s.index('            core.setParameterValueById("ParamMouthOpenY", openNow')
    b=s.index("          }",a)
    change(s[a:b],"""            const {A,E,I,O,U}=vowel;
            core.setParameterValueById("ParamMouthOpenY",clamp(.64*A+.58*E+.28*I+.68*O+.32*U+mouthAdd,0,1));
            core.addParameterValueById("JawOpen",.40*A+.25*E+.36*O);
            core.addParameterValueById("WideMouth",.85*I+.48*E);
            core.addParameterValueById("ParamMouthForm",.53*I+.25*E-.65*O-.42*U);
            core.addParameterValueById("Funnel",.85*O+.38*U);
            core.addParameterValueById("mouthpucker",.28*O+.88*U);
""")
    change("const startTalk = (text, ms, quiet) => {","const syllables = text => {")
    change("        let total = syl.reduce", """        return syl;
      };
      let audioMouth=null;
      document.addEventListener("miku-audio-mouth", event=>{
        const state=JSON.parse(event.detail);
        if(state===null){audioMouth=null;return;}
        if(typeof state.text==="string"){
          audioMouth={text:state.text,shapes:syllables(state.text).filter(x=>x.v),level:0,progress:0};
          talk=null;
        } else if(audioMouth){
          audioMouth.level=state.level;
          audioMouth.progress=state.progress;
        }
      });
      const startTalk = (text, ms, quiet) => {
        if(audioMouth?.text===text)return;
        const syl=syllables(text);
        let total = syl.reduce""")
    change("          if (talk) {", """          if(audioMouth){
            const {level,progress,shapes}=audioMouth;
            const shape=shapes[Math.min(shapes.length-1,Math.floor(progress*shapes.length))]?.v || "A";
            for(const k of VOW)vowel[k]=k===shape ? level : 0;
            open=level;
          } else if (talk) {""")
    # The creator's Watermark expression moves the two credit meshes above the bust.
    # Apply after measuring the original framing so the moved label cannot shift the camera.
    change("const talking = bubble.classList.contains", 'core.setParameterValueById("Watermark", 1);\n          const talking = bubble.classList.contains')
    change("#eef0ffcc", "#a7f1dfcc")
    css=dest/"dsc-theme.css"
    theme=css.read_text()
    theme=re.sub(r"html body::after \{.*?\n\}", "", theme, flags=re.S)
    palette={"5f7cf5":"128478","8fa6ff":"59d7c5","ff8fbd":"fa90b8","f3f6ff":"fff4f8",
             "eef2ff":"e8faf6","6f8cff":"168578","e7edff":"dcf7ef","dfe7ff":"d6f6ed",
             "26305c":"233d3b","f6f8ff":"e2fcf5","eaf0ff":"f6fffa","fbefff":"ffdeed",
             "e3eaff":"d3f8ed","b58cff":"af4877","26315e":"253d39","f7f8ff":"fff3f8",
             "5a6390":"67455a","b9c6ff":"db91ac"}
    for old,new in palette.items():
        theme=theme.replace("#"+old, "#"+new)
    css.write_text(theme+"\n"+(kit/"theme.css").read_text())
    main=overlay/"lib/main.js"
    marker="installMicrophonePermissions(session.defaultSession, () => mainWindow?.webContents);"
    main_src=main.read_text()
    if main_src.count(marker)!=1:
        raise ValueError("Unsupported microphone handler")
    main_src=adapt_desktop(main_src,kit)
    main.write_text(main_src.replace(marker,marker+"\n"+(kit/"speech-main.js").read_text().replace("MIKU_FIXED_VOICE",(kit/"fixed-voice.json").read_text()).replace("MIKU_TONE_NAMES",json.dumps(list(json.loads((kit/"recap-tones.json").read_text()))))+"\n"+(kit/"voice-main.js").read_text().replace("MIKU_FACTORY_PERSONA",json.dumps((kit/"retry-persona.txt").read_text().strip(),ensure_ascii=False))))
    preload=overlay/"lib/preload-app.cjs"
    with preload.open("a") as out:
        out.write("\n;"+(kit/"voice-preload.cjs").read_text().replace("/* MIKU_SPEECH_UI */",(kit/"speech-ui.js").read_text()+"\n"+(kit/"desktop-ui.js").read_text())+"\n")
    adapt_ui(overlay,dest)
    change("const say = (text, ms = 3500, mutter = false)", "const say = (text, ms = 3500, mutter = false, speak = true)")
    change("say(TEXT.start, 2500)", "say(TEXT.start, 2500, false, false)")
    change("const listeners = { tool: null };", "const listeners = { tool: null };\n    const shownToolLines = new Set();")
    change("running = true; lastError = -1e9;", "running = true; lastError = -1e9; shownToolLines.clear(); lastToolSay = -Infinity;")
    change("if (waitingKind || now - lastToolSay < 1500) return;", "if (!running || waitingKind || shownToolLines.has(text) || now - lastToolSay < 1500) return;")
    change("lastToolSay = now; say(text, 0);", "shownToolLines.add(text); lastToolSay = now; say(text, 2400, false, false);")
    change("bubble.textContent = text; bubble.classList.add", 'if (speak) document.dispatchEvent(new CustomEvent("miku-spoken-line",{detail:text})); bubble.textContent = text; bubble.classList.add')
    js.write_text(adapt_bubble(s))


def entry(header, name, create=False):
    parent = header
    parts = name.split("/")
    for segment in parts[:-1]:
        files=parent["files"]
        parent=files.setdefault(segment,{"files":{}}) if create else files[segment]
    return parent["files"], parts[-1]


def adapt_mac_bash(script):
    marker = "if (result.sandbox?.denied) {"
    if script.count(marker) != 1:
        raise ValueError("지원되지 않는 bash 도구 출력 형식")
    # A macOS denial can come from either Seatbelt or TCC. Never retry implicitly.
    return script.replace(marker, r'''if (process.platform === "darwin" && result.exitCode !== 0 &&
        result.sandbox && result.sandbox.mode !== "danger-full-access" &&
        escalationModes.includes("danger-full-access") &&
        /execution error:[^\n]*\(-10004\)|could not create image from display/i.test(err)) {
        markers.push("[macOS: retry the affected Apple Events or screen capture command through the per-call approval flow with sandbox_permissions=danger-full-access and a justification. If it still fails there, check the corresponding macOS privacy setting.]");
    } else '''+marker)


def patch_asar(path, overlay):
    out = path.with_suffix(".miku-temp")
    with path.open("rb") as src:
        prefix = src.read(16)
        marker, size, payload, length = struct.unpack("<4I",prefix)
        if marker!=4 or size!=payload+4 or length>size-8:
            raise ValueError("Invalid ASAR header")
        header=json.loads(src.read(length))
        start=8+size
        files, name=entry(header,"package.json")
        pkg=files[name]
        src.seek(start+int(pkg["offset"]))
        version=json.loads(src.read(pkg["size"]))["version"]
        if version!="0.2.1-rc.5":
            raise ValueError("필요한 Harness 버전: 0.2.1-rc.5. 선택한 버전: "+version)
        files, name=entry(header,(FRONT.parent.parent/"index.html").as_posix())
        if name not in files:
            raise ValueError("지원되지 않는 macOS 패키지 구조")
        # These backend modules can come from the overlay or from the Mac base.
        def patch_module(module, transform):
            original = overlay / module
            if original.exists():
                script = original.read_text()
            else:
                entries, key = entry(header, module.as_posix())
                record = entries[key]
                if record.get("unpacked"):
                    script = (Path(str(path)+".unpacked") / module).read_text()
                else:
                    src.seek(start+int(record["offset"]))
                    script = src.read(record["size"]).decode()
                original.parent.mkdir(parents=True, exist_ok=True)
            original.write_text(transform(script))

        patch_module(PROMPT, adapt_prompt)
        patch_module(PROMPT.parents[2] / "dsh-tool-bash/lib/index.js", adapt_mac_bash)
        tail=path.stat().st_size-start
        additions=sorted(p for p in overlay.rglob("*") if p.is_file())
        for p in additions:
            b=p.read_bytes()
            files, name=entry(header,p.relative_to(overlay).as_posix(),True)
            block=4*1024**2
            files[name]={"size":len(b),"offset":str(tail),"integrity":{"algorithm":"SHA256",
                         "hash":hashlib.sha256(b).hexdigest(),"blockSize":block,
                         "blocks":[hashlib.sha256(b[i:i+block]).hexdigest() for i in range(0,len(b),block)]}}
            tail+=len(b)
        raw=json.dumps(header,separators=(",",":"),ensure_ascii=False).encode()
        padded=raw+bytes((-len(raw))%4)
        with out.open("xb") as dst:
            dst.write(struct.pack("<4I",4,len(padded)+8,len(padded)+4,len(raw))+padded)
            src.seek(start)
            shutil.copyfileobj(src,dst)
            for p in additions:
                with p.open("rb") as f:
                    shutil.copyfileobj(f,dst)
    os.replace(out,path)
    return hashlib.sha256(raw).hexdigest()


def build(app,overlay,archive):
    if sys.platform=="win32":
        prepare(overlay,archive)
        patch_asar(app/"resources/app.asar",overlay)
        return
    plist=app/"Contents/Info.plist"
    info=plistlib.loads(plist.read_bytes())
    prepare(overlay,archive)
    digest=patch_asar(app/"Contents/Resources/app.asar",overlay)
    for key, val in info.get("ElectronAsarIntegrity",{}).items():
        if key.endswith("Resources/app.asar"):
            if val.get("algorithm")!="SHA256":
                raise ValueError("Unsupported Electron integrity algorithm")
            val["hash"]=digest
    info["NSMicrophoneUsageDescription"]="말한 내용을 채팅 입력란에 받아쓰기 위해 마이크를 사용합니다."
    info["CFBundleDisplayName"]="Harness Miku"
    plist.write_bytes(plistlib.dumps(info))


if __name__=="__main__":
    build(*map(Path,sys.argv[1:]))
