import type { NextFunction, Request, Response } from 'express';
import { db } from '../db/db.js';

export interface AuthedUser {
    id: number;
    wisp_number: string;
    display_name: string;
}

declare module 'express-serve-static-core' {
    interface Request {
        user?: AuthedUser;
    }
}

export function requireAuth(req: Request, res: Response, next: NextFunction): void {
    const header = req.header('authorization') ?? '';
    const token = header.startsWith('Bearer ') ? header.slice(7) : '';
    if (!token) {
        res.status(401).json({ error: 'no_token' });
        return;
    }

    const row = db
        .prepare(
            `SELECT u.id, u.wisp_number, u.display_name
             FROM sessions s JOIN users u ON u.id = s.user_id
             WHERE s.token = ?`
        )
        .get(token) as AuthedUser | undefined;
    if (!row) {
        res.status(401).json({ error: 'bad_token' });
        return;
    }
    req.user = row;
    next();
}
