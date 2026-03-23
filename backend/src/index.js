import app from './app.js';
import config from './config/env.js';
import logger from './utils/logger.js';
import http from 'http';
import { initSocket } from './services/socketService.js';
import { geoIndex } from './services/geoIndex.js';

const httpServer = http.createServer(app);
const io = initSocket(httpServer);

const server = httpServer.listen(config.port, '0.0.0.0', async () => {
    logger.info(`🚀 Server running on port ${config.port}`);
    logger.info(`🌐 Environment: ${config.nodeEnv}`);

    // Build the in-memory geospatial index for the local feed
    await geoIndex.build();
});

/**
 * Graceful Shutdown and Global Error Handling
 */
const gracefulShutdown = (signal) => {
    logger.info(`${signal} received, shutting down gracefully`);
    server.close(() => {
        logger.info('Server closed');
        process.exit(0);
    });

    setTimeout(() => {
        logger.error('Forced shutdown after timeout');
        process.exit(1);
    }, 30000);
};

process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
process.on('SIGINT', () => gracefulShutdown('SIGINT'));

process.on('unhandledRejection', (reason, promise) => {
    logger.error({ reason, promise }, 'Unhandled Rejection');
});

process.on('uncaughtException', (error) => {
    logger.error({ err: error }, 'Uncaught Exception');
    process.exit(1);
});
