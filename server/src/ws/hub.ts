import type { WebSocket } from 'ws';

interface Connection {
    ws: WebSocket;
}

/** Every open socket for a user — more than one when they are on several devices. */
const byUser = new Map<number, Set<Connection>>();

export function register(userId: number, ws: WebSocket): void {
    const conn: Connection = { ws };
    if (!byUser.has(userId)) {
        byUser.set(userId, new Set());
    }
    byUser.get(userId)!.add(conn);
    ws.on('close', () => {
        const set = byUser.get(userId);
        set?.delete(conn);
        if (set && set.size === 0) {
            byUser.delete(userId);
        }
    });
}

export function sendToUser(userId: number, payload: unknown): void {
    const conns = byUser.get(userId);
    if (!conns) {
        return; // offline — the message is already on disk, they'll get it from history on reconnect
    }
    const data = JSON.stringify(payload);
    for (const conn of conns) {
        if (conn.ws.readyState === conn.ws.OPEN) {
            conn.ws.send(data);
        }
    }
}

export function broadcastToChat(memberIds: number[], payload: unknown): void {
    for (const id of memberIds) {
        sendToUser(id, payload);
    }
}
