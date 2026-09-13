const { app, BrowserWindow, shell } = require('electron');
const http = require('node:http');
const path = require('node:path');
const fs = require('node:fs');

let mainWindow = null;
let localServer = null;

function resolveAppPath(...parts) {
  return path.join(app.getAppPath(), ...parts);
}

async function startLocalServer() {
  const userDataDirectory = app.getPath('userData');
  const environmentFile = path.join(userDataDirectory, '.env');

  fs.mkdirSync(userDataDirectory, { recursive: true });
  process.env.NODE_ENV = 'production';
  process.env.VERCEL = '1';
  process.env.SHADOWING_APP_ROOT = app.getAppPath();
  process.env.SHADOWING_WEB_DIR = resolveAppPath('dist');
  process.env.SHADOWING_DATA_DIR = path.join(userDataDirectory, 'library');
  process.env.SHADOWING_SETTINGS_FILE = path.join(userDataDirectory, 'settings.json');
  if (fs.existsSync(environmentFile)) process.env.SHADOWING_ENV_FILE = environmentFile;

  const { createApp } = require(resolveAppPath('dist', 'server.cjs'));
  const expressApp = await createApp({ includeFrontend: true });

  return new Promise((resolve, reject) => {
    localServer = http.createServer(expressApp);
    localServer.once('error', reject);
    localServer.listen(0, '127.0.0.1', () => {
      const address = localServer.address();
      if (!address || typeof address === 'string') {
        reject(new Error('Não foi possível iniciar o servidor local.'));
        return;
      }
      resolve(`http://127.0.0.1:${address.port}`);
    });
  });
}

async function createWindow() {
  const localUrl = await startLocalServer();

  mainWindow = new BrowserWindow({
    width: 1440,
    height: 920,
    minWidth: 1050,
    minHeight: 700,
    backgroundColor: '#050505',
    title: 'ShadowingAI',
    titleBarStyle: 'hiddenInset',
    trafficLightPosition: { x: 18, y: 18 },
    show: false,
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
    },
  });

  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    if (url.startsWith('https://') || url.startsWith('http://')) void shell.openExternal(url);
    return { action: 'deny' };
  });

  mainWindow.once('ready-to-show', () => mainWindow?.show());
  await mainWindow.loadURL(localUrl);
}

const hasSingleInstanceLock = app.requestSingleInstanceLock();

if (!hasSingleInstanceLock) {
  app.quit();
} else {
  app.on('second-instance', () => {
    if (!mainWindow) return;
    if (mainWindow.isMinimized()) mainWindow.restore();
    mainWindow.focus();
  });

  app.whenReady().then(createWindow).catch((error) => {
    console.error(error);
    app.quit();
  });
}

app.on('window-all-closed', () => app.quit());

app.on('before-quit', () => {
  localServer?.close();
});
