/**
 * All server configuration in one place, read once at startup. Nothing here reads
 * process.env directly outside this file, so a missing or malformed variable fails
 * loudly here instead of producing a confusing error three modules deep.
 */
export const config = {
    port: Number(process.env.PORT ?? 8080),
    dbPath: process.env.DB_PATH ?? 'data/netegram.db',
    botToken: process.env.TELEGRAM_BOT_TOKEN ?? '',
    /** Telegram chat ids (numeric, comma-separated) that get admin rights on
     *  every startup — see applyAdminBootstrap in telegramBot.ts. This is the
     *  only way an account becomes admin; nothing reachable through the bot
     *  itself grants it. */
    adminChatIds: (process.env.ADMIN_CHAT_IDS ?? '')
        .split(',')
        .map((s) => s.trim())
        .filter(Boolean)
        .map(Number),
    /** How long a login code stays valid after it is sent. */
    codeTtlMs: 5 * 60 * 1000,
    codeLength: 6,
};
