import helmet from 'helmet';
import cors from 'cors';
import logger from '../utils/logger.js';

/**
 * Enterprise Security Configuration
 */

// 1. Helmet: Secure Headers (API-only mode)
export const securityHeaders = helmet({
    contentSecurityPolicy: false,
    crossOriginEmbedderPolicy: false,
    crossOriginResourcePolicy: false, // Essential for Flutter Web image fetching
});

// 2. CORS: Strict Origin Whitelisting
const getAllowedOrigins = () => {
    const origins = process.env.CORS_ALLOWED_ORIGINS;
    if (!origins) {
        return process.env.NODE_ENV === 'production' ? [] : '*';
    }
    return origins.split(',').map(o => o.trim());
};

export const corsOptions = cors({
    origin: (origin, callback) => {
        // In non-production, allow all to simplify local development
        if (process.env.NODE_ENV !== 'production') {
            return callback(null, true);
        }

        const allowed = getAllowedOrigins();
        const isLocal = origin && (origin.startsWith('http://localhost') || origin.startsWith('http://127.0.0.1'));

        if (!origin || allowed === '*' || allowed.includes(origin) || isLocal) {
            callback(null, true);
        } else {
            logger.warn({ origin }, 'CORS Blocked');
            callback(null, false); // Don't throw to avoid crashing preflight
        }
    },
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization', 'X-Requested-With', 'Accept', 'Cache-Control'],
    credentials: true,
    maxAge: 86400,
});

// 4. Request Timeout Middleware
export const requestTimeout = (req, res, next) => {
    // Skip hard timeout for:
    // - Multipart uploads (large file I/O)
    // - Feed/posts reads (Firestore cold-read latency can exceed 5s)
    // - Interactions (batch lookup of likes can be slow)
    // - Proxy requests (external fetch latency)
    const isMultipart = req.headers['content-type']?.includes('multipart/form-data');
    const isSlowRoute = req.path.startsWith('/api/posts') ||
        req.path.startsWith('/api/proxy') ||
        req.path.startsWith('/api/interactions');

    if (isMultipart || isSlowRoute) {
        return next();
    }

    // 15-second hard timeout for all other JSON/REST requests
    res.setTimeout(15000, () => {
        if (!res.headersSent) {
            const err = new Error('Service Timeout: Request took too long');
            err.status = 503;
            err.code = 'infra/timeout';
            next(err);
        }
    });
    next();
};
