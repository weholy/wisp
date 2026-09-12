import type { Server } from 'node:http';
import { WebSocketServer, type WebSocket } from 'ws';
import { db } from '../db/db.js';
import { broadcastToChat, register } from './hub.js';

interface AuthedRow {
    id: number;
}

function userIdForToken(token: string): number | undefined {
    const row = db.prepare('SELECT user_id AS id FROM sessions WHERE token = ?').get(token) as AuthedRow | undefined;
    return row?.id;
}

/**
 * One socket per connected device, authenticated by a `?token=` query
 * parameter rather than a header: browsers' native WebSocket API cannot set
 * custom headers on the handshake, and matching that constraint here keeps a
 * future web client working without a different auth path.
 */
export function attachWebSocket(server: Server): void {
    const wss = new WebSocketServer({ server, path: '/ws' });

    wss.on('connection', (ws: WebSocket, req) => {
        const token = new URL(req.url ?? '', 'http://internal').searchParams.get('token') ?? '';
        const userId = userIdForToken(token);
        if (!userId) {
            ws.close(4001, 'unauthorized');
            return;
        }
        register(userId, ws);

        ws.on('message', (raw) => {
            let msg: { type?: string; chatId?: number; text?: string };
            try {
                msg = JSON.parse(raw.toString());
            } catch {
                return;
            }
            if (msg.type === 'send' && typeof msg.chatId === 'number' && msg.text?.trim()) {
                handleSend(userId, msg.chatId, msg.text.trim());
            }
        });
    });
}

function handleSend(senderId: number, chatId: number, text: string): void {
    const isMember = db.prepare('SELECT 1 FROM chat_members WHERE chat_id = ? AND user_id = ?').get(chatId, senderId);
    if (!isMember) {
        return; // not a member of this chat — drop rather than trust the client
    }

    const createdAt = Date.now();
    const id = Number(
        db
            .prepare('INSERT INTO messages (chat_id, sender_id, text, created_at) VALUES (?, ?, ?, ?)')
            .run(chatId, senderId, text, createdAt).lastInsertRowid
    );

    const memberIds = (
        db.prepare('SELECT user_id FROM chat_members WHERE chat_id = ?').all(chatId) as { user_id: number }[]
    ).map((r) => r.user_id);
    broadcastToChat(memberIds, { type: 'message', id, chatId, senderId, text, createdAt });
}
