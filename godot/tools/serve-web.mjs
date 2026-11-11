// Petit serveur statique pour la version web du client Godot (dossier godot/build/web).
// Le serveur de jeu d'origine n'est pas modifié : cette page s'y connecte en WebSocket (port 3000 par défaut).
//   node godot/tools/serve-web.mjs            → http://localhost:8080
//   JEUX_WEB_PORT=9000 node godot/tools/serve-web.mjs
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'build', 'web');
const PORT = Number(process.env.JEUX_WEB_PORT ?? 8080);
const MIME = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.wasm': 'application/wasm', '.pck': 'application/octet-stream',
  '.png': 'image/png', '.ico': 'image/x-icon', '.svg': 'image/svg+xml', '.json': 'application/json', '.css': 'text/css',
};

const server = http.createServer((req, res) => {
  const url = decodeURIComponent((req.url ?? '/').split('?')[0]);
  const file = path.normalize(path.join(ROOT, url === '/' ? 'index.html' : url));
  if (!file.startsWith(ROOT)) { res.writeHead(403).end(); return; }
  fs.readFile(file, (err, data) => {
    if (err) {
      const built = fs.existsSync(path.join(ROOT, 'index.html'));
      res.writeHead(built ? 404 : 503, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end(built ? 'Introuvable' : 'La version web n\'est pas encore exportée. Voir godot/README.md, section « Exports ».');
      return;
    }
    res.writeHead(200, { 'Content-Type': MIME[path.extname(file)] ?? 'application/octet-stream', 'Cache-Control': 'no-cache' });
    res.end(data);
  });
});

server.listen(PORT, '0.0.0.0', () => {
  const ips = Object.values(os.networkInterfaces()).flat().filter((i) => i && i.family === 'IPv4' && !i.internal).map((i) => i.address);
  console.log('\n  Dotabata! — version web du client Godot');
  console.log(`  Sur ce PC      : http://localhost:${PORT}`);
  for (const ip of ips) console.log(`  Sur le réseau  : http://${ip}:${PORT}`);
  console.log('  Le serveur de jeu doit tourner à côté (« npm run serve », port 3000).');
  console.log('  Autre port ou autre machine : ajoute ?server=adresse:port à l\'URL.\n');
});
