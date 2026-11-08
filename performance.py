"""Backport PR #7 to the Miku stage after its custom layout is assembled."""
from pathlib import Path
from shutil import copyfile
from renderer_patch import patch_renderer

KIT = Path(__file__).parent


def replace_once(source, old, new):
    if source.count(old) != 1:
        raise ValueError("Unsupported Miku stage: " + old[:90])
    return source.replace(old, new)


def optimize_stage(source):
    model_anchor = "      const exp = {};"
    source = replace_once(source, model_anchor, (KIT / "worker-init.js").read_text() + "\n" + model_anchor)
    place_anchor = "      const place = () => {"
    source = replace_once(source, place_anchor, (KIT / "place-cache.js").read_text() + "\n" + place_anchor)
    # Read geometry before mutating any element. Keep the existing intro timing.
    source = replace_once(source, "const lane=mikuBubbleLane(home.card);", "")
    anchor = '        canvas.style.display = bubble.style.display = "block";'
    source = replace_once(source, anchor, """        const lane = introOn ? null : mikuBubbleLane(home.card);
        if (!introOn) {
          const r = home.card?.getBoundingClientRect();
          const key = JSON.stringify([
            k, x, y, W, H, fleeX, innerWidth, innerHeight, r?.left, r?.right, r?.top, r?.bottom,
            lane?.left, lane?.right, lane?.top, document.documentElement.className,
            bubble.className, bubble.textContent, pinnedRecap.hidden, pinnedRecap.textContent, bubbleRevision
          ]);
          if (key === lastPlacement && home.card === lastCard) return;
          lastPlacement = key;
          lastCard = home.card;
        } else {
          lastPlacement = "";
        }
""" + anchor)
    return source


def apply_performance(dest):
    stage = dest / "dsc.js"
    optimized = optimize_stage(stage.read_text())
    patch_renderer(dest / "vendor" / "cubism4.patched.js")
    copyfile(KIT / "dsc-core-worker.js", dest / "dsc-core-worker.js")
    stage.write_text(optimized)
