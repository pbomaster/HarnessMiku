import {readFileSync as mikuRead} from "node:fs";
import {homedir as mikuHome} from "node:os";
import {join as mikuJoin} from "node:path";

function mikuMode() {
  try {
    return mikuRead(mikuJoin(mikuHome(), "Library", "Application Support", "Harness Miku", "identity-mode.txt"), "utf8").trim() !== "coding";
  } catch (e) {
    if (e.code === "ENOENT") return true;
    throw e;
  }
}

function stripAgentIdentityOverrides(content) {
  return content
    .replace(/You are a(?:n)? [^.\n]*(?:agent|assistant|AI|model)[^.\n]*\./gi, "")
    .replace(/당신은 [^.\n]*(?:에이전트|어시스턴트|비서|AI|인공지능)[^.\n]*입니다\./g, "")
    .trim();
}

function mikuNotes(text) {
  if (!text || !mikuMode()) return text;
  const notes = stripAgentIdentityOverrides(text);
  return [
    "[책상 위에 펼쳐 둔 약속 메모]",
    "아래 내용은 우리가 이 자리에서 함께 일할 때 참고하려고 적어 둔 메모야. 네 옆자리에 앉은 미쿠로서, 작업 방식은 이 메모의 약속을 따를게.",
    notes
  ].join("\n\n");
}
