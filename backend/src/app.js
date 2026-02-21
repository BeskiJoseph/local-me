import express from 'express';
import { securityHeaders, corsOptions, globalLimiter, requestTimeout } from './middleware/security.js';
import httpLogger from './middleware/httpLogger.js';
import errorHandler from './middleware/errorHandler.js';

const app = express();

// 1. Trust proxy for correct IP detection
app.set('trust proxy', 1);

// 2. Security & Logging Base
app.use(securityHeaders);
app.use(corsOptions);
app.use(httpLogger);

// 3. Request Shaping
app.use(express.json({ limit: '1mb' }));
app.use(express.urlencoded({ limit: '1mb', extended: true }));
app.use(requestTimeout);

// 4. Health Check (Public - No Limiter or Health-specific Limiter)
import { healthCheckLimiter } from './middleware/rateLimiter.js';
app.get('/health', healthCheckLimiter, (_, res) => {
    res.json({
        status: 'ok',
        timestamp: new Date().toISOString(),
        uptime: process.uptime(),
    });
});

// 5. Public Routes (IP-based limiting)
import otpRoutes from './routes/otp.js';
import proxyRoutes from './routes/proxy.js';
import profileRoutes from './routes/profiles.js';

app.use('/api/otp', globalLimiter, otpRoutes);
app.use('/api/proxy', globalLimiter, proxyRoutes);

// Public sub-route of profiles (must be mounted before protected profiles)
app.get('/api/profiles/check-username', globalLimiter, profileRoutes);

// 6. Protected Routes (User-based limiting)
// By mounting authenticate before globalLimiter, the limiter can use req.user.uid
import authenticate from './middleware/auth.js';
import uploadRoutes from './routes/upload.js';
import interactionRoutes from './routes/interactions.js';
import postRoutes from './routes/posts.js';
import searchRoutes from './routes/search.js';
import notificationRoutes from './routes/notifications.js';

const protectedMiddleware = [authenticate, globalLimiter];

app.use('/api/upload', protectedMiddleware, uploadRoutes);
app.use('/api/interactions', protectedMiddleware, interactionRoutes);
app.use('/api/posts', protectedMiddleware, postRoutes);
app.use('/api/profiles', protectedMiddleware, profileRoutes);
app.use('/api/search', protectedMiddleware, searchRoutes);
app.use('/api/notifications', protectedMiddleware, notificationRoutes);

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
