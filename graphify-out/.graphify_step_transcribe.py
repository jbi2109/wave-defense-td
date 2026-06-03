import json, os
from pathlib import Path
from graphify.transcribe import transcribe_all

detect_text = Path('graphify-out/.graphify_detect.json').read_text(encoding="utf-8-sig")
detect = json.loads(detect_text)
video_files = detect.get('files', {}).get('video', [])
prompt = os.environ.get('GRAPHIFY_WHISPER_PROMPT', 'Godot game development tutorials and demonstrations about terrain, tilesets, shading, and sprites. Use proper punctuation and paragraph breaks.')

transcript_paths = transcribe_all(video_files, initial_prompt=prompt)
print(json.dumps(transcript_paths, ensure_ascii=False))
