import { db } from '../config/firebase.js';
import logger from '../utils/logger.js';

export const USER_CONTEXT_CACHE = new Map();
export const USER_CONTEXT_CACHE_TTL = 5 * 60 * 1000;

export const INTERACTION_DELTAS = {
    likes: new Map(),
    unlikes: new Map(),
    counts: new Map(),
    follows: new Map(),
    unfollows: new Map()
};

const trackDelta = (map, key, value, add = true) => {
    if (!map.has(key)) map.set(key, new Set());
    const set = map.get(key);
    if (add) set.add(value); else set.delete(value);
    setTimeout(() => { if (set.has(value)) set.delete(value); }, 60000);
};

const trackCountDelta = (postId, delta) => {
    const current = INTERACTION_DELTAS.counts.get(postId) || 0;
    INTERACTION_DELTAS.counts.set(postId, current + delta);
    setTimeout(() => {
        const val = INTERACTION_DELTAS.counts.get(postId) || 0;
        INTERACTION_DELTAS.counts.set(postId, val - delta);
    }, 60000);
};

export const updateUserContextCache = (userId, targetId, action = 'invalidate') => {
    const key = `user_context:${userId}`;

    switch (action) {
        case 'like':
            trackDelta(INTERACTION_DELTAS.likes, userId, targetId, true);
            trackDelta(INTERACTION_DELTAS.unlikes, userId, targetId, false);
            trackCountDelta(targetId, 1);
            break;
        case 'unlike':
            trackDelta(INTERACTION_DELTAS.unlikes, userId, targetId, true);
            trackDelta(INTERACTION_DELTAS.likes, userId, targetId, false);
            trackCountDelta(targetId, -1);
            break;
        case 'follow':
            trackDelta(INTERACTION_DELTAS.follows, userId, targetId, true);
            trackDelta(INTERACTION_DELTAS.unfollows, userId, targetId, false);
            break;
        case 'unfollow':
            trackDelta(INTERACTION_DELTAS.unfollows, userId, targetId, true);
            trackDelta(INTERACTION_DELTAS.follows, userId, targetId, false);
            break;
    }

    if (!USER_CONTEXT_CACHE.has(key)) return;
    const cached = USER_CONTEXT_CACHE.get(key);
    if (!cached?.data) return;

    const { likedIds, mutedIds, followedIds } = cached.data;
    switch (action) {
        case 'like': likedIds.add(targetId); break;
        case 'unlike': likedIds.delete(targetId); break;
        case 'mute': mutedIds.add(targetId); break;
        case 'unmute': mutedIds.delete(targetId); break;
        case 'follow': if (followedIds) followedIds.add(targetId); break;
        case 'unfollow': if (followedIds) followedIds.delete(targetId); break;
    }
    USER_CONTEXT_CACHE.set(key, cached);
};

export const invalidateUserContext = (userId) => updateUserContextCache(userId, null, 'invalidate');

export async function getUserContext(userId) {
    const contextKey = `user_context:${userId}`;
    const cachedContext = USER_CONTEXT_CACHE.get(contextKey);

    let likedPostIds = new Set();
    let mutedUserIds = new Set();
    let followedUserIds = new Set();

    if (cachedContext && (Date.now() - cachedContext.timestamp < USER_CONTEXT_CACHE_TTL)) {
        likedPostIds = cachedContext.data.likedIds;
        mutedUserIds = cachedContext.data.mutedIds;
        followedUserIds = cachedContext.data.followedIds || new Set();
    } else {
        const [mutedRes, likesRes, followsRes] = await Promise.all([
            db.collection('users').doc(userId).get()
                .then(doc => new Set(doc.exists ? doc.data().mutedUsers || [] : []))
                .catch(() => new Set()),
            db.collection('likes').where('userId', '==', userId)
                .limit(2000).get()
                .then(snap => new Set(snap.docs.map(d => d.data().postId)))
                .catch((err) => { logger.error('getUserContext likes error', { err: err.message }); return new Set(); }),
            db.collection('follows').where('followerId', '==', userId)
                .limit(1000).get()
                .then(snap => new Set(snap.docs.map(d => d.data().followingId)))
                .catch(() => new Set())
        ]);

        likedPostIds = likesRes;
        mutedUserIds = mutedRes;
        followedUserIds = followsRes;

        USER_CONTEXT_CACHE.set(contextKey, {
            timestamp: Date.now(),
            data: { likedIds: likedPostIds, mutedIds: mutedUserIds, followedIds: followedUserIds }
        });
    }

    // Patch with in-flight deltas
    const pendingLikes = INTERACTION_DELTAS.likes.get(userId);
    const pendingUnlikes = INTERACTION_DELTAS.unlikes.get(userId);
    const pendingFollows = INTERACTION_DELTAS.follows.get(userId);
    const pendingUnfollows = INTERACTION_DELTAS.unfollows.get(userId);

    if (pendingLikes) pendingLikes.forEach(id => likedPostIds.add(id));
    if (pendingUnlikes) pendingUnlikes.forEach(id => likedPostIds.delete(id));
    if (pendingFollows) pendingFollows.forEach(id => followedUserIds.add(id));
    if (pendingUnfollows) pendingUnfollows.forEach(id => followedUserIds.delete(id));

    return { likedPostIds, mutedUserIds, followedUserIds };
}
