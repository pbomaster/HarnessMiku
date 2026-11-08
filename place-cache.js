// Recalculate for content/font changes even when the character is stationary.
let bubbleRevision = 0;
const invalidateBubbles = () => { bubbleRevision++; };
const bubbleResize = new ResizeObserver(invalidateBubbles);
bubbleResize.observe(bubble);
bubbleResize.observe(pinnedRecap);
document.fonts?.addEventListener("loadingdone", invalidateBubbles);
let lastPlacement = "";
let lastCard = null;
