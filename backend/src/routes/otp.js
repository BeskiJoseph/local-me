import express from 'express';
import sgMail from '@sendgrid/mail';
import crypto from 'crypto';
import admin, { db } from '../config/firebase.js';
import logger from '../utils/logger.js';
import { body, validationResult } from 'express-validator';

const router = express.Router();

// Initialize SendGrid
if (process.env.SENDGRID_API_KEY) {
    sgMail.setApiKey(process.env.SENDGRID_API_KEY);
}

/**
 * @route   POST /api/otp/send
 * @desc    Generate and send OTP to email
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
            // Generate 6-digit OTP
            const otp = Math.floor(100000 + Math.random() * 900000).toString();

            // Store in Firestore with expiration (10 minutes)
            await db.collection('otps').doc(email).set({
                otp,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                expiresAt: admin.firestore.Timestamp.fromDate(new Date(Date.now() + 10 * 60 * 1000))
            });

            // Send via SendGrid
            if (!process.env.SENDGRID_API_KEY) {
                logger.warn('SendGrid API key missing, OTP not sent', { email, otp });
                return res.status(500).json({ error: 'Email service configuration missing' });
            }

            const msg = {
                to: email,
                from: process.env.SENDGRID_FROM_EMAIL,
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

            await sgMail.send(msg);

            logger.info('OTP Sent', { email, requestId: req.requestId });
            return res.json({ message: 'OTP sent successfully' });

        } catch (error) {
            logger.error('OTP Send Error', { error: error.message, email, requestId: req.requestId });
            return res.status(500).json({ error: 'Failed to send OTP' });
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
