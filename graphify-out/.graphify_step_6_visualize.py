import sys, json
from graphify.build import build_from_json
from graphify.visualize import visualize
from pathlib import Path

# Load everything from earlier steps
extraction = json.loads(Path('graphify-out/.graphify_extract.json').read_text(encoding="utf-8"))
labels     = json.loads(Path('graphify-out/.graphify_labels.json').read_text(encoding="utf-8"))
analysis   = json.loads(Path('graphify-out/.graphify_analysis.json').read_text(encoding="utf-8"))

G = build_from_json(extraction)
communities = {int(k): v for k, v in analysis['communities'].items()}
labels = {int(k): v for k, v in labels.items()}

html = visualize(G, communities, labels)

Path('graphify-out/wiki').mkdir(exist_ok=True, parents=True)
Path('graphify-out/wiki/index.html').write_text(html, encoding="utf-8")
print("Step 6 Visualizer Generation Complete!")
