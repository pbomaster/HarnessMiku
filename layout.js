// All positions are CSS pixels, matching the pointer hit-test coordinates.
function mikuHome(width, height, card, W, H, visW, visH, fleeX) {
  const percent=Number(document.documentElement.dataset.mikuSize);
  const scale=[50,75,100,125,150].includes(percent)?percent/100:1;
  if(typeof document!=="undefined" && document.documentElement.classList.contains("miku-desktop")){
    const bottom=height;
    const base=Math.min(.79,Math.max(.35,(bottom-115)/H));
    const k=Math.min(base*scale,Math.max(.15,(bottom-45)/H),Math.max(1,width-16)/W);
    // Reserve half of the combined toolbar on the right even at small pet scales.
    const groupWidth=Math.min(196,width-54)+38;
    const centerFromRight=8+Math.max(visW*k,groupWidth)/2;
    const root=document.documentElement;
    const distance=centerFromRight+"px";
    if(root.style.getPropertyValue("--pet-canvas-center-right")!==distance)
      root.style.setProperty("--pet-canvas-center-right",distance);
    return {k,x:width-centerFromRight-W*k/2+fleeX,y:bottom-H*k,card};
  }
  const gap = 8;
  const limit = Math.min(1.25, height * .45 / H, (width - gap) / W);
  const compact = Math.min(.46, limit);
  const r = card?.getBoundingClientRect();
  const beside = r ? (width - r.right - gap) / visW : limit;
  const below = r ? (height - r.bottom - gap) / H : limit;
  const fit = Math.max(beside, below);
  let k = Math.min(limit, Math.max(compact, fit));
  let y = height - H * k;
  if (r && fit < compact) {
    // When the composer occupies the full width, use the space above it.
    if (r.top > 2 * gap + 40) {
      k = Math.min(compact, (r.top - 2 * gap) / H);
      y = r.top - H * k - gap;
    } else y = gap;
  }
  const bottom=y+H*k;
  k=Math.min(k*scale,(width-gap)/W,Math.max(.1,(bottom-gap)/H));
  y=bottom-H*k;
  if(r && scale>1 && y<r.bottom && width-4-visW*k<r.right && r.top>H*k+gap)
    y=Math.min(y,r.top-H*k-gap);
  return {k, x:width - 4 - (W + visW) * k / 2 + fleeX, y, card};
}

function mikuBubbleLane(card) {
  if(document.documentElement.classList.contains("miku-desktop"))return null;
  const panel=card?.closest("[data-conversation-content]") || document.querySelector("[data-conversation-content]");
  const flow=panel?.querySelector("[data-chat-flow]");
  if(!flow?.getClientRects().length)return null;
  const bounds=panel.getBoundingClientRect();
  const left=Math.ceil(flow.getBoundingClientRect().right)+8;
  const right=Math.floor(bounds.right)-8;
  return right>left ? {left,right,top:Math.ceil(bounds.top)+8} : null;
}

function mikuPlaceBubble(bubble, width, height, headTop, centerX, card, lane=null) {
  const gap = 8;
  const recap = !!bubble.querySelector(".miku-recap-text");
  bubble.style.right = "auto";
  bubble.style.width = "max-content";
  const leftEdge=lane?.left ?? gap, rightEdge=lane?.right ?? width-gap;
  const laneWidth=rightEdge-leftEdge;
  const maxWidth=lane ? Math.min(laneWidth,Math.max(140,Math.min(242,Math.round(laneWidth*.9)))) : (recap ? 430 : 250);
  bubble.style.maxWidth=Math.min(laneWidth,maxWidth)+"px";
  const ceiling=lane?.top || gap;
  // Use any remaining gutter width for taller text.
  if(lane && bubble.offsetHeight>headTop-gap-ceiling)
    bubble.style.maxWidth=laneWidth+"px";
  const w = bubble.offsetWidth, h = bubble.offsetHeight;
  const left = Math.max(leftEdge, Math.min(centerX - w / 2, rightEdge - w));
  let top = headTop - h - gap;
  const r = card?.getBoundingClientRect();
  if (r && left < r.right && left+w > r.left && top < r.bottom && top+h > r.top)
    top = r.top - h - gap;
  bubble.style.left = left + "px";
  bubble.style.top = Math.max(ceiling, Math.min(top, height - h - gap)) + "px";
}

// Only bare layout surfaces can relay a chat click to the background character.
// Match the surface itself. Descendant controls and portal contents own their input.
function mikuChatBackdrop(target) {
  return target instanceof Element && (
    target.matches("html,body,#root,[data-conversation-content],[data-conversation-scroll],[data-chat-flow],[data-composer-seat]") ||
    target.matches("#root :has([data-conversation-content]), #root :has(> .dsc-composer)")
  );
}
