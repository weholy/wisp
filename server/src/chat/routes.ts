import { Router } from 'express';
import { db } from '../db/db.js';
import { requireAuth } from '../auth/session.js';

export const chatRouter = Router();
chatRouter.use(requireAuth);

chatRouter.get('/', (req, res) => {
    const rows = db
        .prepare(
            `SELECT c.id, c.kind, c.title,
                    (SELECT text FROM messages m WHERE m.chat_id = c.id ORDER BY m.id DESC LIMIT 1) AS last_text,
                    (SELECT created_at FROM messages m WHERE m.chat_id = c.id ORDER BY m.id DESC LIMIT 1) AS last_at
             FROM chats c
             JOIN chat_members cm ON cm.chat_id = c.id
             WHERE cm.user_id = ?
             ORDER BY last_at DESC`
        )
        .all(req.user!.id);
    res.json(rows);
});

chatRouter.post('/direct', (req, res) => {
    const peerPhone = String(req.body?.phone ?? '').trim();
    const peer = db.prepare('SELECT id FROM users WHERE phone = ?').get(peerPhone) as { id: number } | undefined;
    if (!peer) {
        res.status(404).json({ error: 'user_not_found' });
        return;
    }
    if (peer.id === req.user!.id) {
        res.status(400).json({ error: 'self_chat' });
        return;
    }

    const existing = db
        .prepare(
            `SELECT c.id FROM chats c
             JOIN chat_members a ON a.chat_id = c.id AND a.user_id = ?
             JOIN chat_members b ON b.chat_id = c.id AND b.user_id = ?
             WHERE c.kind = 'direct'`
        )
        .get(req.user!.id, peer.id) as { id: number } | undefined;
    if (existing) {
        res.json({ id: existing.id });
        return;
    }

    const chatId = Number(
        db.prepare(`INSERT INTO chats (kind, title, created_at) VALUES ('direct', NULL, ?)`).run(Date.now())
            .lastInsertRowid
    );
    const addMember = db.prepare('INSERT INTO chat_members (chat_id, user_id) VALUES (?, ?)');
    addMember.run(chatId, req.user!.id);
    addMember.run(chatId, peer.id);
    res.json({ id: chatId });
});

chatRouter.get('/:id/messages', (req, res) => {
    const chatId = Number(req.params.id);
    const isMember = db
        .prepare('SELECT 1 FROM chat_members WHERE chat_id = ? AND user_id = ?')
        .get(chatId, req.user!.id);
    if (!isMember) {
        res.status(403).json({ error: 'not_a_member' });
        return;
    }
    const rows = db
        .prepare('SELECT id, sender_id, text, created_at FROM messages WHERE chat_id = ? ORDER BY id DESC LIMIT 50')
        .all(chatId);
    res.json(rows.reverse());
});
