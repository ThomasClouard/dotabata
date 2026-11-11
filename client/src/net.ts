// Connexion WebSocket + synchronisation de l'horloge serveur (les obstacles en dépendent).
import type { ClientMsg, ServerMsg } from '../../shared/src/protocol';

export class Net {
  id = '';
  private ws!: WebSocket;
  private offset = 0; // horloge serveur - horloge locale
  private bestRtt = Infinity;
  private pings = 0;
  onMessage: (m: ServerMsg) => void = () => {};
  onClose: () => void = () => {};

  connect(hello: Extract<ClientMsg, { t: 'hello' }>): void {
    const proto = location.protocol === 'https:' ? 'wss' : 'ws';
    this.ws = new WebSocket(`${proto}://${location.host}/ws`);
    this.ws.onopen = () => {
      this.send(hello);
      this.ping();
    };
    this.ws.onmessage = (e) => {
      const m = JSON.parse(e.data) as ServerMsg;
      if (m.t === 'welcome') {
        this.id = m.id;
        this.offset = m.time - performance.now() / 1000;
      } else if (m.t === 'pong') {
        const now = performance.now() / 1000, rtt = now - m.c;
        // on garde l'estimation issue de l'aller-retour le plus rapide
        if (rtt <= this.bestRtt + 0.002) {
          this.bestRtt = Math.min(this.bestRtt, rtt);
          this.offset = m.time + rtt / 2 - now;
        }
        return;
      }
      this.onMessage(m);
    };
    this.ws.onclose = () => this.onClose();
  }

  private ping(): void {
    if (this.ws.readyState !== WebSocket.OPEN) return;
    this.send({ t: 'ping', c: performance.now() / 1000 });
    setTimeout(() => this.ping(), this.pings++ < 8 ? 250 : 3000);
  }

  send(m: ClientMsg): void {
    if (this.ws?.readyState === WebSocket.OPEN) this.ws.send(JSON.stringify(m));
  }

  now(): number {
    return performance.now() / 1000 + this.offset;
  }
}
