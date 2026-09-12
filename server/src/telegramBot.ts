import { config } from './config.js';
import { db } from './db/db.js';

const API = `https://api.telegram.org/bot${config.botToken}`;

interface TelegramUpdate {
    update_id: number;
    message?: {
        chat: { id: number };
        from?: { id: number };
        text?: string;
        contact?: { phone_number: string; user_id?: number };
    };
}

/** Returns whether Telegram accepted the call — callers use this to tell a real
 *  delivery failure apart from success, instead of assuming every call worked. */
async function callApi(method: string, body: unknown): Promise<boolean> {
    if (!config.botToken) {
        console.warn(`telegram ${method} skipped: TELEGRAM_BOT_TOKEN is not set`);
        return false;
    }
    try {
        const res = await fetch(`${API}/${method}`, {
            method: 'POST',
            headers: { 'content-type': 'application/json' },
            body: JSON.stringify(body),
        });
        if (!res.ok) {
            console.error(`telegram ${method} failed: ${res.status} ${await res.text()}`);
            return false;
        }
        return true;
    } catch (err) {
        console.error(`telegram ${method} threw`, err);
        return false;
    }
}

export function sendBotMessage(chatId: number, text: string): Promise<boolean> {
    return callApi('sendMessage', { chat_id: chatId, text });
}

// request_contact only lets the user share the phone number their own
// Telegram account is registered under — they cannot type an arbitrary one
// in. That is what makes this a trustworthy way to link a phone number to a
// delivery address: Telegram already verified it when the account was made.
const REQUEST_CONTACT_KEYBOARD = {
    keyboard: [[{ text: '📱 Отправить номер', request_contact: true }]],
    resize_keyboard: true,
    one_time_keyboard: true,
};

function normalizePhone(raw: string): string {
    // Telegram's contact payload is not consistently formatted (sometimes a
    // leading +, sometimes not, occasionally with spaces). Reducing to digits
    // and re-adding "+" makes it match whatever E.164-ish string the app sends
    // when the user later types the same number to log in.
    return `+${raw.replace(/\D/g, '')}`;
}

function linkPhoneToChat(phone: string, chatId: number): void {
    db.prepare(
        `INSERT INTO users (phone, telegram_chat_id, display_name, created_at)
         VALUES (?, ?, ?, ?)
         ON CONFLICT(phone) DO UPDATE SET telegram_chat_id = excluded.telegram_chat_id`
    ).run(phone, chatId, phone, Date.now());
}

/** The chat id to send a login code to for this phone, or null if nobody has linked it yet. */
export function chatIdForPhone(phone: string): number | null {
    const row = db.prepare('SELECT telegram_chat_id FROM users WHERE phone = ?').get(phone) as
        | { telegram_chat_id: number | null }
        | undefined;
    return row?.telegram_chat_id ?? null;
}

async function handleUpdate(update: TelegramUpdate): Promise<void> {
    const message = update.message;
    if (!message) {
        return;
    }
    const chatId = message.chat.id;

    if (message.contact) {
        // A well-behaved client only lets you share your own contact, but the
        // Bot API does not enforce that server-side — check it here rather
        // than trust the field.
        if (message.contact.user_id && message.from && message.contact.user_id !== message.from.id) {
            await sendBotMessage(chatId, 'Поделитесь своим номером, не чужим.');
            return;
        }
        const phone = normalizePhone(message.contact.phone_number);
        linkPhoneToChat(phone, chatId);
        await sendBotMessage(chatId, `Готово: номер ${phone} привязан. Коды входа будут приходить сюда.`);
        return;
    }

    if (message.text === '/start') {
        await callApi('sendMessage', {
            chat_id: chatId,
            text: 'Привет! Чтобы входить в Netegram по коду, поделитесь номером телефона.',
            reply_markup: REQUEST_CONTACT_KEYBOARD,
        });
        return;
    }

    await sendBotMessage(chatId, 'Нажмите /start, чтобы привязать номер.');
}

let polling = false;

/** Long polling, not a webhook: it needs no public HTTPS endpoint or TLS certificate,
 *  so it works the moment a bot token exists, wherever this process runs. Swapping to
 *  a webhook later (once there is a domain in front of the server) only touches this
 *  file. */
export function startBotPolling(): void {
    if (!config.botToken) {
        console.warn('TELEGRAM_BOT_TOKEN не задан — вход по коду через бота работать не будет.');
        return;
    }
    polling = true;
    void pollLoop();
}

export function stopBotPolling(): void {
    polling = false;
}

async function pollLoop(): Promise<void> {
    let offset = 0;
    while (polling) {
        try {
            // timeout=30 asks Telegram to hold the request open for up to 30s
            // and answer as soon as an update exists, rather than us polling
            // in a tight loop.
            const res = await fetch(`${API}/getUpdates?timeout=30&offset=${offset}`);
            const data = (await res.json()) as { ok: boolean; result: TelegramUpdate[] };
            if (!data.ok) {
                await sleep(2000);
                continue;
            }
            for (const update of data.result) {
                offset = update.update_id + 1;
                await handleUpdate(update).catch((err) => console.error('bot update failed', err));
            }
        } catch (err) {
            console.error('bot poll failed', err);
            await sleep(2000);
        }
    }
}

function sleep(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
}
