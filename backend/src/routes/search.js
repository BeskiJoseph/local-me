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
        if (!q) return res.json({ data: [] });

        const pageSize = Math.min(parseInt(limit), 50);
        let query;

        if (type === 'users') {
            query = db.collection('users')
                .where('username', '>=', q)
                .where('username', '<=', q + '\uf8ff')
                .limit(pageSize);
        } else {
            query = db.collection('posts')
                .where('visibility', '==', 'public')
                .where('status', '==', 'active')
                .where('text', '>=', q)
                .where('text', '<=', q + '\uf8ff')
                .limit(pageSize);
            // Note: Cloud Firestore prefix search is limited. 
            // Better to use Algolia/Typesense for full-text.
        }

        const snapshot = await query.get();
        const results = snapshot.docs.map(doc => ({
            id: doc.id,
            ...doc.data()
        }));

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
