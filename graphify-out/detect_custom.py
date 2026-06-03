import os
import json
from pathlib import Path

root = Path(".")
code_files = []
doc_files = []
image_files = []

# Scan scripts
scripts_dir = root / "scripts"
if scripts_dir.exists():
    for f in scripts_dir.glob("*.gd"):
        code_files.append(str(f.resolve()))

# Scan scenes
scenes_dir = root / "scenes"
if scenes_dir.exists():
    for f in scenes_dir.rglob("*.tscn"):
        doc_files.append(str(f.resolve())) # Treat tscn as document for semantic extraction

# Main docs
for doc_name in ["CLAUDE.md", "README.md", "walkthrough.md", "task.md", "implementation_plan.md"]:
    p = root / doc_name
    if p.exists():
        doc_files.append(str(p.resolve()))
        
# AppData brain docs if any (like task.md, implementation_plan.md, walkthrough.md)
brain_dir = Path("C:/Users/jbijo/.gemini/antigravity/brain/b6490d31-bb78-4086-8308-78eb2028aa47")
if brain_dir.exists():
    for f in brain_dir.glob("*.md"):
        doc_files.append(str(f.resolve()))

# Let's count words roughly to populate total_words
total_words = 0
for filepath in code_files + doc_files:
    try:
        with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
            total_words += len(f.read().split())
    except Exception:
        pass

result = {
    "files": {
        "code": code_files,
        "document": doc_files,
        "paper": [],
        "image": [],
        "video": []
    },
    "total_files": len(code_files) + len(doc_files),
    "total_words": total_words,
    "needs_graph": True,
    "skipped_sensitive": [],
    "scan_root": str(root.resolve())
}

# Write back to .graphify_detect.json
out_dir = Path("graphify-out")
out_dir.mkdir(exist_ok=True)
with open(out_dir / ".graphify_detect.json", "w", encoding="utf-8") as f:
    json.dump(result, f, ensure_ascii=False, indent=2)

print(f"Custom detect: {result['total_files']} files ({len(code_files)} code, {len(doc_files)} docs), ~{total_words} words")
