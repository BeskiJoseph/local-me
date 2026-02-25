import express from 'express';
import Joi from 'joi';
import { db } from '../config/firebase.js';
import authenticate, { clearUserCache } from '../middleware/auth.js';
import AuditService from '../services/auditService.js';
import logger from '../utils/logger.js';
import { cleanPayload } from '../utils/sanitizer.js';
import { buildDisplayName, normalizeText } from '../utils/userDisplayName.js';

const router = express.Router();

const profileSchema = Joi.object({
    displayName: Joi.string().max(100).allow('', null).optional(),
    username: Joi.string().min(3).max(30).allow('', null),
    firstName: Joi.string().max(50).allow('', null),
    lastName: Joi.string().max(50).allow('', null),
    about: Joi.string().max(500).allow('', null),
    profileImageUrl: Joi.string().uri().allow('', null),
    location: Joi.string().max(100).allow('', null),
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
        const ALLOWED_PROFILE_FIELDS = [
            'displayName', 'username', 'firstName', 'lastName', 'about',
            'profileImageUrl', 'location', 'fcmToken', 'role'
        ];
        const cleanBody = cleanPayload(req.body, ALLOWED_PROFILE_FIELDS);
        logger.info({
            uid: req.user?.uid,
            incomingBody: req.body,
            afterClean: cleanBody
        }, '[PROFILE_DEBUG] Lifecycle Tracking Started');

        const { error, value } = profileSchema.validate(cleanBody);

        logger.info({ validatedValue: value }, '[PROFILE_DEBUG] After Validation');
        if (error) {
            logger.warn({ validationError: error.details[0].message }, '[PROFILE_DEBUG] Joi Validation ERROR');
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

        const normalizeOptional = (input) => {
            if (input === null || input === undefined) return undefined;
            const normalized = normalizeText(input);
            return normalized || undefined;
        };

        const normalizedValue = { ...value };
        const stringFields = ['displayName', 'username', 'firstName', 'lastName', 'about', 'profileImageUrl', 'location', 'fcmToken'];
        for (const field of stringFields) {
            if (Object.prototype.hasOwnProperty.call(normalizedValue, field)) {
                normalizedValue[field] = normalizeOptional(normalizedValue[field]);
            }
        }

        if (
            Object.prototype.hasOwnProperty.call(value, 'username') &&
            value.username !== null &&
            !normalizedValue.username
        ) {
            const err = new Error('Username cannot be empty');
            err.status = 400;
            err.code = 'profile/invalid-username';
            return next(err);
        }

        if (normalizedValue.username && normalizedValue.username !== currentData?.username) {
            const usernameSnapshot = await db.collection('users')
                .where('username', '==', normalizedValue.username.toLowerCase())
                .limit(1)
                .get();
            const usernameTakenByOther = !usernameSnapshot.empty &&
                usernameSnapshot.docs.some(doc => doc.id !== uid);
            if (usernameTakenByOther) {
                const err = new Error('Username is already taken');
                err.status = 409;
                err.code = 'profile/username-taken';
                return next(err);
            }
        }

        // Security: Prevent unauthorized role changes
        if (normalizedValue.role && normalizedValue.role !== currentData?.role) {
            if (req.user.role !== 'admin') {
                const err = new Error('Unauthorized: Only admins can change user roles');
                err.status = 403;
                err.code = 'profile/unauthorized-role-change';
                return next(err);
            }
            await AuditService.logAction({
                userId: uid,
                action: 'ROLE_CHANGE',
                metadata: { from: currentData?.role, to: normalizedValue.role },
                req
            });
        }

        const effectiveUsername = normalizedValue.username || currentData?.username;
        const effectiveDisplayName = normalizedValue.displayName || buildDisplayName({
            displayName: currentData?.displayName,
            username: effectiveUsername,
            firstName: normalizedValue.firstName || currentData?.firstName,
            lastName: normalizedValue.lastName || currentData?.lastName,
            email: email || currentData?.email,
            fallback: 'User'
        });

        const updateData = {
            ...normalizedValue,
            ...(effectiveUsername ? { username: effectiveUsername.toLowerCase() } : {}),
            ...(effectiveDisplayName ? { displayName: effectiveDisplayName } : {}),
            email: email,
            updatedAt: new Date(),
        };

        if (!exists) {
            updateData.createdAt = new Date();
            updateData.role = 'user';
            updateData.status = 'active';
        }

        await userRef.set(updateData, { merge: true });

        // Architecturally required invalidate cache
        clearUserCache(uid);

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
        const userRef = db.collection('users').doc(req.params.uid);
        let userDoc = await userRef.get();

        // Self-heal for authenticated owner: create minimal profile on first read.
        // Prevents "User not found" race right after login for legacy/incomplete accounts.
        if (!userDoc.exists && req.user.uid === req.params.uid) {
            const bootstrapData = {
                email: req.user.email || '',
                displayName: buildDisplayName({
                    displayName: req.user.displayName,
                    email: req.user.email,
                    fallback: 'User'
                }),
                username: (() => {
                    const base = (req.user.email || 'user')
                        .split('@')[0]
                        .toLowerCase()
                        .replace(/[^a-z0-9_]/g, '')
                        .slice(0, 20) || 'user';
                    return `${base}_${req.user.uid.slice(-6)}`;
                })(),
                profileImageUrl: req.user.photoURL || null,
                role: req.user.role || 'user',
                status: req.user.status || 'active',
                createdAt: new Date(),
                updatedAt: new Date(),
            };
            await userRef.set(bootstrapData, { merge: true });
            clearUserCache(req.user.uid);
            userDoc = await userRef.get();
        }

        if (!userDoc.exists) {
            const err = new Error('User not found');
            err.status = 404;
            err.code = 'profile/not-found';
            return next(err);
        }

        const data = userDoc.data();
        // Remove sensitive fields for public view
        const { email, role, ...publicData } = data;
        const resolvedDisplayName = buildDisplayName({
            displayName: publicData.displayName,
            username: publicData.username,
            firstName: publicData.firstName,
            lastName: publicData.lastName,
            email,
            fallback: 'User'
        });
        const resolvedProfileImageUrl = publicData.profileImageUrl ||
            publicData.photoURL ||
            ((req.user.uid === req.params.uid) ? (req.user.photoURL || null) : null);

        return res.json({
            success: true,
            data: {
                uid: userDoc.id,
                ...publicData,
                displayName: resolvedDisplayName,
                profileImageUrl: resolvedProfileImageUrl,
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
