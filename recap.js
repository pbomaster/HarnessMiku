// Only output expressly formatted for the companion in a finished assistant reply is eligible.
function mikuSpokenRecap(blocks) {
  let text = blocks.filter(b => b.kind === "text" && typeof b.text === "string")
    .map(b => b.text).join("").trim();
  const begin = "<!--miku-recap-->", end = "<!--/miku-recap-->";
  const suffix=text.match(/<!--miku-tone:([a-z]+)-->$/);
  if (!suffix || !MIKU_TONE_NAMES.includes(suffix[1])) return "";
  text=text.slice(0,suffix.index).trimEnd();
  if (!text.endsWith(end)) return "";
  const pos = text.lastIndexOf(begin);
  if (pos < 0) return "";
  const before = text.slice(0,pos);
  if (before && !before.endsWith("\n")) return "";
  let fence="";
  for(const line of before.split("\n")){
    const token=line.match(/^ {0,3}(`{3,}|~{3,})/)?.[1];
    if(!token)continue;
    if(!fence)fence=token;
    else if(token[0]===fence[0] && token.length>=fence.length && line.trim()===token)fence="";
  }
  if(fence)return "";
  // Reject markers within unclosed provider thinking tags, including malformed streamed responses.
  const tags=/<(\/?)(think|thinking|reasoning|analysis|reflection)\b[^>]*>/gi;
  let depth=0;
  for (const match of before.matchAll(tags)) depth=match[1]?Math.max(0,depth-1):depth+1;
  const recap=text.slice(pos+begin.length,-end.length).trim();
  if (depth || !recap || recap.length>400 || /<!--|[<>]|\u0060\u0060\u0060/.test(recap)) return "";
  // A recap is plain spoken dialogue. Fail closed on stage notes or markup.
  if (/&(?:#|[a-z]+;)/i.test(recap) || /[\[\](){}［］（）【】\x60\r\n]/u.test(recap) ||
      /(?:연기\s*지시|지문|톤|말투|대사|direction|tone|dialogue)\s*[:：]/iu.test(recap)) return "";
  return JSON.stringify({text:recap,tone:suffix[1]});
}

// Project text blocks for display only; completed-turn speech still reads the original blocks.
function mikuDisplayBlocks(blocks, streaming=false) {
  const start="<!--miku-recap-->", end="<!--/miku-recap-->";
  const raw=blocks.filter(b=>b.kind==="text").map(b=>b.text).join("");
  let from=0, to=raw.length, fence="";
  for(const line of raw.split("\n")){
    const token=line.match(/^ {0,3}(`{3,}|~{3,})/)?.[1];
    if(token){
      if(!fence)fence=token;
      else if(token[0]===fence[0] && token.length>=fence.length)fence="";
    }else if(!fence && line.startsWith(start)){
      if(raw.slice(0,from).trim()){to=from;from=0;}
      else{
        from+=start.length;
        const closing=raw.indexOf(end,from);
        if(closing>=0)to=closing;
        else for(let n=end.length-1;n>0;n--)if(raw.endsWith(end.slice(0,n))){to-=n;break;}
      }
      break;
    }else if(!fence && streaming && line && from+line.length===raw.length && start.startsWith(line)){
      to=from;from=0;break;
    }
    from+=line.length+1;
  }
  if(from>raw.length)from=0;
  if(from===0 && to===raw.length)return blocks;
  let pos=0;
  return blocks.map(block=>{
    if(block.kind!=="text")return block;
    const offset=pos;pos+=block.text.length;
    return {...block,text:block.text.slice(Math.max(0,from-offset),Math.max(0,to-offset))};
  });
}
