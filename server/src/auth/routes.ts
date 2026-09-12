import { randomBytes } from 'node:crypto';
import { Router } from 'express';
import { db } from '../db/db.js';
import { chatIdForWispNumber, sendBotMessage } from '../telegramBot.js';
import { issueCode, verifyCode } from './codes.js';

export const authRouter = Router();

// Same shape the bot generates and accepts for a custom entry: leading +,
// 6-15 digits. Not a real phone number format check — wisp_number is not a
// real phone number.
const WISP_NUMBER_RE = /^\+\d{6,15}$/;

authRouter.post('/request-code', async (req, res) => {
    const wispNumber = String(req.body?.wispNumber ?? '').trim();
    if (!WISP_NUMBER_RE.test(wispNumber)) {
        res.status(400).json({ error: 'bad_number' });
        return;
    }

    const chatId = chatIdForWispNumber(wispNumber);
    if (!chatId) {
        res.status(404).json({
            error: 'not_linked',
            message: 'Такого номера Wisp не существует. Получите его у бота: /start.',
        });
        return;
    }

    const code = issueCode(wispNumber);
    const delivered = await sendBotMessage(chatId, `Код для входа в Wisp: ${code}`);
    if (!delivered) {
        res.status(502).json({ error: 'delivery_failed', message: 'Не удалось отправить код через бота.' });
        return;
    }
    res.json({ ok: true });
});

authRouter.post('/verify', (req, res) => {
    const wispNumber = String(req.body?.wispNumber ?? '').trim();
    const code = String(req.body?.code ?? '').trim();
    if (!verifyCode(wispNumber, code)) {
        res.status(401).json({ error: 'bad_code' });
        return;
    }

    // Reachable only for a number that request-code already found a user row
    // for, so this lookup cannot come back empty in practice.
    const user = db.prepare('SELECT id, wisp_number, display_name FROM users WHERE wisp_number = ?').get(wispNumber) as
        | { id: number; wisp_number: string; display_name: string }
        | undefined;
    if (!user) {
        res.status(500).json({ error: 'internal' });
        return;
    }

    const token = randomBytes(32).toString('hex');
    db.prepare('INSERT INTO sessions (token, user_id, created_at) VALUES (?, ?, ?)').run(token, user.id, Date.now());
    res.json({ token, user });
});
