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
            // Search users by username (lowercase) or display name (lowercase)
            const usernameQuery = db.collection('users')
                .where('username', '>=', searchTerm)
                .where('username', '<=', searchTerm + '\uf8ff')
                .limit(pageSize);

            const displayNameQuery = db.collection('users')
                .where('displayName_lowercase', '>=', searchTerm)
                .where('displayName_lowercase', '<=', searchTerm + '\uf8ff')
                .limit(pageSize);

            const firstNameQuery = db.collection('users')
                .where('firstName_lowercase', '>=', searchTerm)
                .where('firstName_lowercase', '<=', searchTerm + '\uf8ff')
                .limit(pageSize);

            const [usernameSnap, displayNameSnap, firstNameSnap] = await Promise.all([
                usernameQuery.get(),
                displayNameQuery.get(),
                firstNameQuery.get()
            ]);

            const userMap = new Map();
            const docs = [...usernameSnap.docs, ...displayNameSnap.docs, ...firstNameSnap.docs];
            docs.forEach(doc => userMap.set(doc.id, { id: doc.id, ...doc.data() }));

            results = Array.from(userMap.values()).slice(0, pageSize);
        } else {
            // Search posts by title or body prefix (case-insensitive)
            // Simplified queries to avoid composite index requirements on localhost
            const titleQuery = db.collection('posts')
                .where('title_lowercase', '>=', searchTerm)
                .where('title_lowercase', '<=', searchTerm + '\uf8ff')
                .limit(pageSize * 2);

            const bodyQuery = db.collection('posts')
                .where('body_lowercase', '>=', searchTerm)
                .where('body_lowercase', '<=', searchTerm + '\uf8ff')
                .limit(pageSize * 2);

            const [titleSnap, bodySnap] = await Promise.all([
                titleQuery.get(),
                bodyQuery.get()
            ]);

            const postMap = new Map();
            const allDocs = [...titleSnap.docs, ...bodySnap.docs];

            allDocs.forEach(doc => {
                const data = doc.data();
                // Filter by visibility and status in memory to avoid composite index requirement
                if (data.visibility === 'public' && data.status === 'active') {
                    postMap.set(doc.id, { id: doc.id, ...data });
                }
            });

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
