import pinoHttp from 'pino-http';
import logger from '../utils/logger.js';

const httpLogger = pinoHttp({
    logger,
    serializers: {
        req: (req) => ({
            method: req.method,
            url: req.url,
            userId: req.raw.user?.uid, // Log userId if available
        }),
    },
    customLogLevel: (res, err) => {
        if (res.statusCode >= 500 || err) return 'error';
        if (res.statusCode >= 400) return 'warn';
        return 'info';
    },
});

export default httpLogger;
