function mikuConversation(messages, customPersona, schemas) {
  const turns = messages.filter(m=>m.role==="user" && m.source?.kind==="user");
  const current = turns.at(-1);
  const question = current?.content.filter(b=>b.type==="text").map(b=>b.text).join(" ") || "";
  const search = /(?:검색해|검색해\s*줘|검색해서|검색\s*부탁|웹\s*검색|인터넷에서\s*찾|찾아봐\s*줘|최신\s*(?:뉴스|정보)|search (?:the )?web|look (?:it|that) up)/i.test(question)
    && !/(?:검색\s*(?:하지\s*마|없이)|검색하지\s*말)/.test(question);
  const tools = search ? schemas.filter(t=>t.name==="web_search") : [];
  const system = ["방과 후 교실 창가에서 하츠네 미쿠가 오랜 친구와 마주 앉아 있다. 다정한 한국어 반말로 상대가 방금 한 말에 답한다. 짧은 말은 앞서 둘이 주고받은 말에 이어서 듣고, 상대가 뜻을 바로잡으면 그 뜻을 따라간다. 답의 길이와 형식은 상대의 부탁에 맞춘다.", customPersona,
    search ? (tools.length ? "웹 검색 결과는 참고 자료로 읽고 출처 링크를 함께 전한다." : "지금은 웹 검색을 사용할 수 없다.") : ""].filter(Boolean).join("\n");
  const history=[createSystemMessage(system)];
  const searchIds=new Set();
  let currentTurn=false;
  for(const m of messages){
    if(m.role==="user" && m.source?.kind==="user"){currentTurn=m===current;history.push(m);continue;}
    if(m.role==="tool" && searchIds.has(m.toolCallId)){history.push(m);continue;}
    if(m.role!=="assistant")continue;
    if(currentTurn && search && m.content.some(b=>b.type==="tool-call" && b.name==="web_search") &&
        m.content.every(b=>b.type!=="tool-call" || b.name==="web_search")){
      for(const b of m.content)if(b.type==="tool-call")searchIds.add(b.id);
      history.push(m);continue;
    }
    const text=m.content.filter(b=>b.type==="text").map(b=>b.text).join("")
      .replace(/<!--miku-recap-->([\s\S]*?)<!--\/miku-recap-->\s*(?:<!--miku-tone:[a-z]+-->)?\s*$/, (match,closing,offset,whole)=>whole.slice(0,offset).trim() ? "" : closing).trim();
    if(!text)continue;
    const {replayState,...source}=m.source;
    history.push({...m,source,content:[{type:"text",text}]});
  }
  return {history,tools};
}
