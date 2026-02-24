import express from 'express';
import multer from 'multer';
import { S3Client, PutObjectCommand } from '@aws-sdk/client-s3';
import crypto from 'crypto';
import fs from 'fs/promises';
import path from 'path';
import os from 'os';
import authenticate from '../middleware/auth.js';
import { progressiveLimiter } from '../middleware/progressiveLimiter.js';
import {
    validateFileUpload,
    validateFileMagicBytes,
    validateTokenExpiration,
    handleValidationErrors,
} from '../middleware/sanitize.js';
import { checkDailyUploadLimit, incrementDailyUploadCount } from '../middleware/uploadLimits.js';
import { getVideoMetadata, processVideo } from '../utils/videoProcessor.js';
import logger from '../utils/logger.js';

const router = express.Router();

// ============================================
// MULTER (MEMORY ONLY)
// ============================================
const upload = multer({
    storage: multer.memoryStorage(),
    limits: {
        fileSize: 200 * 1024 * 1024, // 200MB (increased for videos)
        files: 1,
    },
});

// ============================================
// R2 CLIENT
// ============================================
const r2Client = new S3Client({
    region: 'auto',
    endpoint: `https://${process.env.R2_ACCOUNT_ID}.r2.cloudflarestorage.com`,
    credentials: {
        accessKeyId: process.env.R2_ACCESS_KEY_ID,
        secretAccessKey: process.env.R2_SECRET_ACCESS_KEY,
    },
});

// ============================================
// HELPER FUNCTIONS
// ============================================
function getExtension(mime) {
    const map = {
        'image/jpeg': 'jpg',
        'image/png': 'png',
        'image/webp': 'webp',
        'image/gif': 'gif',
        'video/mp4': 'mp4',
        'video/webm': 'webm',
        'video/quicktime': 'mov',
    };
    return map[mime] || null;
}

async function uploadToR2(file, key, bufferOverride = null) {
    const body = bufferOverride || file.buffer;
    const size = bufferOverride ? bufferOverride.length : file.size;

    await r2Client.send(
        new PutObjectCommand({
            Bucket: process.env.R2_BUCKET_NAME,
            Key: key,
            Body: body,
            ContentType: file.mimetype,
            ContentLength: size,
            CacheControl: 'public, max-age=31536000, immutable',
        })
    );
}

// ============================================
// ROUTES
// ============================================

// Upload profile image
router.post(
    '/profile',
    progressiveLimiter('upload', true),
    authenticate,
    validateTokenExpiration,
    upload.single('file'),
    validateFileUpload,
    validateFileMagicBytes,
    async (req, res) => {
        try {
            const ext = getExtension(req.validatedFileType.mime);
            if (!ext) {
                return res.status(400).json({ error: 'Unsupported image format' });
            }

            const key = `profile-images/${req.user.uid}/${crypto.randomUUID()}.${ext}`;
            await uploadToR2(req.file, key);

            logger.info('Profile image uploaded', {
                userId: req.user.uid,
                key,
                size: req.file.size,
            });

            return res.json({
                key,
                url: `${process.env.R2_PUBLIC_BASE_URL}/${key}`,
            });
        } catch (err) {
            logger.error('Profile upload error', {
                requestId: req.requestId,
                userId: req.user.uid,
                error: err.message,
            });
            return res.status(500).json({
                error: 'Upload failed',
                requestId: req.requestId,
            });
        }
    }
);

// Upload post media
router.post(
    '/post',
    progressiveLimiter('upload', true),
    authenticate,
    (req, res, next) => {
        if (process.env.NODE_ENV !== 'production') {
            logger.debug({ auth: req.headers.authorization?.substring(0, 20) }, 'Post upload auth check');
        }
        next();
    },
    validateTokenExpiration,
    checkDailyUploadLimit,
    upload.single('file'),
    validateFileUpload,
    validateFileMagicBytes,
    async (req, res) => {
        let tempInputPath = null;
        let tempOutputPath = null;

        try {
            const { mediaType, postId = 'uncategorized' } = req.body;

            const ext = getExtension(req.validatedFileType.mime);
            if (!ext) {
                return res.status(400).json({ error: 'Unsupported media format' });
            }

            const safePostId =
                postId.replace(/[^a-zA-Z0-9-_]/g, '').slice(0, 100) || 'uncategorized';
            const folder = mediaType === 'video' ? 'videos' : 'images';

            let finalBuffer = req.file.buffer;
            let finalKey = `posts/${req.user.uid}/${safePostId}/${folder}/${crypto.randomUUID()}.${ext}`;

            // Handle video processing
            if (mediaType === 'video') {
                const tempId = crypto.randomUUID();
                tempInputPath = path.join(os.tmpdir(), `input_${tempId}.${ext}`);
                tempOutputPath = path.join(os.tmpdir(), `output_${tempId}.mp4`); // Always output mp4 for consistency

                // Write buffer to temp file
                await fs.writeFile(tempInputPath, req.file.buffer);

                // Check duration
                const metadata = await getVideoMetadata(tempInputPath);
                const duration = metadata.format.duration;

                logger.info('Video metadata retrieved', { duration, userId: req.user.uid });

                // Process (Trim/Compress) if > 5 mins (300s) or always compress to save size
                // We always process to ensure consistent format (mp4) and compression
                await processVideo(tempInputPath, tempOutputPath, 300);

                // Read processed video
                finalBuffer = await fs.readFile(tempOutputPath);
                // Update key extension if changed to mp4
                finalKey = finalKey.replace(new RegExp(`\\.${ext}$`), '.mp4');
            }

            await uploadToR2(req.file, finalKey, finalBuffer);

            // Increment daily upload count upon success
            await incrementDailyUploadCount(req.user.uid);

            logger.info('Post media uploaded', {
                userId: req.user.uid,
                postId: safePostId,
                mediaType,
                key: finalKey,
                size: finalBuffer.length,
            });

            return res.json({
                key: finalKey,
                url: `${process.env.R2_PUBLIC_BASE_URL}/${finalKey}`,
            });
        } catch (err) {
            logger.error('Post upload error', {
                requestId: req.requestId,
                userId: req.user.uid,
                error: err.message,
                stack: err.stack
            });
            return res.status(500).json({
                error: 'Upload failed',
                requestId: req.requestId,
            });
        } finally {
            // Cleanup temp files
            try {
                if (tempInputPath) await fs.unlink(tempInputPath).catch(() => { });
                if (tempOutputPath) await fs.unlink(tempOutputPath).catch(() => { });
            } catch (cleanupErr) {
                logger.error('Cleanup error', { cleanupErr: cleanupErr.message });
            }
        }
    }
);

export default router;
