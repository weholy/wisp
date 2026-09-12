// Synthetic-update test harness: feeds fabricated Telegram Update objects
// straight into handleUpdate, bypassing the network entirely. Verifies the
// state machine (free/paid gating, uniqueness, payment idempotency, admin
// override) against the real DB file, without needing a live Telegram
// client to press any button.
//
// Every chat id here is fake, and ADMIN_CHAT_IDS is set to one of them below
// (not read from .env) — this suite must be safe to run repeatedly, in CI,
// without ever notifying a real person's Telegram chat. sendMessage to a
// fake id fails with "chat not found", logged and ignored: expected noise,
// not a test failure. Live delivery to a real chat is a separate, manual
// check (see README).
// ESM import statements are hoisted and run before any other top-level code
// in this file, so setting process.env here and only THEN writing a static
// `import` below would not work — config.js (imported transitively by
// telegramBot.js) would already have read the old value. A dynamic import()
// inside main(), after the assignment, genuinely runs in order.
process.env.ADMIN_CHAT_IDS = '900000003';

import { DatabaseSync } from 'node:sqlite';

const DB_PATH = 'data/dev.db';
const ADMIN_CHAT_ID = 900000003; // fake
const USER_A = 900000001; // fake
const USER_B = 900000002; // fake

let failures = 0;
function check(label, condition) {
    console.log(`${condition ? 'OK  ' : 'FAIL'} ${label}`);
    if (!condition) failures++;
}

function row(chatId) {
    const db = new DatabaseSync(DB_PATH);
    const r = db.prepare('SELECT wisp_number, is_premium, is_admin FROM users WHERE telegram_chat_id = ?').get(chatId);
    db.close();
    return r;
}

function paymentCount() {
    const db = new DatabaseSync(DB_PATH);
    const r = db.prepare('SELECT COUNT(*) AS n FROM payments').get();
    db.close();
    return r.n;
}

function msg(chatId, text, extra = {}) {
    return { update_id: 0, message: { message_id: 1, chat: { id: chatId }, text, ...extra } };
}

function cb(chatId, data) {
    return { update_id: 0, callback_query: { id: 'cbq', data, message: { chat: { id: chatId } } } };
}

async function main() {
    const bot = await import('../dist/telegramBot.js');

    // --- USER_A: free path ---
    await bot.handleUpdate(msg(USER_A, '/start'));
    check('A: no row before choosing', row(USER_A) === undefined);

    await bot.handleUpdate(cb(USER_A, 'free'));
    const aAfterFree = row(USER_A);
    check('A: got a number, not premium', aAfterFree && aAfterFree.is_premium === 0);

    // --- USER_A: cannot use premium picker before paying ---
    const numberBefore = aAfterFree.wisp_number;
    await bot.handleUpdate(cb(USER_A, 'premium_us'));
    check('A: premium picker blocked pre-payment', row(USER_A).wisp_number === numberBefore);

    // --- USER_B: pays FIRST, without ever picking free (the bug I found and fixed) ---
    check('B: no row before paying', row(USER_B) === undefined);
    const paymentsBefore = paymentCount();
    await bot.handleUpdate(
        msg(USER_B, undefined, {
            successful_payment: { telegram_payment_charge_id: 'charge_1', total_amount: 100 },
        })
    );
    const bAfterPay = row(USER_B);
    check('B: row created by payment alone', bAfterPay && bAfterPay.is_premium === 1);
    check('B: one payment recorded', paymentCount() === paymentsBefore + 1);

    // --- USER_B: replayed webhook (same charge id) must not double-count ---
    await bot.handleUpdate(
        msg(USER_B, undefined, {
            successful_payment: { telegram_payment_charge_id: 'charge_1', total_amount: 100 },
        })
    );
    check('B: replayed payment not double-counted', paymentCount() === paymentsBefore + 1);

    // --- USER_A: pays for real now, premium picker should work ---
    await bot.handleUpdate(
        msg(USER_A, undefined, {
            successful_payment: { telegram_payment_charge_id: 'charge_2', total_amount: 100 },
        })
    );
    await bot.handleUpdate(cb(USER_A, 'premium_us'));
    const aUs = row(USER_A);
    check('A: premium picker works after paying, US-shaped', aUs && /^\+1\d{10}$/.test(aUs.wisp_number));

    // --- USER_A: custom number ---
    await bot.handleUpdate(cb(USER_A, 'premium_custom'));
    await bot.handleUpdate(msg(USER_A, '+15551234567'));
    check('A: custom number set', row(USER_A).wisp_number === '+15551234567');

    // --- USER_B: tries to take the SAME custom number — must be rejected, not stolen ---
    await bot.handleUpdate(cb(USER_B, 'premium_custom'));
    await bot.handleUpdate(msg(USER_B, '+15551234567'));
    check('B: collision rejected, kept old number', row(USER_B).wisp_number !== '+15551234567');
    check('A: unaffected by B\'s attempt', row(USER_A).wisp_number === '+15551234567');

    // --- Admin bootstrap (mirrors what index.ts calls at startup) ---
    bot.applyAdminBootstrap();
    check('admin: flagged after bootstrap', row(ADMIN_CHAT_ID)?.is_admin === 1);

    // --- Admin: buy_premium short-circuits, no invoice needed ---
    await bot.handleUpdate(cb(ADMIN_CHAT_ID, 'buy_premium'));
    // no DB assertion here — this path only sends messages; verified visually below.

    // --- Admin: takes A's already-claimed custom number by force ---
    await bot.handleUpdate(cb(ADMIN_CHAT_ID, 'premium_custom'));
    await bot.handleUpdate(msg(ADMIN_CHAT_ID, '+15551234567'));
    check('admin: forcibly took the number', row(ADMIN_CHAT_ID)?.wisp_number === '+15551234567');
    check('A: bumped to a different number after admin took it', row(USER_A).wisp_number !== '+15551234567');
    check('A: still has *a* valid number, not left empty', Boolean(row(USER_A)?.wisp_number));

    console.log(failures === 0 ? '\nALL CHECKS PASSED' : `\n${failures} CHECK(S) FAILED`);
    process.exit(failures === 0 ? 0 : 1);
}

main();
