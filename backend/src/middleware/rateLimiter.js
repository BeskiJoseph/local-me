import rateLimit from 'express-rate-limit';
import slowDown from 'express-slow-down';
import { logSecurityEvent } from '../utils/logger.js';
import { globalLimiterStore } from '../services/MemoryLimiterService.js';

// Helper to check user-specific rate limit using unified MemoryLimiterService
export const checkUserRateLimit = (userId, action, maxAttempts = 5, windowMs = 15 * 60 * 1000) => {
    const key = `user_limit:${userId}:${action}`;
    const now = Date.now();
    
    // globalLimiterStore.get returns the data payload automatically tracking TTL
    let userLimit = globalLimiterStore.get(key);
    
    if (!userLimit) {
        userLimit = { count: 1, resetTime: now + windowMs };
        globalLimiterStore.set(key, userLimit, windowMs);
        return { allowed: true, remaining: maxAttempts - 1 };
    }
    
    if (userLimit.count >= maxAttempts) {
        return { allowed: false, retryAfter: Math.ceil((userLimit.resetTime - now) / 1000) };
    }
    
    userLimit.count++;
    globalLimiterStore.set(key, userLimit, userLimit.resetTime - now);
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
