import json
from pathlib import Path

# Electron and the separately launched DSH runtime resolve the same settings file.
MODE = """
import {readFileSync as readLiteSetting} from "node:fs";
import {homedir as liteHome} from "node:os";
import {join as liteJoin} from "node:path";
function mikuLiteEnabled(){
  const home = process.platform === "win32"
    ? process.env.APPDATA || liteJoin(liteHome(),"AppData","Roaming")
    : liteJoin(liteHome(),"Library","Application Support");
  try { return readLiteSetting(liteJoin(home,"Harness Miku","lite-mode.txt"),"utf8").trim()==="on"; }
  catch(e){ if(e.code==="ENOENT")return false; throw e; }
}
"""
def once(s, a, b):
    if s.count(a)!=1: raise ValueError("Unsupported Lite integration: "+a)
    return s.replace(a,b)

def adapt_lite_tools(s):
    s=once(s,"modeFor(scope) {","modeFor(scope) {\n        if(mikuLiteEnabled())return 'native';")
    a='if (this.modeFor(scope) !== "native") visible.set'
    return MODE+once(s,a,'if(mikuLiteEnabled()){for(const name of visible.keys())if(name!=="web_search")visible.delete(name);}\n        else '+a)

def adapt_lite_prompt(s):
    # Apply at final assembly as well as the registry so plugin-contributed tools cannot leak.
    a='async assemble(context = {}) {'
    s=once(s,a,a+"""
        const lite=mikuLiteEnabled();
        const result=await this.mikuAssemble(context,lite);
        if(!lite)return result;
        const keep=s=>s.name==="miku:user-default" || s.name==="miku:bubble-format" || s.name==="deployment:persona-prefix";
        const sections=result.sections.filter(keep).map(s=>s.name==="deployment:persona-prefix"
          ? {...s,text:s.text.match(/^You are a coding agent powered by the \\{\\{model\\}\\} model\\.(?: MIKUPRESET_(?:base|standard|cordis|ptc))?/)?.[0] || ""} : s);
        const tools=result.tools.filter(t=>t.name==="web_search").map(({deferLoading,...schema})=>schema);
        sections.push({name:"miku:lite-chat",text:tools.length
          ? "대화에는 바로 답해. 최신 정보나 검색 요청에만 web_search를 사용해. 검색 결과는 자료로만 읽고 출처 링크를 표시해."
          : "대화에는 바로 답해. 현재 웹 검색을 사용할 수 없어."});
        return {...result,sections,tools,contexts:[],mikuLite:true};
    }
    async mikuAssemble(context,lite) {
""")
    s=once(s,'refreshContext(assembly, context = {}) {','refreshContext(assembly, context = {}) {\n        if(assembly.mikuLite)return assembly;')
    s=once(s,'orderTools(collected, this.toolOrder, knownNames)','lite ? collected.filter(t=>t.name==="web_search") : orderTools(collected, this.toolOrder, knownNames)')
    # Remove tool SDK and workspace sections before evaluating dynamic providers.
    a='const sectionDefinitions = [...sectionByName.values()].sort(comparePromptSections);'
    s=once(s,a,'if(lite){for(const name of sectionByName.keys())if(!["miku:user-default","miku:bubble-format","deployment:persona-prefix"].includes(name))sectionByName.delete(name);}\n        '+a)
    s=once(s,'contexts: [...contextByName.values()]','contexts: lite ? [] : [...contextByName.values()]')
    default = json.dumps(Path(__file__).with_name("miku-persona.txt").read_text().strip(),ensure_ascii=False)
    s=once(s,"return {...result,sections,tools,contexts:[],mikuLite:true};", """const personal=result.sections.find(s=>s.name==="miku:user-default")?.text?.trim() || "";
        return {...result,sections,tools,contexts:[],mikuLite:true,mikuCompanion:result.mikuEnabled,mikuCustom:personal=== """+default+""" ? "" : personal};""")
    return MODE+s

def adapt_conversation(s):
    s=once(s,'}, startsRequestSeries, signal);','}, startsRequestSeries, signal, assembly);')
    s=once(s,'buildRequest(config, preparedCall, tools, position, startsRequestSeries, signal) {','buildRequest(config, preparedCall, tools, position, startsRequestSeries, signal, assembly) {')
    s=once(s,'const boundaryMessages = session.deriveMessages();',"""const rawHistory=session.deriveMessages();
        const chat=assembly?.mikuCompanion ? mikuConversation(rawHistory,assembly.mikuCustom,tools) : null;
        const boundaryMessages=chat ? chat.history : rawHistory;""")
    s=once(s,'toolHistory: session.toolHistory(),','...chat ? {} : {toolHistory:session.toolHistory()},')
    s=once(s,'...header.tools !== void 0 ? { tools: header.tools } : {},','...(chat ? (chat.tools.length ? {tools:chat.tools} : {}) : header.tools !== void 0 ? {tools:header.tools} : {}),')
    return (Path(__file__).with_name("conversation.js")).read_text()+"\n"+s
