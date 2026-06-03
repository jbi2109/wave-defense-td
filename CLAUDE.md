# Wave Defense TD - Godot 4.x Project

## Commands
- Run project: Use `project_run` tool via `godot-ai` MCP server.
- Stop project: Use `project_manage(op="stop")` tool via `godot-ai` MCP server.
- Get editor state: Use `editor_state` tool via `godot-ai` MCP server.

## Project Rules & Memories
- Always use `caveman` skill with `full` intensity for all responses to maximize token efficiency and save quota.
- Must use appropriate agents and skills when required.
- Always follow global rules for this project.

## Code Conventions
- Target Godot 4.x using Forward+ Renderer.
- Optimize systems for high performance (MultiMeshInstance2D, compute shaders).
- Maintain correct 2D depth sorting (Y-sorting) in MultiMesh buffers by sorting index arrays by `positions[i].y`.
- Avoid dynamic wiggling/swaying on enemies; keep visual variety static using `visual_offsets` array.
