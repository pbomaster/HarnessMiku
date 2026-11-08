      // ---------- Core 계산을 Worker로 (결과는 1프레임 늦게 반영) ----------
      // 정점 변형(Core update)은 Worker의 같은 모델이 맡고, 메인은 받은 결과를 Core 배열에 복사만 한다.
      // 렌더러·터치 판정은 그대로 Core 배열을 읽는다. Worker를 못 쓰거나 실패하면 원래대로 메인에서 계산.
      (() => {
        const d = cm.drawables, N = d.count, localUpdate = () => Object.getPrototypeOf(cm).update.call(cm);
        let w;
        if (localStorage.getItem("miku-core-worker") === "off") return;
        try { w = new Worker(BASE + "dsc-core-worker.js"); } catch { return; }
        let lo = Infinity, hi = 0;
        for (let i = 0; i < N; i++) { const a = d.vertexPositions[i]; lo = Math.min(lo, a.byteOffset); hi = Math.max(hi, a.byteOffset + a.byteLength); }
        const offs = Array.from(d.vertexPositions, (a) => a.byteOffset - lo).join();
        const vBytes = new Uint8Array(d.vertexPositions[0].buffer, lo, hi - lo);
        // Only copy vertex memory. Padding and other Core data in the heap belong to the main model.
        const ranges = Array.from(d.vertexPositions, a => [a.byteOffset-lo, a.byteOffset-lo+a.byteLength])
          .filter(([start,end]) => end > start).sort((a,b) => a[0]-b[0]);
        const runs = [];
        for (const [start,end] of ranges) {
          const prev = runs[runs.length-1];
          if (prev && start <= prev[1]) prev[1] = Math.max(prev[1],end);
          else runs.push([start,end]);
        }
        let pendingSince = performance.now();
        let ready = false, busy = false, result = null, spare = null;
        const stop = () => { ready = false; delete cm.update; try { w.terminate(); } catch {} };
        window.addEventListener("pagehide", stop, {once:true});
        w.onmessageerror = stop;
        const apply = (buf) => {
          const u8 = new Uint8Array(buf); let o = 0;
          for (const [start,end] of runs) vBytes.set(u8.subarray(start,end),start);
          o += vBytes.length;
          d.opacities.set(new Float32Array(buf, o, N)); o += N * 4;
          d.drawOrders.set(new Int32Array(buf, o, N)); o += N * 4;
          d.renderOrders.set(new Int32Array(buf, o, N)); o += N * 4;
          d.multiplyColors.set(new Float32Array(buf, o, N * 4)); o += N * 16;
          d.screenColors.set(new Float32Array(buf, o, N * 4)); o += N * 16;
          d.dynamicFlags.set(u8.subarray(o, o + N));
        };
        w.onerror = stop;
        w.onmessage = (e) => {
          const m = e.data;
          if (m.type === "ready") {   // 같은 모델인지(개수·정점 배치) 확인한 뒤에만 넘김
            if (m.count === N && m.params === cm.parameters.count && m.parts === cm.parts.count && m.offs.join() === offs) ready = true; else stop();
          } else if (m.type === "frame") { result = m.buf; busy = false; }
          else if (m.type === "fail") stop();
        };
        cm.update = () => {
          if ((!ready || busy) && performance.now()-pendingSince > 3000) {
            stop();
            return localUpdate();
          }
          if (!ready) return localUpdate();
          if (result) {
            try { apply(result); } catch { stop(); return localUpdate(); }
            spare = result; result = null;
          }
          if (!busy) {   // 이전 결과가 오기 전엔 새로 보내지 않음 (밀리지 않게)
            const P = cm.parameters.count, inp = new Float32Array(P + cm.parts.count);
            inp.set(cm.parameters.values); inp.set(cm.parts.opacities, P);
            const tr = [inp.buffer]; if (spare) tr.push(spare);
            try { w.postMessage({ type: "frame", inp: inp.buffer, out: spare }, tr); }
            catch { stop(); return localUpdate(); }
            pendingSince = performance.now();
            spare = null; busy = true;
          }
        };
        try { w.postMessage({ type: "init", url: BASE + "miku/RetrynowMiku.moc3" }); } catch { stop(); }
      })();
