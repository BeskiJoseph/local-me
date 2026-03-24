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
        userId: req.user?.uid,
        statusCode: err.status
    });

    // If headers already sent, don't try to send another response
    if (res.headersSent) {
        return next(err);
    }

    // Handle specific error codes
    let statusCode = err.status || 500;
    let errorCode = err.code || 'INTERNAL_ERROR';
    let errorMessage = err.message || 'Internal Server Error';

    // URL too long (414 Payload URI Too Large)
    // This typically occurs when watchedIds query param exceeds 2000 chars
    if (statusCode === 414 || err.message?.includes('414') || req.originalUrl.length > 2000) {
        statusCode = 414;
        errorCode = 'URL_OVERFLOW';
        errorMessage = 'URL too long (>2000 chars). Switch to POST-based pagination or reduce seenIds count.';
        logger.warn(
            { urlLength: req.originalUrl.length, userId: req.user?.uid },
            '[ErrorHandler] 414 URL overflow detected'
        );
    }

    res.status(statusCode).json({
        success: false,
        data: null,
        error: {
            message: errorMessage,
            code: errorCode,
            ...(isProd ? {} : { stack: err.stack })
        }
    });
};

export default errorHandler;
