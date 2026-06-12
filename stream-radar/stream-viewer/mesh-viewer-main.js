// Standalone mesh inspector — runs alongside the radar (separate Electron userData, no lock clash).
//   npm run mesh                          open empty, type an id
//   npm run mesh -- 117805356475599       load a mesh straight away
//   npm run mesh -- 117805356475599 125957035805244    ... with a texture
//   npm run mesh -- 123284302443490 0 100044382834735  game-restricted asset: pass its place id 3rd
//                                                       (use 0 for the texture slot to skip it)
const { app, BrowserWindow } = require('electron');
const path = require('path');
const os = require('os');

app.setPath('userData', path.join(os.tmpdir(), 'serotonin-mesh-viewer'));

const args = process.argv.slice(2).filter((a) => /^\d+$/.test(a));

app.whenReady().then(() => {
  const win = new BrowserWindow({
    width: 1000,
    height: 760,
    title: 'Mesh Inspector',
    autoHideMenuBar: true,
    webPreferences: {
      nodeIntegration: true,
      contextIsolation: false,
      additionalArguments: [
        ...(args[0] ? [`--mesh-id=${args[0]}`] : []),
        ...(args[1] && args[1] !== '0' ? [`--tex-id=${args[1]}`] : []),   // 0 = skip texture slot
        ...(args[2] ? [`--place-id=${args[2]}`] : []),
      ],
    },
  });
  win.loadFile('mesh-viewer.html');
});

app.on('window-all-closed', () => app.quit());
