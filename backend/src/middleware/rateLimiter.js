import rateLimit from 'express-rate-limit';
import slowDown from 'express-slow-down';
import { logSecurityEvent } from '../utils/logger.js';

// In-memory store for user-specific rate limiting
const userRateLimits = new Map();

// Helper to check user-specific rate limit
export const checkUserRateLimit = (userId, action, maxAttempts = 5, windowMs = 15 * 60 * 1000) => {
    const key = `${userId}:${action}`;
    const now = Date.now();
    const userLimit = userRateLimits.get(key);
    
    if (!userLimit || now > userLimit.resetTime) {
        userRateLimits.set(key, { count: 1, resetTime: now + windowMs });
        return { allowed: true, remaining: maxAttempts - 1 };
    }
    
    if (userLimit.count >= maxAttempts) {
        return { allowed: false, retryAfter: Math.ceil((userLimit.resetTime - now) / 1000) };
    }
    
    userLimit.count++;
    return { allowed: true, remaining: maxAttempts - userLimit.count };
};

// General API rate limiter - reduce for production
const isProduction = process.env.NODE_ENV === 'production';
export const apiLimiter = rateLimit({
    windowMs: 15 * 60 * 1000, // 15 minutes
    max: isProduction ? 200 : 1000, // Stricter in production
    message: 'Too many requests from this IP, please try again later.',
    standardHeaders: true,
    legacyHeaders: false,
    handler: (req, res) => {
        logSecurityEvent('RATE_LIMIT_EXCEEDED', {
            ip: req.ip,
            path: req.path,
            limit: 'api',
        });
        res.status(429).json({
            error: 'Too many requests, please try again later.',
        });
    },
});

// Strict rate limiter for authentication endpoints
export const authLimiter = rateLimit({
    windowMs: 15 * 60 * 1000, // 15 minutes
    max: 5, // Limit each IP to 5 requests per windowMs
    skipSuccessfulRequests: true, // Don't count successful requests
    message: 'Too many authentication attempts, please try again later.',
    standardHeaders: true,
    legacyHeaders: false,
    handler: (req, res) => {
        logSecurityEvent('AUTH_RATE_LIMIT_EXCEEDED', {
            ip: req.ip,
            path: req.path,
        });
        res.status(429).json({
            error: 'Too many authentication attempts, please try again in 15 minutes.',
        });
    },
});

// Upload rate limiter (already exists, enhanced)
export const uploadLimiter = rateLimit({
    windowMs: 15 * 60 * 1000,
    max: 20,
    message: 'Too many upload requests, please try again later.',
    standardHeaders: true,
    legacyHeaders: false,
    handler: (req, res) => {
        logSecurityEvent('UPLOAD_RATE_LIMIT_EXCEEDED', {
            ip: req.ip,
            userId: req.user?.uid,
        });
        res.status(429).json({
            error: 'Too many upload requests, please try again later.',
        });
    },
});

// Speed limiter - gradually slow down repeated requests
export const speedLimiter = slowDown({
    windowMs: 15 * 60 * 1000, // 15 minutes
    delayAfter: 50, // Allow 50 requests per 15 minutes at full speed
    delayMs: () => 500, // Add 500ms delay per request after delayAfter
    maxDelayMs: 20000, // Maximum delay of 20 seconds
});

// Health check rate limiter (more permissive)
export const healthCheckLimiter = rateLimit({
    windowMs: 1 * 60 * 1000, // 1 minute
    max: 60, // 60 requests per minute
    standardHeaders: true,
    legacyHeaders: false,
});
