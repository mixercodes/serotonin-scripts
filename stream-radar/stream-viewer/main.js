// main.js — Electron entry point for the Serotonin 3D stream radar.
// Opens a frameless-ish window and loads the Three.js renderer. nodeIntegration is on so the
// renderer can use fs.watch directly against the stream directory — this is a local-only tool.
//
// Optional hosting: `--host=localhost` or `--host=lan` ALSO serves the radar over HTTP
// (server.js) so browsers on this machine / any LAN device can open it. `--port=N` overrides
// the default 8137. Plain HTTP, no auth — never expose it beyond your own network.

const { app, BrowserWindow } = require('electron');
const path = require('path');
const os = require('os');

// Where stream.lua writes its JSON. file.* sandbox root is files/, so stream/ lands here.
// Override with STREAM_DIR env var if your Serotonin install lives elsewhere.
const STREAM_DIR = process.env.STREAM_DIR || 'C:/Serotonin/files/stream';

const hostArg = (process.argv.find((a) => a.startsWith('--host=')) || '').slice(7);
const portRaw = (process.argv.find((a) => a.startsWith('--port=')) || '').slice(7);
const portArg = portRaw ? +portRaw : 8137;
if (!Number.isInteger(portArg) || portArg < 1 || portArg > 65535) {
  console.error(`bad --port value "${portRaw}" — use an integer 1-65535`);
  app.exit(1);
}
if (hostArg && hostArg !== 'localhost' && hostArg !== 'lan') {
  console.error(`unknown --host value "${hostArg}" — use --host=localhost or --host=lan`);
  app.exit(1);
}

let titleSuffix = '';
if (hostArg === 'localhost' || hostArg === 'lan') {
  const { createRadarServer } = require('./server.js');
  const srv = createRadarServer({
    streamDir: STREAM_DIR,
    appDir: __dirname,
    host: hostArg === 'lan' ? '0.0.0.0' : '127.0.0.1',
    port: portArg,
  });
  srv.server.on('error', (err) => {
    console.error('radar server failed:', err.message);
    titleSuffix = ' — hosting FAILED';
    for (const w of BrowserWindow.getAllWindows()) w.setTitle('Serotonin Radar' + titleSuffix);
  });
  srv.server.on('listening', () => {
    const urls = hostArg === 'lan'
      ? Object.values(os.networkInterfaces()).flat()
          .filter((i) => i && i.family === 'IPv4' && !i.internal)
          .map((i) => `http://${i.address}:${portArg}`)
      : [`http://127.0.0.1:${portArg}`];
    console.log('radar hosted at  ' + urls.join('  '));
  });
  titleSuffix = ` — hosting :${portArg} (${hostArg})`;
}

function createWindow() {
  const win = new BrowserWindow({
    width: 1280,
    height: 800,
    backgroundColor: '#0a0e14',
    title: 'Serotonin Radar' + titleSuffix,
    webPreferences: {
      nodeIntegration: true,
      contextIsolation: false,
      additionalArguments: [`--stream-dir=${STREAM_DIR}`],
    },
  });

  win.setMenuBarVisibility(false);
  win.loadFile(path.join(__dirname, 'index.html'));
}

app.whenReady().then(() => {
  createWindow();
  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});
