import json
from graphify.extract import collect_files, extract
from pathlib import Path


def main():
    code_files = []
    detect_text = Path('graphify-out/.graphify_detect.json').read_text(encoding="utf-8-sig")
    detect = json.loads(detect_text)
    for f in detect.get('files', {}).get('code', []):
        code_files.extend(collect_files(Path(f)) if Path(f).is_dir() else [Path(f)])

    if code_files:
        result = extract(code_files)
        Path('graphify-out/.graphify_ast.json').write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding="utf-8")
        print(f'AST: {len(result["nodes"])} nodes, {len(result["edges"])} edges')
    else:
        Path('graphify-out/.graphify_ast.json').write_text(json.dumps({'nodes':[],'edges':[],'input_tokens':0,'output_tokens':0}, ensure_ascii=False), encoding="utf-8")
        print('No code files - skipping AST extraction')


# Windows-spawn ProcessPoolExecutor (used inside extract()) re-imports this
# script in each worker; without an `if __name__ == "__main__":` guard the
# pool would recursively spawn itself. graphify v0.7.11+ falls back to
# sequential extraction if the pool dies, but the guard keeps multi-core
# extraction working on Windows.
if __name__ == '__main__':
    main()
