(async () => {
  let calm = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const target = {open: 0, form: 0, pucker: 0}, mouth = {...target};
  const bounded = (value, min, max) => Number.isFinite(value) ? Math.max(min, Math.min(max, value)) : 0;
  window.mikuPose = (open, form, pucker, reduced) => {
    target.open = bounded(open, 0, 1);
    target.form = bounded(form, -1, 1);
    target.pucker = bounded(pucker, -1, 1);
    calm = !!reduced;
  };
  let mouthTime = performance.now();
  function updateMouth(core) {
    const now = performance.now(), dt = Math.max(0, Math.min(100, now - mouthTime));
    mouthTime = now;
    // Smooth phoneme boundaries without delaying a closed mouth after speech.
    const blend = 1 - Math.exp(-dt / (target.open === 0 ? 28 : 45));
    for (const key of ["open", "form", "pucker"]) {
      mouth[key] += (target[key] - mouth[key]) * blend;
      if (Math.abs(target[key] - mouth[key]) < 0.001) mouth[key] = target[key];
    }
    core.setParameterValueById("ParamMouthOpenY", mouth.open);
    core.setParameterValueById("ParamMouthForm", mouth.form);
    core.setParameterValueById("mouthpucker", mouth.pucker);
  }
  const thighs = new URLSearchParams(location.search).get("framing") === "thighs";
  const still = document.getElementById("still");
  try {
    const view = document.getElementById("stage");
    const app = new PIXI.Application({view,backgroundAlpha:0,antialias:true,resolution:Math.min(devicePixelRatio,2),autoDensity:true});
    app.ticker.maxFPS = 30;
    const model = await PIXI.live2d.Live2DModel.from(new URL("Private/miku/RetrynowMiku.model3.json",location.href).href,{autoInteract:false});
    app.stage.addChild(model);
    const im = model.internalModel, core = im.coreModel, draws = core.getModel().drawables;
    core.update();
    let x0=Infinity,x1=-Infinity,y0=Infinity,y1=-Infinity;
    function vertices(fn) {
      for(let i=0;i<draws.count;i++) {
        if(draws.opacities[i]<0.01)continue;
        const v=im.getDrawableVertices(i);
        for(let j=0;j<v.length;j+=2)fn(v[j],v[j+1]);
      }
    }
    vertices((x,y)=>{y0=Math.min(y,y0);y1=Math.max(y,y1);});
    const bodyHeight = y1 - y0;
    // Anchor the enlarged portrait on the head. Hands and twin-tails may extend offscreen.
    const bust = bodyHeight * (thighs ? 0.2 : 0.48);
    vertices((x,y)=>{if(y<y0+bust){x0=Math.min(x0,x);x1=Math.max(x1,x);}});
    const centerX = (x0+x1)/2;
    const touch = installTouch(view, model, app.renderer.screen, centerX, y0, y1, () => calm);
    function fit(){
      touch.reset();
      const viewport = document.documentElement.getBoundingClientRect();
      const w = viewport.width, h = viewport.height;
      if(!w||!h)return;
      app.renderer.resize(w,h);
      const local = im.localTransform;
      const top = local.apply(new PIXI.Point(centerX, y0));
      const end = local.apply(new PIXI.Point(centerX, y0 + bodyHeight * (thighs ? 0.60 : 0.48)));
      const topGap = h * (thighs ? 0.085 : 0.02);
      const heightScale = (h - topGap) / (end.y - top.y);
      const scale = thighs ? heightScale : Math.min(w * 0.9 / ((x1-x0)*local.a), heightScale);
      model.scale.set(scale);
      model.position.set(w/2 - top.x*scale, topGap - top.y*scale);
    }
    new ResizeObserver(fit).observe(document.documentElement);fit();
    im.on("beforeModelUpdate",()=>{
      touch.frame();
      core.setParameterValueById("Watermark",1);
      updateMouth(core);
      if(!calm)core.addParameterValueById("ParamAngleZ",Math.sin(performance.now()/2000)*1.4);
    });
    document.getElementById("still").hidden=true;
    document.getElementById("still").style.display="none";
  } catch {window.webkit?.messageHandlers?.stage?.postMessage("fallback");}
})();
