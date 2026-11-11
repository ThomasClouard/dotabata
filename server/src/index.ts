// Serveur de jeu : WebSocket + fichiers du client buildé. Un PC héberge, les autres ouvrent l'URL LAN.
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { WebSocketServer } from 'ws';
import { ROOT } from '../../shared/src/level-store';
import { Session } from './session';

const PORT = Number(process.env.JEUX_PORT ?? 3000);
const DIST = path.join(ROOT, 'client', 'dist');
const MIME: Record<string, string> = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.svg': 'image/svg+xml', '.png': 'image/png', '.ico': 'image/x-icon' };

const server = http.createServer((req, res) => {
  const url = decodeURIComponent((req.url ?? '/').split('?')[0]);
  const file = path.normalize(path.join(DIST, url === '/' ? 'index.html' : url));
  if (!file.startsWith(DIST)) { res.writeHead(403).end(); return; }
  fs.readFile(file, (err, data) => {
    if (err) {
      const built = fs.existsSync(path.join(DIST, 'index.html'));
      res.writeHead(built ? 404 : 503, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end(built ? 'Introuvable' : 'Le client n\'est pas encore construit. Lance « npm start » (ou « npm run dev » puis ouvre le port 5173).');
      return;
    }
    res.writeHead(200, { 'Content-Type': MIME[path.extname(file)] ?? 'application/octet-stream' });
    res.end(data);
  });
});

const lanIps = Object.values(os.networkInterfaces()).flat().filter((i) => i && i.family === 'IPv4' && !i.internal).map((i) => i!.address);
const dev = !!process.env.JEUX_DEV || process.argv.includes('--dev');
const clientPort = dev ? 5173 : PORT;
const urls = lanIps.map((ip) => `http://${ip}:${clientPort}`);

const session = new Session(urls);
const wss = new WebSocketServer({ server, path: '/ws' });
wss.on('connection', (ws) => session.connect(ws));

server.listen(PORT, '0.0.0.0', () => {
  console.log('\n  🎉 Dotabata! — serveur prêt');
  console.log(`  Sur ce PC      : http://localhost:${clientPort}`);
  for (const u of urls) console.log(`  Sur le réseau  : ${u}`);
  if (!urls.length) console.log('  (aucune adresse réseau détectée)');
  console.log('  Si les autres PC ne se connectent pas, autorise Node.js dans le pare-feu Windows.\n');
});
