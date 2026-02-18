import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import crypto from 'crypto';
import config from './config/index.js';
import logger, { requestLogger } from './utils/logger.js';
import { apiLimiter, healthCheckLimiter, speedLimiter } from './middleware/rateLimiter.js';
import { sanitizeRequest } from './middleware/security.js';
import uploadRoutes from './routes/upload.js';
import otpRoutes from './routes/otp.js';
import interactionRoutes from './routes/interactions.js';

// ============================================
// APP INIT
// ============================================
const app = express();

// Trust proxy for correct IP detection behind reverse proxies
app.set('trust proxy', 1);

// ============================================
// SECURITY MIDDLEWARE
// ============================================

// Helmet - Security headers
app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      styleSrc: ["'self'", "'unsafe-inline'"],
      scriptSrc: ["'self'"],
      imgSrc: ["'self'", 'data:', 'https:'],
    },
  },
  hsts: {
    maxAge: 31536000, // 1 year
    includeSubDomains: true,
    preload: true,
  },
  frameguard: { action: 'deny' },
  noSniff: true,
  xssFilter: true,
  referrerPolicy: { policy: 'no-referrer' },
}));

// Request ID for tracking
app.use((req, _, next) => {
  req.requestId = crypto.randomUUID();
  next();
});

// Request logging
app.use(requestLogger);

// CORS
app.use(
  cors({
    origin: config.nodeEnv === 'production'
      ? config.corsOrigin.split(',')
      : '*',
    credentials: true,
  })
);

// Body parsing with size limits
app.use(express.json({ limit: '1mb' }));
app.use(express.urlencoded({ limit: '1mb', extended: true }));

// Input sanitization (XSS, NoSQL injection, HPP)
app.use(sanitizeRequest);

// Speed limiter - gradually slow down repeated requests
app.use(speedLimiter);

// General API rate limiting
app.use('/api', apiLimiter);

// ============================================
// ROUTES
// ============================================

// Health check
app.get('/health', healthCheckLimiter, (_, res) => {
  res.json({
    status: 'ok',
    time: new Date().toISOString(),
    uptime: process.uptime(),
  });
});

// Proxy route to bypass CORS for media
app.get('/api/proxy', async (req, res) => {
  const targetUrl = req.query.url;

  if (!targetUrl) {
    return res.status(400).json({ error: 'Missing url parameter' });
  }

  try {
    // Check if target is a known media source (security)
    if (!targetUrl.includes('workers.dev') && !targetUrl.includes('r2')) {
      // logger.warn('Proxy access to non-verified source', { url: targetUrl });
      // return res.status(403).json({ error: 'Unauthorized target URL' });
    }

    const response = await fetch(targetUrl);

    if (!response.ok) {
      throw new Error(`Failed to fetch: ${response.statusText}`);
    }

    // Forward headers
    const contentType = response.headers.get('content-type');
    if (contentType) res.setHeader('Content-Type', contentType);

    // Cache control
    res.setHeader('Cache-Control', 'public, max-age=86400');
    res.set('Access-Control-Allow-Origin', '*');

    // Stream the response
    const arrayBuffer = await response.arrayBuffer();
    res.send(Buffer.from(arrayBuffer));
  } catch (error) {
    logger.error('Proxy Error', {
      url: targetUrl,
      error: error.message,
      requestId: req.requestId
    });
    res.status(500).json({ error: 'Proxy request failed' });
  }
});

// Upload routes
app.use('/api/upload', uploadRoutes);

// OTP routes
app.use('/api/otp', otpRoutes);

// Interaction routes
app.use('/api/interactions', interactionRoutes);

// ============================================
// ERROR HANDLING
// ============================================

// 404 handler
app.use((req, res) => {
  logger.warn('Route not found', {
    method: req.method,
    path: req.path,
    ip: req.ip,
  });
  res.status(404).json({ error: 'Route not found' });
});

// Global error handler
app.use((err, req, res, next) => {
  logger.error('Unhandled error', {
    requestId: req.requestId,
    error: err.message,
    stack: err.stack,
    path: req.path,
    method: req.method,
  });

  // Don't leak error details in production
  const errorMessage = config.nodeEnv === 'production'
    ? 'Internal server error'
    : err.message;

  res.status(err.status || 500).json({
    error: errorMessage,
    requestId: req.requestId,
  });
});

// ============================================
// GRACEFUL SHUTDOWN
// ============================================
const gracefulShutdown = (signal) => {
  logger.info(`${signal} received, shutting down gracefully`);

  server.close(() => {
    logger.info('Server closed');
    process.exit(0);
  });

  // Force shutdown after 30 seconds
  setTimeout(() => {
    logger.error('Forced shutdown after timeout');
    process.exit(1);
  }, 30000);
};

process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
process.on('SIGINT', () => gracefulShutdown('SIGINT'));

// Unhandled rejection handler
process.on('unhandledRejection', (reason, promise) => {
  logger.error('Unhandled Rejection', {
    reason,
    promise,
  });
});

// Uncaught exception handler
process.on('uncaughtException', (error) => {
  logger.error('Uncaught Exception', {
    error: error.message,
    stack: error.stack,
  });
  process.exit(1);
});

// ============================================
// START SERVER
// ============================================
const server = app.listen(config.port, '0.0.0.0', () => {
  logger.info(`🚀 Server running on port ${config.port}`);
  logger.info(`🌐 Environment: ${config.nodeEnv}`);
  logger.info(`🔒 CORS: ${config.corsOrigin}`);
  logger.info(`📦 Media base: ${config.r2.publicBaseUrl}`);
});

export default app;
