import pino from 'pino';

const logger = pino({
    level: process.env.LOG_LEVEL || 'info',
    transport: process.env.NODE_ENV !== 'production' ? {
        target: 'pino-pretty',
        options: {
            colorize: true,
            ignore: 'pid,hostname',
            translateTime: 'HH:MM:ss Z',
        },
    } : undefined,
});

/**
 * Log a security-related event
 * @param {string} event - The name of the event (e.g., 'RATE_LIMIT_EXCEEDED')
 * @param {Object} metadata - Additional data related to the event
 */
export const logSecurityEvent = (event, metadata = {}) => {
    logger.warn({
        securityEvent: event,
        ...metadata,
        timestamp: new Date().toISOString(),
    }, `Security Event: ${event}`);
};

export default logger;
