import winston from 'winston';

const { combine, timestamp, printf, colorize, errors } = winston.format;

// Custom format for logs
const logFormat = printf(({ level, message, timestamp, stack, ...metadata }) => {
    let msg = `${timestamp} [${level}]: ${message}`;

    // Add stack trace for errors
    if (stack) {
        msg += `\n${stack}`;
    }

    // Add metadata if present
    if (Object.keys(metadata).length > 0) {
        msg += `\n${JSON.stringify(metadata, null, 2)}`;
    }

    return msg;
});

// Filter sensitive data from logs
const filterSensitiveData = winston.format((info) => {
    const sensitiveFields = ['password', 'token', 'apiKey', 'secret', 'authorization'];

    const filter = (obj) => {
        if (typeof obj !== 'object' || obj === null) return obj;

        const filtered = { ...obj };
        for (const key in filtered) {
            if (sensitiveFields.some(field => key.toLowerCase().includes(field))) {
                filtered[key] = '***REDACTED***';
            } else if (typeof filtered[key] === 'object') {
                filtered[key] = filter(filtered[key]);
            }
        }
        return filtered;
    };

    return filter(info);
});

// Create logger instance
const logger = winston.createLogger({
    level: process.env.LOG_LEVEL || 'info',
    format: combine(
        errors({ stack: true }),
        timestamp({ format: 'YYYY-MM-DD HH:mm:ss' }),
        filterSensitiveData(),
        logFormat
    ),
    transports: [
        // Console transport
        new winston.transports.Console({
            format: combine(
                colorize(),
                logFormat
            ),
        }),
        // File transport for errors
        new winston.transports.File({
            filename: 'logs/error.log',
            level: 'error',
            maxsize: 5242880, // 5MB
            maxFiles: 5,
        }),
        // File transport for all logs
        new winston.transports.File({
            filename: 'logs/combined.log',
            maxsize: 5242880, // 5MB
            maxFiles: 5,
        }),
    ],
});

// Security event logger
export const logSecurityEvent = (event, details = {}) => {
    logger.warn('SECURITY_EVENT', {
        event,
        ...details,
        timestamp: new Date().toISOString(),
    });
};

// Request logger middleware
export const requestLogger = (req, res, next) => {
    const start = Date.now();

    res.on('finish', () => {
        const duration = Date.now() - start;
        const logData = {
            method: req.method,
            url: req.url,
            status: res.statusCode,
            duration: `${duration}ms`,
            ip: req.ip,
            userAgent: req.get('user-agent'),
            requestId: req.requestId,
        };

        if (res.statusCode >= 400) {
            logger.error('Request failed', logData);
        } else {
            logger.info('Request completed', logData);
        }
    });

    next();
};

export default logger;
