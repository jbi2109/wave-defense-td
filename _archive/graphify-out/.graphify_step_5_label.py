import sys, json
from graphify.build import build_from_json
from graphify.analyze import suggest_questions
from graphify.report import generate
from graphify.export import to_json
from pathlib import Path

# Load everything from earlier steps
extraction = json.loads(Path('graphify-out/.graphify_extract.json').read_text(encoding="utf-8"))
detection  = json.loads(Path('graphify-out/.graphify_detect.json').read_text(encoding="utf-8-sig"))
analysis   = json.loads(Path('graphify-out/.graphify_analysis.json').read_text(encoding="utf-8"))

G = build_from_json(extraction)
communities = {int(k): v for k, v in analysis['communities'].items()}
cohesion = {int(k): v for k, v in analysis['cohesion'].items()}

# We can manually define labels or simple heuristic
labels = {
    0: "Gemini Settings IDE",
    1: "Design Patterns",
    2: "Python Tooling",
    3: "Gemini Experimental Settings",
    4: "GitHub Settings",
    5: "SmartShape2D",
    6: "GameDev Documentation",
    7: "Inventory System",
    8: "AI Plugin Modifiers",
    9: "Input Management",
    10: "Performance & Object Pooling",
    11: "Quest System",
    12: "Environment Post Processing",
    13: "AI Action Resetter",
    14: "Data Management",
    15: "Godot AI MCP",
    16: "Level Generation",
    17: "Project Structure",
    18: "Resolution Scaling",
    19: "Graphify Tooling",
    20: "AI Tool Append",
    21: "AI Patch Handlers",
    22: "AI Refactor Tools",
    23: "Claude Guidelines",
    24: "Grid Architecture",
    25: "Settings File",
    26: "Contributing Guides",
    27: "Debugging Output",
    28: "Image Processing",
    29: "Agent Code Mod",
    30: "Health Component",
    31: "Modern GDScript",
    32: "Signals & Tweens",
    33: "Networking & Multiplayer",
    34: "Dialogue Manager",
    35: "Save Manager",
    36: "Shaders",
    37: "Responsive UI",
    38: "UI Styles",
    39: "KayKit Assets",
    40: "Shape Anchors"
}
Path('graphify-out/.graphify_labels.json').write_text(json.dumps(labels, indent=2), encoding="utf-8")

# Add labels to the graph nodes
for node, data in G.nodes(data=True):
    # This might not be needed for graph.json but is good practice
    pass

tokens = {'input': extraction.get('input_tokens', 0), 'output': extraction.get('output_tokens', 0)}
questions = suggest_questions(G, communities, labels)

report = generate(G, communities, cohesion, labels, analysis['gods'], analysis['surprises'], detection, tokens, '.', suggested_questions=questions)

Path('graphify-out/GRAPH_REPORT.md').write_text(report, encoding="utf-8")
to_json(G, communities, 'graphify-out/graph.json')

# We can rewrite graph.json manually to inject community labels if we want
data = json.loads(Path('graphify-out/graph.json').read_text(encoding="utf-8"))
for node in data.get('nodes', []):
    if 'community' in node and node['community'] in labels:
        node['communityLabel'] = labels[node['community']]
Path('graphify-out/graph.json').write_text(json.dumps(data, indent=2), encoding="utf-8")

print("Step 5 Labeling and Report Generation Complete!")
