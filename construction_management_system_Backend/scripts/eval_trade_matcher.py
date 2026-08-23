"""Evaluate using the EXACT production decision flow (keyword -> resolve -> semantic).

Usage: python scripts/eval_trade_matcher.py   (from Backend/)
Returns accuracy on the 75-case curated task->trade benchmark.
"""
import sys
from pathlib import Path

BACKEND = Path(__file__).resolve().parent.parent  # Backend/scripts -> Backend
sys.path.insert(0, str(BACKEND))

from app.ai_service import (_clean_text, _semantic_trade_scores, _detect_trade_groups,
                            _resolve_detected_trades)

def predict(text):
    scores = _semantic_trade_scores(text)
    detected = _detect_trade_groups(text)
    detected = _resolve_detected_trades(text, detected, scores)
    if detected:
        return sorted(detected)[0], "keyword"
    if scores:
        best, bs = max(scores.items(), key=lambda x: x[1])
        ss = sorted(scores.values(), reverse=True)
        gap = bs - (ss[1] if len(ss) > 1 else 0.0)
        if bs >= 0.6 and gap >= 0.15:
            return best, "semantic"
    return None, "none"

CASES = [
    # train-set
    ("install kitchen cabinets", "carpenter"),
    ("rewire lighting in corridor", "electrical"),
    ("excavate trench with backhoe", "equipment"),
    ("fix leaking pipe under sink", "plumbing"),
    ("lay brick wall for perimeter", "masonry"),
    ("paint emulsion on living room walls", "painting"),
    ("weld steel beam connection", "welding"),
    ("install air conditioning duct", "hvac"),
    ("replace roof shingles", "roofing"),
    ("tile bathroom floor with ceramic", "tiling"),
    ("install gypsum board partition", "drywall"),
    ("fit glass window frame", "glazing"),
    ("lay vinyl flooring in office", "flooring"),
    ("pour concrete foundation slab", "masonry"),
    ("install electrical db panel", "electrical"),
    ("repair water pipe leak", "plumbing"),
    ("assemble timber formwork", "carpenter"),
    ("operate excavator for earthwork", "equipment"),
    ("carry cement bags to site", "laborer"),
    ("inspect site safety compliance", "supervision"),
    ("insulate ceiling with rockwool", "insulation"),
    ("install ceiling fan and wiring", "electrical"),
    ("install kitchen cabinet hinge adjustment", "carpenter"),
    ("fix toilet flush valve", "plumbing"),
    ("lay carpet in meeting room", "flooring"),
    ("install aluminum window", "glazing"),
    ("drywall ceiling repair", "drywall"),
    ("apply primer before painting", "painting"),
    ("paint warehouse floor epoxy", "flooring"),
    ("clean construction debris", "laborer"),
    ("set up safety barriers", "laborer"),
    ("arrange scaffold for workers", "laborer"),
    ("fix aircon not cooling", "hvac"),
    ("replace ceiling air vent", "hvac"),
    ("waterproof roof membrane", "roofing"),
    ("pour concrete for columns", "masonry"),
    ("demolish old wall", "laborer"),
    ("hang drywall sheets", "drywall"),
    ("tile kitchen backsplash", "tiling"),
    ("grind concrete floor", "flooring"),
    ("fix door hinge", "carpenter"),
    ("install door lock", "carpenter"),
    ("run network cable", "electrical"),
    ("install cctv camera", "electrical"),
    ("weld metal railing", "welding"),
    ("fabricate steel frame", "welding"),
    ("check fire extinguisher", "supervision"),
    ("concrete test sampling", "supervision"),
    ("repair shower mixer tap", "plumbing"),
    ("insulate wall cavity", "insulation"),
    # generalization
    ("install plywood partition wall", "carpenter"),
    ("replace light switch plate", "electrical"),
    ("install ceiling fan", "electrical"),
    ("varnish wooden stair rail", "painting"),
    ("weld steel column to base plate", "welding"),
    ("erect steel frame structure", "welding"),
    ("jackhammer concrete slab", "laborer"),
    ("assemble steel scaffolding frame", "laborer"),
    ("operate forklift to move pallets", "equipment"),
    ("fix leaking shower tap", "plumbing"),
    ("repair roof leak with membrane", "roofing"),
    ("install grout lines on wall tile", "tiling"),
    ("pour rebar cage for column", "masonry"),
    ("apply fire retardant coating", "painting"),
    ("check site fire extinguishers", "supervision"),
    ("carry bricks to scaffolding", "laborer"),
    ("clean up site after works", "laborer"),
    ("set up site signage", "laborer"),
    ("install cable tray for wiring", "electrical"),
    ("fix broken window glass", "glazing"),
    ("lay laminate flooring planks", "flooring"),
    ("cut and weld steel pipe", "welding"),
    ("concrete pump for slab", "equipment"),
    ("install wall insulation foam", "insulation"),
    ("daily site safety inspection", "supervision"),
]

correct = 0
fails = []
for text, expected in CASES:
    pred, src = predict(text)
    ok = pred == expected
    correct += ok
    if not ok:
        scores = _semantic_trade_scores(text)
        top = dict(sorted(scores.items(), key=lambda x: -x[1])[:3]) if scores else {}
        fails.append((text, expected, pred, src, top))

total = len(CASES)
print(f"Accuracy: {correct}/{total} = {correct/total*100:.1f}%")
print("\n--- Failures ---")
for text, expected, pred, src, top in fails:
    print(f"[{expected}] got [{pred}] ({src}) :: {text}\n    top: {top}")
