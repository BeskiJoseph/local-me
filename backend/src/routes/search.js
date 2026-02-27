import express from 'express';
import { db } from '../config/firebase.js';
import authenticate from '../middleware/auth.js';

const router = express.Router();

/**
 * @route   GET /api/search
 * @desc    Search for users or posts
 */
router.get('/', authenticate, async (req, res, next) => {
    try {
        const { q, type = 'posts', limit = 20 } = req.query;
        if (!q || q.trim().length < 1) return res.json({ data: [] });

        const searchTerm = q.trim().toLowerCase();
        const pageSize = Math.min(parseInt(limit), 50);
        let results = [];

        if (type === 'users') {
            // Search users by username prefix (case-insensitive)
            const usernameQuery = db.collection('users')
                .where('username', '>=', searchTerm)
                .where('username', '<=', searchTerm + '\uf8ff')
                .limit(pageSize);

            // Also search by display name
            const displayNameQuery = db.collection('users')
                .where('displayName', '>=', searchTerm)
                .where('displayName', '<=', searchTerm + '\uf8ff')
                .limit(pageSize);

            const [usernameSnap, displayNameSnap] = await Promise.all([
                usernameQuery.get(),
                displayNameQuery.get()
            ]);

            const userMap = new Map();
            usernameSnap.docs.forEach(doc => userMap.set(doc.id, { id: doc.id, ...doc.data() }));
            displayNameSnap.docs.forEach(doc => userMap.set(doc.id, { id: doc.id, ...doc.data() }));

            results = Array.from(userMap.values()).slice(0, pageSize);
        } else {
            // Search posts by title prefix (case-insensitive)
            const titleQuery = db.collection('posts')
                .where('visibility', '==', 'public')
                .where('status', '==', 'active')
                .where('title_lowercase', '>=', searchTerm)
                .where('title_lowercase', '<=', searchTerm + '\uf8ff')
                .limit(pageSize);

            // Also search by body text (case-insensitive)
            const bodyQuery = db.collection('posts')
                .where('visibility', '==', 'public')
                .where('status', '==', 'active')
                .where('body_lowercase', '>=', searchTerm)
                .where('body_lowercase', '<=', searchTerm + '\uf8ff')
                .limit(pageSize);

            const [titleSnap, bodySnap] = await Promise.all([
                titleQuery.get(),
                bodyQuery.get()
            ]);

            const postMap = new Map();
            titleSnap.docs.forEach(doc => postMap.set(doc.id, { id: doc.id, ...doc.data() }));
            bodySnap.docs.forEach(doc => postMap.set(doc.id, { id: doc.id, ...doc.data() }));

            results = Array.from(postMap.values()).slice(0, pageSize);
        }

        return res.json({
            success: true,
            data: results,
            error: null
        });
    } catch (err) {
        next(err);
    }
});

export default router;
