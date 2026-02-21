import helmet from 'helmet';
import cors from 'cors';
import rateLimit from 'express-rate-limit';

/**
 * Enterprise Security Configuration
 */

// 1. Helmet: Secure Headers (API-only mode)
export const securityHeaders = helmet({
    contentSecurityPolicy: false, // API only, no frontend to protect
    crossOriginEmbedderPolicy: false,
});

// 2. CORS: Strict Origin Whitelisting
const getAllowedOrigins = () => {
    const origins = process.env.CORS_ALLOWED_ORIGINS;
    if (process.env.NODE_ENV === 'production' && !origins) {
        throw new Error('FATAL: CORS_ALLOWED_ORIGINS must be defined in production environment');
    }
    return origins?.split(',') || '*';
};

export const corsOptions = cors({
    origin: (origin, callback) => {
        const allowed = getAllowedOrigins();
        // Allow requests with no origin (like mobile apps or curl)
        if (!origin || allowed === '*' || allowed.includes(origin)) {
            callback(null, true);
        } else {
            callback(new Error('Not allowed by CORS'));
        }
    },
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH'],
    allowedHeaders: ['Content-Type', 'Authorization'],
    credentials: true,
    maxAge: 86400, // 24 hours
});

// 3. Rate Limiting: Global Base Throttling
// Combined Key: IP + UserID (if available)
export const globalLimiter = rateLimit({
    windowMs: 15 * 60 * 1000, // 15 minutes
    max: 1000, // Increased for development to 1000 requests per window
    keyGenerator: (req) => {
        return req.user?.uid || req.ip; // CTO suggested IP+UserID combined key
    },
    message: {
        error: {
            message: 'Too many requests, please try again later.',
            code: 'auth/too-many-requests'
        }
    },
    standardHeaders: true,
    legacyHeaders: false,
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
