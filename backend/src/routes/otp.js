import express from 'express';
import crypto from 'crypto';
import admin, { db } from '../config/firebase.js';
import logger from '../utils/logger.js';
import { body, validationResult } from 'express-validator';
import nodemailer from 'nodemailer';

const router = express.Router();

// Initialize Nodemailer (SMTP Driver - Optimized for Amazon SES)
const transporter = nodemailer.createTransport({
    host: process.env.SMTP_HOST || 'email-smtp.us-east-1.amazonaws.com',
    port: parseInt(process.env.SMTP_PORT || '465'),
    secure: process.env.SMTP_SECURE !== 'false',
    auth: {
        user: process.env.SMTP_USER,
        pass: process.env.SMTP_PASS
    }
});

/**
 * @route   POST /api/otp/send
 * @desc    Generate and send OTP to email (Amazon SES)
 * @access  Public
 */
router.post(
    '/send',
    [
        body('email').isEmail().normalizeEmail().withMessage('Valid email is required'),
    ],
    async (req, res) => {
        const errors = validationResult(req);
        if (!errors.isEmpty()) {
            return res.status(400).json({ errors: errors.array() });
        }

        const { email } = req.body;

        try {
            // Generate 6-digit OTP using cryptographically secure random
            const otp = crypto.randomInt(100000, 999999).toString();

            // Store in Firestore with expiration (10 minutes)
            await db.collection('otps').doc(email).set({
                otp,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                expiresAt: admin.firestore.Timestamp.fromDate(new Date(Date.now() + 10 * 60 * 1000))
            });

            // PRODUCTION: Use SMTP (SES/Gmail) if credentials present
            if (process.env.SMTP_PASS || process.env.EMAIL_PASS) {
                const mailOptions = {
                    from: process.env.SMTP_FROM_EMAIL || process.env.EMAIL_USER || 'beskijosphjr@gmail.com',
                    to: email,
                    subject: 'Your Verification Code',
                    text: `Your verification code is: ${otp}. It will expire in 10 minutes.`,
                    html: `
                        <div style="font-family: Arial, sans-serif; padding: 20px; border: 1px solid #eee; border-radius: 10px;">
                            <h2 style="color: #00B87C;">Verification Code</h2>
                            <p>Hello,</p>
                            <p>Your verification code for TestPro is:</p>
                            <div style="font-size: 32px; font-weight: bold; color: #333; margin: 20px 0; letter-spacing: 5px;">
                                ${otp}
                            </div>
                            <p>This code will expire in 10 minutes.</p>
                            <p>If you didn't request this code, please ignore this email.</p>
                        </div>
                    `,
                };
                
                // Final SES Delivery
                transporter.sendMail(mailOptions).catch(err => {
                    logger.error('SES/SMTP Delivery Error', { error: err.message, email, requestId: req.requestId });
                });
                
            } else {
                // DEVELOPMENT: Fallback for local testing if no credentials provided
                logger.warn(`No email provider configured. [DEVELOPMENT MODE] OTP for ${email} is ${otp}`);
                return res.json({ 
                    message: 'OTP generated (check server logs for code)',
                    dev: true 
                });
            }

            logger.info('OTP Delivery Handed to SES/SMTP', { email, requestId: req.requestId });
            return res.json({ message: 'OTP sent successfully' });

        } catch (error) {
            logger.error('OTP Dispatch Error', { error: error.message, email, requestId: req.requestId });
            return res.status(500).json({ error: 'Failed to dispatch OTP' });
        }
    }
);

/**
 * @route   POST /api/otp/verify
 * @desc    Verify OTP for email
 * @access  Public
 */
router.post(
    '/verify',
    [
        body('email').isEmail().normalizeEmail().withMessage('Valid email is required'),
        body('otp').isLength({ min: 6, max: 6 }).withMessage('OTP must be 6 digits'),
    ],
    async (req, res) => {
        const errors = validationResult(req);
        if (!errors.isEmpty()) {
            return res.status(400).json({ errors: errors.array() });
        }

        const { email, otp } = req.body;

        try {
            const otpDoc = await db.collection('otps').doc(email).get();

            if (!otpDoc.exists) {
                return res.status(404).json({ error: 'No OTP found for this email' });
            }

            const data = otpDoc.data();
            const now = admin.firestore.Timestamp.now();

            if (data.expiresAt.toMillis() < now.toMillis()) {
                await db.collection('otps').doc(email).delete();
                return res.status(400).json({ error: 'OTP has expired' });
            }

            if (data.otp !== otp) {
                return res.status(400).json({ error: 'Invalid OTP' });
            }

            // Success - delete OTP
            await db.collection('otps').doc(email).delete();

            logger.info('OTP Verified', { email, requestId: req.requestId });
            return res.json({ message: 'OTP verified successfully' });

        } catch (error) {
            logger.error('OTP Verify Error', { error: error.message, email, requestId: req.requestId });
            return res.status(500).json({ error: 'Verification failed' });
        }
    }
);

export default router;
