# Export Output

This folder will contain the exported HTML5 files after running the export process in Godot Editor.

## Files that will be generated:

- `index.html` - Main HTML file
- `index.js` - Godot engine and game code
- `index.pck` - Packaged game resources
- `index.png` - Favicon
- `index.worker.js` - Web worker for threading

## To Export:

1. Open Godot 4.x Editor
2. Open project at: `/home/moston/.openclaw/workspace/godot-office/`
3. Go to **Project > Export**
4. Select **Web** preset
5. Click **Export Project**
6. Save to: `export/index.html`

## Manual Testing

After export, serve with any HTTP server:

```bash
cd /home/moston/.openclaw/workspace/godot-office/export
python3 -m http.server 8080
# or
npx serve .
```

Then open: `http://localhost:8080`

## iFrame Embed Code

```html
<iframe 
    src="path/to/export/index.html" 
    width="1280" 
    height="720" 
    frameborder="0">
</iframe>
```
