import { randomInt } from 'node:crypto';
import { config } from './config.js';
import { db } from './db/db.js';

const API = `https://api.telegram.org/bot${config.botToken}`;
const STARS_PRICE = 100;

interface TelegramUpdate {
    update_id: number;
    message?: {
        message_id: number;
        chat: { id: number };
        text?: string;
        successful_payment?: { telegram_payment_charge_id: string; total_amount: number };
    };
    callback_query?: {
        id: string;
        data?: string;
        message?: { chat: { id: number } };
    };
    pre_checkout_query?: { id: string };
}

async function callApi<T = unknown>(
    method: string,
    body: unknown
): Promise<{ ok: boolean; result?: T; description?: string }> {
    if (!config.botToken) {
        console.warn(`telegram ${method} skipped: TELEGRAM_BOT_TOKEN is not set`);
        return { ok: false, description: 'no token' };
    }
    try {
        const res = await fetch(`${API}/${method}`, {
            method: 'POST',
            headers: { 'content-type': 'application/json' },
            body: JSON.stringify(body),
        });
        const data = (await res.json()) as { ok: boolean; result?: T; description?: string };
        if (!data.ok) {
            console.error(`telegram ${method} rejected: ${data.description}`);
        }
        return data;
    } catch (err) {
        console.error(`telegram ${method} threw`, err);
        return { ok: false, description: String(err) };
    }
}

interface SentMessage {
    message_id: number;
}

export async function sendBotMessage(chatId: number, text: string, replyMarkup?: unknown): Promise<boolean> {
    const res = await callApi<SentMessage>('sendMessage', { chat_id: chatId, text, reply_markup: replyMarkup });
    return res.ok;
}

export function deleteBotMessage(chatId: number, messageId: number): Promise<{ ok: boolean }> {
    return callApi('deleteMessage', { chat_id: chatId, message_id: messageId });
}

export function sendPremiumInvoice(chatId: number): Promise<{ ok: boolean; result?: SentMessage }> {
    return callApi<SentMessage>('sendInvoice', {
        chat_id: chatId,
        title: 'Свой номер Wisp',
        description: 'Выбор вида номера (США/Россия/анонимный) или свой на вход в приложение.',
        payload: 'wisp_premium_number',
        currency: 'XTR',
        prices: [{ label: 'Свой номер Wisp', amount: STARS_PRICE }],
    });
}

// ---------------------------------------------------------------------------
// Wisp numbers: display-only identifiers shaped like phone numbers.
//
// None of these are real, dialable numbers, nothing is ever sent to one
// outside this bot, and no telecom or SMS provider is involved anywhere in
// this file. A free account gets a random one; 100 Stars unlocks choosing
// the look, an "anonymous" one, or typing a custom string. Either way, the
// only channel a login code for the account is ever delivered through is
// this same Telegram chat — see chatIdForWispNumber / auth/routes.ts.
// ---------------------------------------------------------------------------

type FreeKind = 'us' | 'ru' | 'other';
type PremiumKind = FreeKind | 'anon';

const OTHER_COUNTRY_CODES = ['44', '49', '81', '86', '33', '39'];

function randomDigits(count: number): string {
    let out = '';
    for (let i = 0; i < count; i++) {
        out += String(randomInt(0, 10));
    }
    return out;
}

function generateWispNumber(kind: PremiumKind): string {
    switch (kind) {
        case 'us':
            return `+1${randomInt(2, 10)}${randomDigits(9)}`;
        case 'ru':
            return `+79${randomDigits(9)}`;
        case 'other': {
            const cc = OTHER_COUNTRY_CODES[randomInt(0, OTHER_COUNTRY_CODES.length)];
            return `+${cc}${randomInt(1, 10)}${randomDigits(8)}`;
        }
        case 'anon':
            // Deliberately not shaped like any of the codes above, and a length
            // that does not match a real numbering plan — the point is that it
            // does not read as being from anywhere in particular.
            return `+${randomInt(2, 10)}${randomDigits(randomInt(9, 13))}`;
    }
}

function pickFreeKind(): FreeKind {
    const kinds: FreeKind[] = ['us', 'ru', 'other'];
    return kinds[randomInt(0, kinds.length)];
}

interface SqliteLikeError {
    code?: string;
    errcode?: number;
    message?: string;
}

/** SQLITE_CONSTRAINT_UNIQUE. Narrow to this one error rather than swallowing
 *  every failure, so a real bug (a locked file, a missing table) still throws
 *  instead of quietly being read as "number taken". */
function isUniqueViolation(err: unknown): boolean {
    const e = err as SqliteLikeError;
    return e?.code === 'ERR_SQLITE_ERROR' && (e.errcode === 2067 || /UNIQUE constraint failed/.test(e.message ?? ''));
}

/** Attaches a wisp_number to this chat, creating the account on first use.
 *  Returns false when the number is already someone else's — the caller
 *  decides whether that means "try a different random one" (free/premium
 *  pick) or "tell the user to choose another" (custom entry). */
function trySetWispNumber(chatId: number, wispNumber: string): boolean {
    try {
        db.prepare(
            `INSERT INTO users (wisp_number, telegram_chat_id, display_name, created_at)
             VALUES (?, ?, ?, ?)
             ON CONFLICT(telegram_chat_id) DO UPDATE SET wisp_number = excluded.wisp_number, display_name = excluded.display_name`
        ).run(wispNumber, chatId, wispNumber, Date.now());
        return true;
    } catch (err) {
        if (isUniqueViolation(err)) {
            return false;
        }
        throw err;
    }
}

const MAX_RANDOM_ATTEMPTS = 20;

function assignRandomNumber(chatId: number, kind: PremiumKind): string {
    for (let i = 0; i < MAX_RANDOM_ATTEMPTS; i++) {
        const candidate = generateWispNumber(kind);
        if (trySetWispNumber(chatId, candidate)) {
            return candidate;
        }
    }
    throw new Error('could not find a free wisp_number after many attempts — the random space is probably too small');
}

interface UserRow {
    wisp_number: string;
    is_premium: number;
    is_admin: number;
}

function userForChat(chatId: number): UserRow | undefined {
    return db.prepare('SELECT wisp_number, is_premium, is_admin FROM users WHERE telegram_chat_id = ?').get(chatId) as
        | UserRow
        | undefined;
}

function isAdminChat(chatId: number): boolean {
    return Boolean(userForChat(chatId)?.is_admin);
}

/** Whether this chat can use the country/anonymous/custom picker — either it
 *  paid, or it is an admin, which skips payment everywhere that access is
 *  checked rather than in one place that is easy to miss extending later. */
function hasPremiumAccess(chatId: number): boolean {
    const user = userForChat(chatId);
    return Boolean(user?.is_premium) || Boolean(user?.is_admin);
}

function setPremium(chatId: number): void {
    db.prepare('UPDATE users SET is_premium = 1 WHERE telegram_chat_id = ?').run(chatId);
}

/** Paying is allowed as someone's very first action, before they have ever
 *  picked a free number — but wisp_number is NOT NULL, and setPremium's
 *  UPDATE only touches an existing row, so without this, paying first left
 *  no row for it to mark and the charge silently didn't unlock anything.
 *  Gives them a starter random number, which the premium menu then lets
 *  them replace immediately after. A no-op for anyone who already has one. */
function ensureUserRow(chatId: number): void {
    if (!userForChat(chatId)) {
        assignRandomNumber(chatId, pickFreeKind());
    }
}

/** Grants admin on every configured chat id, creating the account first if
 *  it does not exist yet. Called once at startup (index.ts) — this is the
 *  only path that can ever set is_admin; nothing reachable through the bot
 *  itself does. Safe to call repeatedly: re-applying to an existing admin
 *  changes nothing. */
export function applyAdminBootstrap(): void {
    for (const chatId of config.adminChatIds) {
        ensureUserRow(chatId);
        db.prepare('UPDATE users SET is_admin = 1 WHERE telegram_chat_id = ?').run(chatId);
    }
}

/** The chat id to send a login code to for this wisp_number, or null if it is not assigned. */
export function chatIdForWispNumber(wispNumber: string): number | null {
    const row = db.prepare('SELECT telegram_chat_id FROM users WHERE wisp_number = ?').get(wispNumber) as
        | { telegram_chat_id: number }
        | undefined;
    return row?.telegram_chat_id ?? null;
}

// ---------------------------------------------------------------------------
// Keyboards
// ---------------------------------------------------------------------------

const START_KEYBOARD = {
    inline_keyboard: [
        [{ text: '🆓 Бесплатный (случайный)', callback_data: 'free' }],
        [{ text: `⭐ Свой — ${STARS_PRICE} звёзд`, callback_data: 'buy_premium' }],
    ],
};

const PREMIUM_KEYBOARD = {
    inline_keyboard: [
        [
            { text: '🇺🇸 США', callback_data: 'premium_us' },
            { text: '🇷🇺 Россия', callback_data: 'premium_ru' },
        ],
        [{ text: '🎭 Анонимный', callback_data: 'premium_anon' }],
        [{ text: '✏️ Свой номер', callback_data: 'premium_custom' }],
    ],
};

function accountText(number: string): string {
    return `Ваш номер Wisp: ${number}\n\nЭто не настоящий телефон — он нужен только для входа в приложение. Коды входа будут приходить сюда, в этот чат.`;
}

// ---------------------------------------------------------------------------
// Update handling
// ---------------------------------------------------------------------------

/** Chats we are waiting on a typed custom number from. A plain Set is fine —
 *  it is a short-lived "what are we in the middle of asking this chat" flag,
 *  not data that needs to survive a restart. */
const awaitingCustomNumber = new Set<number>();

async function handleStart(chatId: number): Promise<void> {
    const user = userForChat(chatId);
    if (!user) {
        await sendBotMessage(
            chatId,
            'Привет! Нужен номер для входа в Wisp — настоящий телефон не нужен.\n\nБесплатно — случайный. За звёзды — выбираете вид сами или вписываете свой.',
            START_KEYBOARD
        );
        return;
    }
    const keyboard = hasPremiumAccess(chatId) ? PREMIUM_KEYBOARD : START_KEYBOARD;
    const prefix = user.is_admin ? '👑 Админ.\n\n' : '';
    await sendBotMessage(chatId, prefix + accountText(user.wisp_number), keyboard);
}

async function handleCallback(update: NonNullable<TelegramUpdate['callback_query']>): Promise<void> {
    const chatId = update.message?.chat.id;
    const data = update.data;
    if (!chatId || !data) {
        await answerCallbackQuery(update.id);
        return;
    }

    if (data === 'free') {
        const number = assignRandomNumber(chatId, pickFreeKind());
        await answerCallbackQuery(update.id);
        await sendBotMessage(chatId, accountText(number), START_KEYBOARD);
        return;
    }

    if (data === 'buy_premium') {
        if (hasPremiumAccess(chatId)) {
            const user = userForChat(chatId)!;
            await answerCallbackQuery(update.id, user.is_admin ? 'Вы админ — оплата не нужна.' : 'У вас уже есть доступ.');
            await sendBotMessage(chatId, accountText(user.wisp_number), PREMIUM_KEYBOARD);
            return;
        }
        await answerCallbackQuery(update.id);
        await sendPremiumInvoice(chatId);
        return;
    }

    const premiumKinds: Record<string, PremiumKind> = { premium_us: 'us', premium_ru: 'ru', premium_anon: 'anon' };
    if (data in premiumKinds) {
        if (!hasPremiumAccess(chatId)) {
            await answerCallbackQuery(update.id, 'Сначала оплатите доступ.');
            return;
        }
        const number = assignRandomNumber(chatId, premiumKinds[data]);
        await answerCallbackQuery(update.id);
        await sendBotMessage(chatId, accountText(number), PREMIUM_KEYBOARD);
        return;
    }

    if (data === 'premium_custom') {
        if (!hasPremiumAccess(chatId)) {
            await answerCallbackQuery(update.id, 'Сначала оплатите доступ.');
            return;
        }
        awaitingCustomNumber.add(chatId);
        await answerCallbackQuery(update.id);
        await sendBotMessage(chatId, 'Пришлите желаемый номер в формате +ХХХХХХХХХХ.');
        return;
    }

    await answerCallbackQuery(update.id);
}

const CUSTOM_NUMBER_RE = /^\+\d{6,15}$/;

async function handleCustomNumberReply(chatId: number, text: string): Promise<void> {
    awaitingCustomNumber.delete(chatId);
    const candidate = text.trim();
    if (!CUSTOM_NUMBER_RE.test(candidate)) {
        await sendBotMessage(
            chatId,
            'Не похоже на номер. Формат: + и от 6 до 15 цифр. Нажмите /start, чтобы попробовать снова.'
        );
        return;
    }

    if (trySetWispNumber(chatId, candidate)) {
        await sendBotMessage(chatId, accountText(candidate), PREMIUM_KEYBOARD);
        return;
    }

    // Taken by someone else. Only an admin can take it anyway — bump the
    // previous holder to a fresh random number rather than leaving their
    // account without one, and tell them why it changed.
    if (isAdminChat(chatId)) {
        const previousHolder = chatIdForWispNumber(candidate);
        if (previousHolder !== null && previousHolder !== chatId) {
            const replacement = assignRandomNumber(previousHolder, pickFreeKind());
            await sendBotMessage(
                previousHolder,
                `Ваш номер Wisp понадобился администратору. Новый: ${replacement}`
            );
        }
        trySetWispNumber(chatId, candidate); // now free; cannot fail
        await sendBotMessage(chatId, `Забрано у другого аккаунта.\n\n${accountText(candidate)}`, PREMIUM_KEYBOARD);
        return;
    }

    await sendBotMessage(chatId, 'Этот номер уже занят. Нажмите /start и попробуйте другой.');
}

async function handleSuccessfulPayment(
    chatId: number,
    payment: { telegram_payment_charge_id: string; total_amount: number }
): Promise<void> {
    try {
        db.prepare('INSERT INTO payments (telegram_chat_id, charge_id, stars, created_at) VALUES (?, ?, ?, ?)').run(
            chatId,
            payment.telegram_payment_charge_id,
            payment.total_amount,
            Date.now()
        );
    } catch (err) {
        if (isUniqueViolation(err)) {
            // Telegram redelivered an update we already processed — the
            // premium flag is already set from the first time, nothing more
            // to do.
            return;
        }
        throw err;
    }
    ensureUserRow(chatId);
    setPremium(chatId);
    await sendBotMessage(chatId, 'Оплата прошла. Выберите вид номера:', PREMIUM_KEYBOARD);
}

export async function handleUpdate(update: TelegramUpdate): Promise<void> {
    if (update.pre_checkout_query) {
        // Telegram cancels the payment if this is not answered within 10s.
        // Nothing here to actually validate — the only thing sold is this
        // one flat-price unlock — so it is always accepted.
        await callApi('answerPreCheckoutQuery', { pre_checkout_query_id: update.pre_checkout_query.id, ok: true });
        return;
    }

    if (update.callback_query) {
        await handleCallback(update.callback_query);
        return;
    }

    const message = update.message;
    if (!message) {
        return;
    }
    const chatId = message.chat.id;

    if (message.successful_payment) {
        await handleSuccessfulPayment(chatId, message.successful_payment);
        return;
    }

    if (message.text === '/start') {
        await handleStart(chatId);
        return;
    }

    if (awaitingCustomNumber.has(chatId) && message.text) {
        await handleCustomNumberReply(chatId, message.text);
        return;
    }

    await sendBotMessage(chatId, 'Нажмите /start.');
}

function answerCallbackQuery(id: string, text?: string): Promise<{ ok: boolean }> {
    return callApi('answerCallbackQuery', { callback_query_id: id, text, show_alert: Boolean(text) });
}

// ---------------------------------------------------------------------------
// Long polling
// ---------------------------------------------------------------------------

let polling = false;

/** Long polling, not a webhook: it needs no public HTTPS endpoint or TLS
 *  certificate, so it works the moment a bot token exists, wherever this
 *  process runs. Swapping to a webhook later (once there is a domain in
 *  front of the server) only touches this section. */
export function startBotPolling(): void {
    if (!config.botToken) {
        console.warn('TELEGRAM_BOT_TOKEN не задан — бот не сможет ни выдавать номера, ни присылать коды входа.');
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
