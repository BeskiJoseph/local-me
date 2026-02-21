import express from 'express';
import Joi from 'joi';
import { db } from '../config/firebase.js';
import authenticate from '../middleware/auth.js';
import AuditService from '../services/auditService.js';
import logger from '../utils/logger.js';

const router = express.Router();

const profileSchema = Joi.object({
    username: Joi.string().min(3).max(30),
    firstName: Joi.string().max(50),
    lastName: Joi.string().max(50),
    about: Joi.string().max(500),
    profileImageUrl: Joi.string().uri(),
    location: Joi.string().max(100),
    fcmToken: Joi.string().optional().allow(null, ''),
    // Sensitive fields - usually managed by Admin but included for demonstrating audit logging
    role: Joi.string().valid('user', 'creator', 'admin', 'moderator'),
}).min(1);

/**
 * @route   PATCH /api/profiles/me
 * @desc    Update current user profile
 */
router.patch('/me', authenticate, async (req, res, next) => {
    try {
        const { error, value } = profileSchema.validate(req.body);
        if (error) {
            const err = new Error(error.details[0].message);
            err.status = 400;
            err.code = 'profile/invalid-input';
            return next(err);
        }

        const { uid, email } = req.user;
        const userRef = db.collection('users').doc(uid);
        const snapshot = await userRef.get();
        const exists = snapshot.exists;
        const currentData = exists ? snapshot.data() : null;

        // Security: Prevent unauthorized role changes
        if (value.role && value.role !== currentData?.role) {
            if (req.user.role !== 'admin') {
                const err = new Error('Unauthorized: Only admins can change user roles');
                err.status = 403;
                err.code = 'profile/unauthorized-role-change';
                return next(err);
            }
            await AuditService.logAction({
                userId: uid,
                action: 'ROLE_CHANGE',
                metadata: { from: currentData?.role, to: value.role },
                req
            });
        }

        const updateData = {
            ...value,
            email: email,
            updatedAt: new Date(),
        };

        if (!exists) {
            updateData.createdAt = new Date();
            updateData.role = 'user';
            updateData.status = 'active';
        }

        await userRef.set(updateData, { merge: true });

        logger.info({ userId: uid, isNew: !exists }, 'Profile upserted successfully');
        return res.json({
            success: true,
            data: { message: exists ? 'Profile updated' : 'Profile created' },
            error: null
        });

    } catch (err) {
        next(err);
    }
});

/**
 * @route   GET /api/profiles/check-username
 * @desc    Check if a username is available (Public for Signup)
 */
router.get('/check-username', async (req, res, next) => {
    try {
        const { username } = req.query;
        if (!username) return res.status(400).json({ error: 'Username query param required' });

        const snapshot = await db.collection('users')
            .where('username', '==', username.trim().toLowerCase())
            .limit(1)
            .get();

        return res.json({
            success: true,
            data: { available: snapshot.empty },
            error: null
        });
    } catch (err) {
        next(err);
    }
});

/**
 * @route   GET /api/profiles/:uid
 * @desc    Get user profile by UID
 */
router.get('/:uid', authenticate, async (req, res, next) => {
    try {
        const userDoc = await db.collection('users').doc(req.params.uid).get();
        if (!userDoc.exists) {
            const err = new Error('User not found');
            err.status = 404;
            err.code = 'profile/not-found';
            return next(err);
        }

        const data = userDoc.data();
        // Remove sensitive fields for public view
        const { email, role, ...publicData } = data;

        return res.json({
            success: true,
            data: {
                uid: userDoc.id,
                ...publicData,
                // Only show email to owner or admin
                ...((req.user.uid === req.params.uid || req.user.role === 'admin') ? { email, role } : {})
            },
            error: null
        });
    } catch (err) {
        next(err);
    }
});

export default router;
