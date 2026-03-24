# AICube Agent Office - Godot 4.x Project

A 2D pixel-art office simulation with interactive Agent characters built in Godot 4.x.

## Features

- **Manager Room**: Boss desk, computer, bookshelf, painting, large window, checkered carpet
- **Employee Office**: 5 workstations with desks, chairs, computers; windows and plants
- **Rest Area**: Sofa lounge, tea station with coffee machine and teapot, chat corner
- **Agent System**: 
  - 5 pixel-style agents with names, job titles, and status indicators
  - Working/Resting/Walking states with color-coded status icons
  - Walking animation with bob effect
  - Click to select and view details

## Project Structure

```
godot-office/
├── project.godot          # Godot project configuration
├── export_presets.cfg     # HTML5 export settings
├── icon.svg               # Project icon
├── scenes/
│   ├── office.tscn        # Main office scene
│   └── agent.tscn         # Agent character scene
├── scripts/
│   ├── office.gd          # Office logic, agent management
│   └── agent.gd           # Agent behavior, movement, states
└── export/
    └── index.html         # (Generated after export)
```

## How to Run

### Option 1: Use Godot Editor
1. Download Godot 4.x from https://godotengine.org
2. Open the project folder in Godot
3. Press F5 to run

### Option 2: Export to HTML5
1. Open project in Godot Editor
2. Go to Project > Export
3. Select "Web" preset
4. Click "Export Project"
5. Files will be generated in `export/` folder

### HTML5 Requirements
The exported web build requires a web server (due to CORS restrictions on shared array buffers):
```bash
cd export
python3 -m http.server 8080
```
Then open http://localhost:8080

## Controls

- **Click Agent**: Open detail panel
- **Toggle Status**: Switch between Working/Resting
- **Click Outside**: Close panel

## Agent Details

| Name    | Job Title      | Color   |
|---------|----------------|---------|
| Alice   | Frontend Dev   | Blue    |
| Bob     | Backend Dev    | Pink    |
| Charlie | Designer       | Green   |
| Diana   | QA Engineer    | Orange  |
| Eve     | DevOps         | Purple  |

## States

- 🟢 **Working** (Green): Agent at workstation
- 🟠 **Resting** (Orange): Agent in rest area
- 🔵 **Walking** (Blue): Agent moving between locations
- ⚪ **Idle** (Gray): Agent standing by

---

*Built with Godot 4.x*
