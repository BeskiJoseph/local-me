import { body, validationResult } from 'express-validator';
import mongoSanitize from 'express-mongo-sanitize';
import xss from 'xss-clean';
import hpp from 'hpp';
import logger, { logSecurityEvent } from '../utils/logger.js';

// Sanitize request data
export const sanitizeRequest = [
    mongoSanitize(), // Prevent NoSQL injection
    xss(), // Prevent XSS attacks
    hpp(), // Prevent HTTP parameter pollution
];

// Validation error handler
export const handleValidationErrors = (req, res, next) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
        logSecurityEvent('VALIDATION_FAILED', {
            ip: req.ip,
            path: req.path,
            errors: errors.array(),
        });
        return res.status(400).json({
            error: 'Validation failed',
            details: errors.array(),
        });
    }
    next();
};

// File upload validation rules
export const validateFileUpload = [
    body('mediaType')
        .isIn(['image', 'video', 'document'])
        .withMessage('Media type must be either image, video or document'),
    body('fileExtension')
        .matches(/^(jpg|jpeg|png|webp|gif|mp4|webm|mov|pdf|doc|docx)$/)
        .withMessage('Invalid file extension'),
    handleValidationErrors,
];

// Validate file size and type using magic bytes
export const validateFileMagicBytes = async (req, res, next) => {
    if (!req.file) {
        return res.status(400).json({ error: 'No file uploaded' });
    }

    try {
        const { fileTypeFromBuffer } = await import('file-type');
        const fs = await import('fs/promises');
        // Read first 4100 bytes from disk for magic byte detection
        const fileBuffer = await fs.readFile(req.file.path);
        const fileType = await fileTypeFromBuffer(fileBuffer);

        if (!fileType) {
            logSecurityEvent('INVALID_FILE_TYPE', {
                ip: req.ip,
                userId: req.user?.uid,
                fileName: req.file.originalname,
            });
            return res.status(400).json({
                error: 'Unable to determine file type',
            });
        }

        // Verify MIME type matches
        const allowedTypes = {
            image: ['image/jpeg', 'image/png', 'image/webp', 'image/gif'],
            video: ['video/mp4', 'video/webm', 'video/quicktime'],
            document: [
                'application/pdf',
                'application/msword',
                'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
            ],
        };

        const mediaType = req.body.mediaType;
        const isValid = allowedTypes[mediaType]?.includes(fileType.mime);

        if (!isValid) {
            logSecurityEvent('FILE_TYPE_MISMATCH', {
                ip: req.ip,
                userId: req.user?.uid,
                expectedType: mediaType,
                actualType: fileType.mime,
            });
            return res.status(400).json({
                error: 'File type does not match declared media type',
                expected: mediaType,
                actual: fileType.mime,
            });
        }

        // Attach validated file type to request
        req.validatedFileType = fileType;
        next();
    } catch (error) {
        logSecurityEvent('FILE_VALIDATION_ERROR', {
            ip: req.ip,
            userId: req.user?.uid,
            error: error.message,
        });
        res.status(500).json({
            error: 'File validation failed',
        });
    }
};

// Validate Firebase token expiration
export const validateTokenExpiration = (req, res, next) => {
    if (!req.user) {
        return res.status(401).json({ error: 'Unauthorized' });
    }

    // 1. Custom tokens have built-in JWT expiration (verified in auth middleware)
    if (req.user.auth_type === 'custom') return next();

    // 2. Firebase tokens are valid for 1 hour
    // req.user.auth_time is the original login time
    const authTime = req.user.auth_time || 0;
    if (authTime === 0) return next();

    const tokenAge = Date.now() / 1000 - authTime;
    const maxAge = 30 * 24 * 3600; // 30 days in seconds (Matches Custom Refresh Token lifespan for continuity)

    if (tokenAge > maxAge) {
        logSecurityEvent('EXPIRED_TOKEN_USED', {
            ip: req.ip,
            userId: req.user.uid,
            tokenAge,
            auth_time: req.user.auth_time
        });
        logger.warn({ userId: req.user.uid, tokenAge, auth_time: req.user.auth_time, ip: req.ip }, 'Token expired check failed');
        return res.status(401).json({
            error: 'Token expired, please re-authenticate',
        });
    }

    next();
};

// Request size validator
export const validateRequestSize = (maxSize = 1024 * 1024) => {
    return (req, res, next) => {
        const contentLength = parseInt(req.get('content-length') || '0');

        if (contentLength > maxSize) {
            logSecurityEvent('REQUEST_TOO_LARGE', {
                ip: req.ip,
                size: contentLength,
                maxSize,
            });
            return res.status(413).json({
                error: 'Request entity too large',
                maxSize: `${maxSize / 1024 / 1024}MB`,
            });
        }

        next();
    };
};
