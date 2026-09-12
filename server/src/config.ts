/**
 * All server configuration in one place, read once at startup. Nothing here reads
 * process.env directly outside this file, so a missing or malformed variable fails
 * loudly here instead of producing a confusing error three modules deep.
 */
export const config = {
    port: Number(process.env.PORT ?? 8080),
    dbPath: process.env.DB_PATH ?? 'data/netegram.db',
    botToken: process.env.TELEGRAM_BOT_TOKEN ?? '',
    /** How long a login code stays valid after it is sent. */
    codeTtlMs: 5 * 60 * 1000,
    codeLength: 6,
};
