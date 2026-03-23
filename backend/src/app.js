import express from 'express';
import { securityHeaders, corsOptions, requestTimeout } from './middleware/security.js';
import httpLogger from './middleware/httpLogger.js';
import errorHandler from './middleware/errorHandler.js';
import logger from './utils/logger.js';

const app = express();

// Production error tracking
if (process.env.NODE_ENV === 'production') {
    logger.info('🔒 Production mode: Security features enabled');
}

// 1. Trust proxy for correct IP detection
app.set('trust proxy', 1);

// 2. Security & Logging Base
app.use(securityHeaders);
app.use(corsOptions);
app.use(httpLogger);

// 3. Request Shaping
app.use(express.json({ limit: '100mb' }));
app.use(express.urlencoded({ limit: '100mb', extended: true }));
app.use(requestTimeout);

// 4. Health Check (Public - No Limiter or Health-specific Limiter)
import { progressiveLimiter } from './middleware/progressiveLimiter.js';
import { db } from './config/firebase.js';
app.get('/health', progressiveLimiter('health'), async (_, res) => {
    try {
        // Quick Firestore connectivity check
        await db.collection('_health').doc('ping').set({ ts: Date.now() }, { merge: true });
        res.json({
            status: 'ok',
            timestamp: new Date().toISOString(),
            uptime: process.uptime(),
            db: 'connected',
        });
    } catch (err) {
        res.status(503).json({
            status: 'degraded',
            timestamp: new Date().toISOString(),
            uptime: process.uptime(),
            db: 'unreachable',
        });
    }
});

// 5. Public Routes (IP-based limiting)
import otpRoutes from './routes/otp.js';
import proxyRoutes from './routes/proxy.js';
import profileRoutes from './routes/profiles.js';
import authRoutes from './routes/auth.js';

app.use('/api/otp', progressiveLimiter('otp'), otpRoutes);
app.use('/api/proxy', progressiveLimiter('api'), proxyRoutes);
app.use('/api/auth', progressiveLimiter('auth'), authRoutes);

// Public sub-route of profiles (must be mounted before protected profiles)
app.use('/api/profiles', progressiveLimiter('api'), profileRoutes);

// 6. Protected Routes (User-based limiting)
// By mounting authenticate before progressiveLimiter, the limiter can use req.user.uid
import authenticate from './middleware/auth.js';
import uploadRoutes from './routes/upload.js';
import interactionRoutes from './routes/interactions.js';
import postRoutes from './routes/posts.js';
import searchRoutes from './routes/search.js';
import notificationRoutes from './routes/notifications.js';
import chatRoutes from './routes/chats.js';

const protectedMiddleware = [authenticate, progressiveLimiter('api', true)];

app.use('/api/upload', protectedMiddleware, uploadRoutes);
app.use('/api/interactions', protectedMiddleware, interactionRoutes);
app.use('/api/posts', protectedMiddleware, postRoutes);
app.use('/api/profiles', protectedMiddleware, profileRoutes);
app.use('/api/search', protectedMiddleware, searchRoutes);
app.use('/api/notifications', protectedMiddleware, notificationRoutes);
app.use('/api/chats', protectedMiddleware, chatRoutes);

// 7. 404 Handler
app.use((req, res) => {
    res.status(404).json({
        success: false,
        data: null,
        error: {
            message: 'Route not found',
            code: 'infra/route-not-found'
        }
    });
});

// 8. Centralized Error Handler (Last)
app.use(errorHandler);

export default app;
