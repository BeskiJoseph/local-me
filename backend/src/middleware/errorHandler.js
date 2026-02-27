import logger from '../utils/logger.js';

const errorHandler = (err, req, res, next) => {
    const isProd = process.env.NODE_ENV === 'production';

    // Log the full error for internal tracking
    logger.error({
        msg: err.message,
        stack: err.stack,
        path: req.path,
        method: req.method,
        body: isProd ? '[REDACTED]' : req.body,
        userId: req.user?.uid
    });

    // If headers already sent, don't try to send another response
    if (res.headersSent) {
        return next(err);
    }

    const statusCode = err.status || 500;

    res.status(statusCode).json({
        success: false,
        data: null,
        error: {
            message: err.message || 'Internal Server Error',
            code: err.code || 'INTERNAL_ERROR',
            ...(isProd ? {} : { stack: err.stack })
        }
    });
};

export default errorHandler;
