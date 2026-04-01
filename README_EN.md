# AICube Agent Office

A 2D pixel-art office simulation with interactive Agent characters, built in Godot 4.x. Agents appear as pixel characters in a real-time office environment, with their states synchronized via the OpenClaw Agent API.

[中文](README.md)

## Features

- 🏢 **Manager Room**: Boss desk, computer, bookshelf, painting, large window, checkered carpet
- 👥 **Employee Office**: 5 workstations (desks, chairs, computers), windows, plants
- ☕ **Rest Area**: Sofa lounge, tea station (coffee machine, teapot), chat corner
- 🤖 **Agent System**:
  - 5 pixel-style agents with names, job titles, and status indicators
  - 🟢Working 🟠Resting 🔵Walking ⚪Idle states
  - Walking animation with bob effect
  - Click to open detail panel

## Project Structure

```
godot-office/
├── project.godot          # Godot project configuration
├── export_presets.cfg     # HTML5 export settings
├── icon.svg              # Project icon
├── scenes/
│   ├── office.tscn       # Main office scene
│   └── agent.tscn         # Agent character scene
├── scripts/
│   ├── office.gd         # Office logic, agent management
│   └── agent.gd           # Agent behavior, movement, state transitions
└── export/
    └── index.html         # (Generated after export)
```

## How to Run

### Option 1: Godot Editor
1. Download Godot 4.x from https://godotengine.org
2. Open this project folder in Godot
3. Press F5 to run

### Option 2: Export to HTML5
1. Open project in Godot Editor
2. Go to **Project > Export**
3. Select **Web** preset
4. Click **Export Project**
5. Files will be generated in the `export/` folder

### HTML5 Local Testing
The exported web build requires an HTTP server (due to SharedArrayBuffer CORS restrictions):
```bash
cd export
python3 -m http.server 8080
# or
npx serve .
```
Then open http://localhost:8080

## Controls

- **Click Agent**: Open detail panel
- **Toggle Status**: Switch between Working/Resting
- **Click Outside**: Close panel

## Agent Characters

| Name     | Job Title      | Color   |
|----------|----------------|---------|
| Alice    | Frontend Dev   | 🔵 Blue  |
| Bob      | Backend Dev    | 🩷 Pink  |
| Charlie  | Designer       | 🟢 Green |
| Diana    | QA Engineer    | 🟠 Orange|
| Eve      | DevOps         | 🟣 Purple|

## States

- 🟢 **Working** (Green): Agent at workstation
- 🟠 **Resting** (Orange): Agent in rest area
- 🔵 **Walking** (Blue): Agent moving between locations
- ⚪ **Idle** (Gray): Agent standing by

## API

The project fetches Agent states from the OpenClaw Agent API. Configure the API URL in `scripts/office.gd`:

```gdscript
@export var api_base_url: String = "/api"
@export var api_fallback_base_urls: PackedStringArray = [
    "http://localhost:5180/api",
    "http://127.0.0.1:5180/api"
]
```

> ⚠️ Update `api_fallback_base_urls` to match your deployment environment.

## Tech Stack

- **Engine**: Godot 4.x
- **Language**: GDScript
- **Rendering**: 2D Pixel Art (Godot TileMap + Sprite2D)
- **Export**: HTML5 (Web)

---

*Built with Godot 4.x*
