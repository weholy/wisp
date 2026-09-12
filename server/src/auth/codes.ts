import { config } from '../config.js';

interface PendingCode {
    code: string;
    expiresAt: number;
    attempts: number;
}

/**
 * In-memory, not a table: a code lives minutes and is single-use, so nothing
 * is lost by forgetting it on a restart, and a real table would just be
 * something to clean up. If this ever runs as more than one process, this
 * needs to move to shared storage (Redis, or the same SQLite file) — noted
 * here so it isn't a silent trap later.
 */
const pending = new Map<string, PendingCode>();

const MAX_ATTEMPTS = 5;

export function issueCode(phone: string): string {
    const code = String(Math.floor(Math.random() * 10 ** config.codeLength)).padStart(config.codeLength, '0');
    pending.set(phone, { code, expiresAt: Date.now() + config.codeTtlMs, attempts: 0 });
    return code;
}

export function verifyCode(phone: string, code: string): boolean {
    const entry = pending.get(phone);
    if (!entry) {
        return false;
    }
    if (Date.now() > entry.expiresAt) {
        pending.delete(phone);
        return false;
    }
    entry.attempts += 1;
    if (entry.attempts > MAX_ATTEMPTS) {
        pending.delete(phone);
        return false;
    }
    if (entry.code !== code) {
        return false;
    }
    pending.delete(phone);
    return true;
}
