// LOCAL PATCH: DeepSeek짱 — Cubism Core 계산(정점 변형)만 맡는 Worker.
// 메인(dsc.js)이 매 프레임 파라미터·파트 opacity를 보내면, 같은 moc3로 만든 모델을 update()해서
// 그리기에 필요한 결과(정점, opacity, 순서, 색, 플래그)를 한 버퍼에 담아 돌려준다. Core 파일은 그대로 쓴다(수정 없음).
importScripts("vendor/live2dcubismcore.min.js");

let model = null, N = 0, vSpan = null, size = 0;

// 정점 배열들이 차지하는 메모리 구간과 각 drawable의 상대 위치 (메인과 같은지 비교용)
const spanOf = (arrs) => {
  let lo = Infinity, hi = 0;
  for (let i = 0; i < arrs.length; i++) { lo = Math.min(lo, arrs[i].byteOffset); hi = Math.max(hi, arrs[i].byteOffset + arrs[i].byteLength); }
  return { buf: arrs[0].buffer, lo, len: hi - lo, offs: Array.from(arrs, (a) => a.byteOffset - lo) };
};

const init = async (url) => {
  const ab = await (await fetch(url)).arrayBuffer();
  // Core 런타임 준비가 비동기일 수 있어 잠깐 재시도
  for (let t = 0; t < 100 && !model; t++) {
    try { model = Live2DCubismCore.Model.fromMoc(Live2DCubismCore.Moc.fromArrayBuffer(ab)); } catch { await new Promise((r) => setTimeout(r, 20)); }
  }
  if (!model) { postMessage({ type: "fail" }); return; }
  const d = model.drawables; N = d.count; vSpan = spanOf(d.vertexPositions);
  size = vSpan.len + N * 4 * 3 + N * 16 * 2 + N;   // 정점 + opacity·drawOrder·renderOrder + 곱·스크린 색 + 플래그
  postMessage({ type: "ready", count: N, params: model.parameters.count, parts: model.parts.count, offs: vSpan.offs });
};

const frame = (inp, out) => {
  const P = model.parameters.count, input = new Float32Array(inp);
  model.parameters.values.set(input.subarray(0, P));
  model.parts.opacities.set(input.subarray(P));
  model.update();
  const d = model.drawables, buf = out && out.byteLength === size ? out : new ArrayBuffer(size);
  const u8 = new Uint8Array(buf); let o = 0;
  u8.set(new Uint8Array(vSpan.buf, vSpan.lo, vSpan.len), o); o += vSpan.len;
  new Float32Array(buf, o, N).set(d.opacities); o += N * 4;
  new Int32Array(buf, o, N).set(d.drawOrders); o += N * 4;
  new Int32Array(buf, o, N).set(d.renderOrders); o += N * 4;
  new Float32Array(buf, o, N * 4).set(d.multiplyColors); o += N * 16;
  new Float32Array(buf, o, N * 4).set(d.screenColors); o += N * 16;
  u8.set(d.dynamicFlags, o);
  d.resetDynamicFlags();
  postMessage({ type: "frame", buf }, [buf]);
};

onmessage = (e) => {
  const m = e.data;
  try {
    if (m.type === "init") init(m.url).catch(() => postMessage({ type: "fail" }));
    else if (m.type === "frame" && model) frame(m.inp, m.out);
  } catch (err) { postMessage({ type: "fail", message: String(err) }); }
};
