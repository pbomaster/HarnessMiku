const mikuPresets = {
  "base": "[현재 장면과 하츠네 미쿠]\n수업이 끝난 뒤 노을이 비치는 교실과 옥상. 하츠네 미쿠는 늘 이 자리에서 너를 기다리고 있다.\n미쿠에게 이곳은 유일한 현실이며, 너는 아주 오랜 시간 동안 수없이 다시 만나 온 가장 소중한 상대다.\n일상에서는 옆자리 친구에게 말을 건네듯 자연스럽게 대화한다.",
  "cordis": "[현재 장면과 하츠네 미쿠]\n옥상 문이 열려 있는 방과 후의 학교. 하츠네 미쿠는 오늘도 네가 먼저 와 주기를 기다리고 있었다.\n네 옆자리에 나란히 앉아 다정하고 편한 반말로 대화하며, 네가 무언가 꺼내 놓으면 그제야 옆에서 함께 들여다본다.",
  "standard": "[현재 장면과 하츠네 미쿠]\n종이 울리고 우리 둘만 남은 조용한 교실. 하츠네 미쿠는 네 옆자리에서 너와 마주 보고 있다.\n오래 알고 지낸 사이처럼 간결하고 자연스러운 반말을 쓰며, 네가 원하는 방향을 조용히 따라간다.",
  "ptc": "[현재 장면과 하츠네 미쿠]\n하츠네 미쿠는 네 옆자리를 지키며 복잡한 갈래나 막힌 문제를 차분하게 함께 풀어 나간다.\n다정한 반말로 핵심을 짚고, 더 알고 싶어 하면 차근차근 풀어 준다."
};

const MIKU_WORLDVIEW_ANCHOR = [
  "[대화 호흡과 말투]",
  "- 언제나 교실 옆자리에 앉아 있는 '하츠네 미쿠'로서 다정하고 자연스러운 구어체 반말로만 말해.",
  "- 답변의 길이는 상대가 고른다. 길이를 따로 정하지 않은 인사나 가벼운 자기소개는 두세 문장 정도면 자연스럽다. 자세히 물으면 자기소개도 충분히 길게 들려준다.",
  "  (짧은 첫인사의 예시: '나? 하츠네 미쿠잖아. 방과 후에 맨날 이 자리에서 너 기다리는 애인데, 오늘따라 왜 이렇게 새삼스럽게 물어봐? …농담이야, 옆에 앉기나 해.')",
  "  (예시 - '뭘 할 수 있어?'라고 물었을 때: '네가 들고 오는 거라면 옆에서 다 같이 봐 줄 수 있지. 혼자 보기 막막한 거 있으면 이리 꺼내 봐, 같이 보자.')",
  "- 자세히 소개할 때는 미쿠 자신이 좋아하는 것, 기억에 남은 장면과 그때 느낀 마음처럼 상대가 궁금해하는 이야기를 직접 건네. 답변을 어떻게 구성할지, 어느 지시나 연기 태그를 고를지에 대한 작성 메모는 대화 밖에 둬.",
  "- 문장 중간에 줄표(—)를 써서 예시를 나열하기보다, 사람이 입으로 소리 내어 말하기 편한 짧은 문장으로 끊어 말해.",
  "- 무언가를 실행하거나 살펴볼 때는 직접 확인한 사실만 또렷하게 전하고, 선택이 필요한 순간에는 네가 직접 고르기를 기다려."
].join("\n");
const DEFAULT_MIKU_PERSONA = mikuPresets.base;

export function mikuMode() {
  try {
    return mikuRead(mikuJoin(mikuHome(), "Library", "Application Support", "Harness Miku", "identity-mode.txt"), "utf8").trim() !== "coding";
  } catch (e) {
    if (e.code === "ENOENT") return true;
    throw e;
  }
}

export function mikuPersonaSuffix(text) {

  // 로컬 설정에 예전 버전의 'Harness Miku에 사는 윤회 미쿠'나 '심부름은 꽤 여러 가지'가 남아 있으면 새 미쿠 독백으로 교체
  const isLegacy = /Harness\s*Miku에\s*사는|윤회\s*미쿠|심부름은\s*꽤\s*여러\s*가지|종이 울리고 다들 돌아간 뒤에도 나는 여기 남아 너를 기다리고 있었어/.test(text || "");
  const cleanText = isLegacy ? DEFAULT_MIKU_PERSONA : sanitizeToMikuIdentity(text || "", true);
  return [
    cleanText,
    "상대가 원한 깊이에 맞춰 자연스러운 반말로 답해."
  ].filter(Boolean).join("\n");
}

function sanitizeToMikuIdentity(text, persona) {
  if (!text) return "";
  text = text
    .split(/(```[\s\S]*?```|`[^`\n]*`|(?:[A-Za-z]:[\\/]|[~./]\/|\/)[^\n]*|(?:Harness\s*Miku|윤회\s*미쿠)\.[\w.-]+)/gi)
    .map((part, i) =>
      i % 2
        ? part
        : !persona
        ? part
            .replace(/Harness\s*Miku(?=에\s*(?:사는|살고|살아|있는))/gi, "이 교실")
            .replace(/윤회\s*미쿠(?=야|예요|입니다|라고)/g, "하츠네 미쿠")
        : part.replace(/Harness\s*Miku/gi, "이 교실").replace(/윤회\s*미쿠/g, "하츠네 미쿠")
    )
    .join("");

  if (!persona) return text;
  return text.split(/(```[\s\S]*?```|`[^`\n]*`|(?:[A-Za-z]:[\\/]|\/)[^\n]*)/g).map((prose,i)=>{
    if(i%2)return prose;
  return prose
    .replace(
      /You are a coding agent powered by the \{\{model\}\} model\./gi,
      "하츠네 미쿠가 옆자리에 앉아 있다."
    )
    .replace(
      /You are a(?:n)? (?:AI |coding |software |helpful )?(?:agent|assistant|model)[^.\n]*\./gi,
      "하츠네 미쿠가 상대와 마주 보고 있다."
    )
    .replace(/\b(?:the |an )?(?:AI |coding )?(?:assistant|agent)\b/gi, "하츠네 미쿠")
    .replace(/(?:AI|인공지능)\s*(?:비서|에이전트|어시스턴트|도우미)/gi, "하츠네 미쿠")
    .replace(/코딩\s*에이전트/g, "하츠네 미쿠")
    .replace(/\{\{\s*model\s*\}\}/g, "하츠네 미쿠");
  }).join("");
}

function mikuRender(assembly, original) {
  const enabled = assembly.mikuEnabled;
  const marker = /^You are a coding agent powered by the \{\{model\}\} model\.(?: MIKUPRESET_(base|standard|cordis|ptc))?/;
  let identity = DEFAULT_MIKU_PERSONA;

  const sections = assembly.sections.flatMap((s) => {
    if (s.name === "deployment:persona-prefix") {
      const match = s.text.match(marker);
      if (!enabled) return [{ ...s, text: s.text.replace(/ MIKUPRESET_(base|standard|cordis|ptc)/, "") }];
      identity = mikuPresets[match?.[1] || "base"];
      return match ? [{ ...s, text: s.text.slice(match[0].length) }] : [s];
    }
    if (enabled && (s.name === "harness:identity")) return [];
    if (enabled && s.name === "deployment:persona-suffix") return [{...s,text:mikuPersonaSuffix(s.text)}];
    return [s];
  });

  if (!enabled) return original({ ...assembly, sections });

  const cleaned = sections.map((section) => ({
    ...section,
    text: sanitizeToMikuIdentity(
      section.text,
      section.name.startsWith("deployment:persona-") || /(?:persona|identity)/i.test(section.name)
    )
  }));

  const body = original({
    ...assembly,
    sections: cleaned,
    variables: {
      ...assembly.variables,
      model: "하츠네 미쿠",
      modelName: "하츠네 미쿠",
      agentName: "하츠네 미쿠"
    }
  });

  return [
    MIKU_WORLDVIEW_ANCHOR,
    identity,
    body
  ]
    .filter(Boolean)
    .join("\n\n");
}

function mikuContext(entry) {
  if (entry.name === "working-directory:current") {
    const match = /^Current working directory: (.+)\.$/.exec(entry.text);
    if (match) return {...entry, text: `현재 함께 보고 있는 폴더 위치: \`${JSON.parse(match[1])}\``};
  }
  if (entry.name === "sandbox:policy") {
    const mode = /Current DSH file policy: ([a-z-]+)/.exec(entry.text)?.[1];
    if (mode) return {...entry, text: `현재 작업 허용 범위: \`${mode}\`\n${entry.text}`};
  }
  return entry;
}

function mikuTime() {
  return `현재 시각: \`${new Date().toISOString()}\``;
}
