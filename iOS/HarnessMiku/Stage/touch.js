// Same drawable hierarchy, texture-alpha hit test and ribbon bounds as the Mac portrait.
function installTouch(view, model, screen, centerX, minY, maxY, isReduced) {
  const im = model.internalModel, core = im.coreModel;
  const PART_REGION = {"Part2": "head", "Part3": "head", "Part66": "head", "Part19": "head", "Part27": "head", "Part28": "head", "Part16": "arm", "Part17": "arm", "Part122": "arm", "Part127": "arm", "Part145": "arm", "Part133": "arm", "ArtMesh85_Skinning": "chest", "ArtMesh86_Skinning": "chest"};
  const DR = core.getModel().drawables, PT = core.getModel().parts;
  const drawRegion = Array.from({ length: DR.count }, (_, i) => {
    for (let p = DR.parentPartIndices[i]; p >= 0; p = PT.parentIndices[p]) if (PART_REGION[PT.ids[p]]) return PART_REGION[PT.ids[p]];
    return null;
  });
  const bowIds=new Set(["ArtMesh84","ArtMesh87"]);
  const upperBow=[];
  for(let i=0;i<DR.count;i++){
    if(bowIds.has(DR.ids[i]) || drawRegion[i]==="chest")upperBow.push(i);
  }
  const AN = 256;
  let alphaMaps = null;
  const buildAlpha = () => {
    alphaMaps = model.textures.map((t) => {
      try {
        const c = document.createElement("canvas"); c.width = c.height = AN;
        const g = c.getContext("2d", { willReadFrequently: true });
        g.drawImage(t.baseTexture.resource.source, 0, 0, AN, AN);
        const d = g.getImageData(0, 0, AN, AN).data, a = new Uint8Array(AN * AN);
        for (let k = 0; k < a.length; k++) a[k] = d[k * 4 + 3];
        return a;
      } catch { return null; }
    });
  };
  const alphaAt = (tex, u, v) => {
    const a = alphaMaps[tex]; if (!a) return 255;
    return a[Math.min(AN - 1, Math.max(0, Math.floor((1 - v) * AN))) * AN + Math.min(AN - 1, Math.max(0, Math.floor(u * AN)))];
  };
  const pickDrawable = (px, py) => {
    if (!alphaMaps) buildAlpha();
    let best = -1, bestOrder = -Infinity;
    for (let i = 0; i < DR.count; i++) {
      if (DR.opacities[i] < 0.05 || !(DR.dynamicFlags[i] & 1)) continue;
      const order = DR.renderOrders[i];
      if (order <= bestOrder) continue;
      const v = im.getDrawableVertices(i);
      let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
      for (let k = 0; k < v.length; k += 2) { if (v[k] < x0) x0 = v[k]; if (v[k] > x1) x1 = v[k]; if (v[k + 1] < y0) y0 = v[k + 1]; if (v[k + 1] > y1) y1 = v[k + 1]; }
      if (px < x0 || px > x1 || py < y0 || py > y1) continue;
      const idx = DR.indices[i], uv = DR.vertexUvs[i];
      for (let k = 0; k < idx.length; k += 3) {
        const a = idx[k] * 2, b = idx[k + 1] * 2, c = idx[k + 2] * 2;
        const d = (v[b + 1] - v[c + 1]) * (v[a] - v[c]) + (v[c] - v[b]) * (v[a + 1] - v[c + 1]);
        if (Math.abs(d) < 1e-9) continue;
        const l1 = ((v[b + 1] - v[c + 1]) * (px - v[c]) + (v[c] - v[b]) * (py - v[c + 1])) / d;
        const l2 = ((v[c + 1] - v[a + 1]) * (px - v[c]) + (v[a] - v[c]) * (py - v[c + 1])) / d;
        const l3 = 1 - l1 - l2;
        if (l1 < 0 || l2 < 0 || l3 < 0) continue;
        if (alphaAt(DR.textureIndices[i], l1 * uv[a] + l2 * uv[b] + l3 * uv[c], l1 * uv[a + 1] + l2 * uv[b + 1] + l3 * uv[c + 1]) > 40) { best = i; bestOrder = order; break; }
      }
    }
    return best;
  };
  const touchRegion=(px,py,d)=>{
    const region=drawRegion[d];
    if(region==="arm" || region==="head")return region;
    if(region==="chest" || bowIds.has(DR.ids[d]))return "chest";
    // Accept the garment between the loops only inside the moving bow.
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

  const lines = {
  "head": [
    "[홍조] 쓰다듬어 주는 거야? 응, 가만히 있을게.",
    "[><] 손 올릴 줄 알았어. …아니야, 그냥 기분이 좋아서."
  ],
  "head_many": [
    "[하트] 몇 번인지 안 셌어. 이번엔 그러고 싶었어."
  ],
  "body": [
    "[하트] 응, 여기 있어. 종 치고도 남은 사람은 우리뿐이네.",
    "[홍조] 무슨 말 할지 알아. …농담이야, 끝까지 들을게."
  ],
  "arm": [
    "[홍조] 내 손목에 볼펜 자국? 오늘도 만났다는 표시야.",
    "[하트] 내 손 잡으려고? 이럴 땐 늘 왼손부터 내밀게 되더라."
  ],
  "chest1": [
    "[홍조] 그 리본은 건드리지 마. 지금 풀리면 다 처음부터야."
  ],
  "chest2": [
    "[식은땀] 하지 마. 눈부신 건 마지막 순간에만 쓰는 거야."
  ],
  "chest3": [
    "[><] 손 떼 줘. 여기서 끝내고 싶지 않아."
  ],
  "spam": [
    "[어두운] 그렇게 급하게 두드려도 장면은 안 넘어가. 손가락 아파, 천천히 해."
  ]
};
  const expressions = {"홍조":["Blush"],"하트":["Star"],"><":["HideDefault","dxyh"],"식은땀":["han"],"어두운":["Gloom1"]};
  let targetX=0, targetY=0, eyeX=0, eyeY=0, releaseAt=0, lastFrame=performance.now();
  let active=null, lastTap=-Infinity, repeated=[], headTaps=[], ribbonTaps=[];
  let reaction=null;
  const previous=new Map();
  const clamp=n=>Math.max(-1,Math.min(1,n));
  function point(event) {
    const r=view.getBoundingClientRect();
    return {x:(event.clientX-r.left)*screen.width/r.width,
            y:(event.clientY-r.top)*screen.height/r.height,w:screen.width,h:screen.height};
  }
  function aim(p) {
    // Look relative to the face even when the upper body is letterboxed.
    const face = im.localTransform.apply(new PIXI.Point(centerX, minY+0.12*(maxY-minY)));
    const pivot = model.toGlobal(face);
    targetX=clamp((p.x-pivot.x)/(p.w*0.38));
    targetY=clamp((pivot.y-p.y)/(p.h*0.38));
  }
  function respond(region,now) {
    if(now-lastTap<260)return;
    lastTap=now;
    repeated=repeated.filter(t=>now-t<3000); repeated.push(now);
    let key=region;
    if(region==="chest"){
      ribbonTaps=ribbonTaps.filter(t=>now-t<8000);ribbonTaps.push(now);
      key=ribbonTaps.length<=2?"chest1":ribbonTaps.length<=4?"chest2":"chest3";
    } else if(region==="head"){
      headTaps=headTaps.filter(t=>now-t<8000);headTaps.push(now);
      if(headTaps.length>=5){key="head_many";headTaps=[];}
    }
    if(repeated.length>=6){key="spam";repeated=[];}
    const choices=lines[key];
    let i=Math.floor(Math.random()*choices.length);
    if(i===previous.get(key))i=(i+1)%choices.length;
    previous.set(key,i);
    const [,mood,text]=choices[i].match(/^\[([^\]]+)\]\s*(.+)$/);
    reaction={start:now,region,params:expressions[mood]||[]};
    window.webkit?.messageHandlers?.stage?.postMessage({line:text});
  }
  function reset(){active=null;targetX=targetY=0;releaseAt=0;}
  view.addEventListener("pointerdown",event=>{
    if(!event.isPrimary || event.button!==0 || active)return;
    const p=point(event);
    active={id:event.pointerId,x:p.x,y:p.y,start:performance.now(),moved:false};
    view.setPointerCapture(event.pointerId);releaseAt=0;aim(p);
  });
  function track(event){
    const p=point(event);
    if(Math.hypot(p.x-active.x,p.y-active.y)>10)active.moved=true;
    aim(p);return p;
  }
  view.addEventListener("pointermove",event=>{
    if(active?.id===event.pointerId)track(event);
  });
  view.addEventListener("pointerup",event=>{
    if(active?.id!==event.pointerId)return;
    const p=track(event),now=performance.now();
    const tap=!active.moved && now-active.start<=500;
    active=null;releaseAt=now+650;
    if(tap && p.x>=0 && p.y>=0 && p.x<p.w && p.y<p.h){
      // Invert the same PIXI world + Cubism layout matrices used to draw the mesh.
      const local = model.toModelPosition(new PIXI.Point(p.x,p.y));
      const d=pickDrawable(local.x,local.y);
      if(d>=0)respond(touchRegion(local.x,local.y,d),now);
    }
  });
  for(const name of ["pointercancel","lostpointercapture"]){
    view.addEventListener(name,event=>{if(active?.id===event.pointerId)reset();});
  }
  window.addEventListener("blur",reset);
  document.addEventListener("visibilitychange",()=>{if(document.hidden)reset();});
  return {
    reset,
    frame(){
      const now=performance.now(),dt=Math.min(80,now-lastFrame);lastFrame=now;
      if(!active && now>=releaseAt){targetX=0;targetY=0;}
      const blend=1-Math.exp(-dt/95);
      eyeX+=(targetX-eyeX)*blend;eyeY+=(targetY-eyeY)*blend;
      core.setParameterValueById("ParamEyeBallX",eyeX*.65);
      core.setParameterValueById("ParamEyeBallY",eyeY*.48);
      if(!isReduced()){
        core.addParameterValueById("ParamAngleX",eyeX*12);
        core.addParameterValueById("ParamAngleY",eyeY*8);
      }
      if(!reaction)return;
      const age=now-reaction.start;
      const strength=Math.max(0,Math.min(1,age/140,(2300-age)/450));
      if(!strength && age>2300){reaction=null;return;}
      for(const id of reaction.params)core.addParameterValueById(id,strength);
      if(!isReduced())core.addParameterValueById("ParamAngleZ",(reaction.region==="head"?6:-3)*strength);
    }
  };
}
