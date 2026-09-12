import { randomBytes } from 'node:crypto';
import { Router } from 'express';
import { db } from '../db/db.js';
import { chatIdForPhone, sendBotMessage } from '../telegramBot.js';
import { issueCode, verifyCode } from './codes.js';

export const authRouter = Router();

// A loose E.164 check: leading +, 7-15 digits total. Good enough to reject
// obvious junk before it reaches the bot lookup.
const PHONE_RE = /^\+[1-9]\d{6,14}$/;

authRouter.post('/request-code', async (req, res) => {
    const phone = String(req.body?.phone ?? '').trim();
    if (!PHONE_RE.test(phone)) {
        res.status(400).json({ error: 'bad_phone' });
        return;
    }

    const chatId = chatIdForPhone(phone);
    if (!chatId) {
        res.status(404).json({
            error: 'not_linked',
            message: 'Сначала откройте бота в Telegram и поделитесь номером — тогда сюда можно будет прислать код.',
        });
        return;
    }

    const code = issueCode(phone);
    const delivered = await sendBotMessage(chatId, `Код для входа в Netegram: ${code}`);
    if (!delivered) {
        res.status(502).json({ error: 'delivery_failed', message: 'Не удалось отправить код через бота.' });
        return;
    }
    res.json({ ok: true });
});

authRouter.post('/verify', (req, res) => {
    const phone = String(req.body?.phone ?? '').trim();
    const code = String(req.body?.code ?? '').trim();
    if (!verifyCode(phone, code)) {
        res.status(401).json({ error: 'bad_code' });
        return;
    }

    // Reachable only for a phone that request-code already found a user row
    // for, so this lookup cannot come back empty in practice.
    const user = db.prepare('SELECT id, phone, display_name FROM users WHERE phone = ?').get(phone) as
        | { id: number; phone: string; display_name: string }
        | undefined;
    if (!user) {
        res.status(500).json({ error: 'internal' });
        return;
    }

    const token = randomBytes(32).toString('hex');
    db.prepare('INSERT INTO sessions (token, user_id, created_at) VALUES (?, ?, ?)').run(token, user.id, Date.now());
    res.json({ token, user });
});
