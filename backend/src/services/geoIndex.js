import ngeohash from 'ngeohash';
import logger from '../utils/logger.js';
import { db } from '../config/firebase.js';

// Mathematical Haversine for exact distance
function getDistance(lat1, lon1, lat2, lon2) {
    const R = 6371; // Earth radius in km
    const dLat = (lat2 - lat1) * Math.PI / 180;
    const dLon = (lon2 - lon1) * Math.PI / 180;
    const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
        Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
        Math.sin(dLon / 2) * Math.sin(dLon / 2);
    return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

class GeoIndex {
    constructor() {
        // Group posts into Precision 4 Geohash Buckets (~40km chunks)
        // Map<Precision4Hash, Map<PostId, PostData>>
        this.buckets = new Map(); 
        this._isReady = false;
        this._totalCount = 0;
    }

    async build() {
        try {
            logger.info('[GEO INDEX] Building in-memory spatial index from Firestore...');
            const snapshot = await db.collection('posts')
                .where('visibility', '==', 'public')
                .where('status', '==', 'active')
                .get();
                
            this.buckets.clear();
            this._totalCount = 0;
            
            snapshot.forEach(doc => {
                const data = doc.data();
                const lat = data.latitude !== undefined ? data.latitude : data.location?.lat;
                const lng = data.longitude !== undefined ? data.longitude : data.location?.lng;
                if (lat !== undefined && lng !== undefined) {
                    this.add(doc.id, data);
                }
            });
            
            this._isReady = true;
            logger.info(`[GEO INDEX] Build complete. Indexed ${this._totalCount} posts across ${this.buckets.size} spatial buckets.`);
        } catch (error) {
            logger.error({ err: error }, '[GEO INDEX] Failed to build index');
        }
    }

    add(postId, data) {
        const lat = data.latitude !== undefined ? data.latitude : data.location?.lat;
        const lng = data.longitude !== undefined ? data.longitude : data.location?.lng;
        if (lat === undefined || lng === undefined) return;
        
        const p4Hash = ngeohash.encode(lat, lng, 4);
        if (!this.buckets.has(p4Hash)) {
            this.buckets.set(p4Hash, new Map());
        }
        
        const bucket = this.buckets.get(p4Hash);
        if (!bucket.has(postId)) this._totalCount++;
        
        // Use a robust media type detection
        let effectiveType = data.mediaType ? data.mediaType.toLowerCase() : null;
        const category = (data.category || '').toLowerCase();
        const url = (data.mediaUrl || '').toLowerCase();

        if (effectiveType === 'video' || category === 'reels' || url.endsWith('.mp4') || url.endsWith('.mov')) {
            effectiveType = 'video';
        } else if (effectiveType === 'image' || url.endsWith('.jpg') || url.endsWith('.png') || url.endsWith('.jpeg') || url.endsWith('.webp')) {
            effectiveType = 'image';
        }

        bucket.set(postId, {
            id: postId,
            latitude: lat,
            longitude: lng,
            mediaType: effectiveType,
            engagementScore: data.engagementScore || 0,
            createdAt: data.createdAt?.toMillis ? data.createdAt.toMillis() : (data.createdAt?._seconds ? data.createdAt._seconds * 1000 : Date.now())
        });
    }

    remove(postId) {
        for (const [p2Hash, bucket] of this.buckets.entries()) {
            if (bucket.has(postId)) {
                bucket.delete(postId);
                this._totalCount--;
                if (bucket.size === 0) this.buckets.delete(p2Hash);
                return;
            }
        }
    }

    update(postId, updates) {
        let foundBucket = null;
        let existing = null;
        for (const bucket of this.buckets.values()) {
            if (bucket.has(postId)) {
                foundBucket = bucket;
                existing = bucket.get(postId);
                break;
            }
        }
        
        if (!existing) return;
        
        if (updates.latitude !== undefined || updates.longitude !== undefined || updates.location !== undefined) {
            this.remove(postId);
            this.add(postId, { ...existing, ...updates });
        } else {
            foundBucket.set(postId, { ...existing, ...updates });
        }
    }

    queryLocal(userLat, userLng, watchedIdsSet, mediaType, limit = 20) {
        if (!this._isReady) return { posts: [], maxScannedDistance: 0, hasMore: false };
        
        let candidates = [];
        const totalInIndex = this.size;
        let mediaMatchCount = 0;

        // 1. Collect ALL matching posts from ALL buckets
        for (const bucket of this.buckets.values()) {
            if (candidates.length > 2000) break; // ⚠️ Scale guard
            
            for (const post of bucket.values()) {
                if (mediaType && post.mediaType !== mediaType) continue;
                
                const distance = getDistance(userLat, userLng, post.latitude, post.longitude);
                
                // 🔥 Issue 3: Removed strict 500km limit to allow feed continuity 
                // (Radial expansion happens via the naturally sorted 'candidates' list)
                
                mediaMatchCount++;
                candidates.push({ ...post, distance });
            }
        }

        // 2. Sort the FULL list by distance
        candidates.sort((a, b) => {
            if (Math.abs(a.distance - b.distance) < 0.001) return (b.createdAt || 0) - (a.createdAt || 0);
            return a.distance - b.distance;
        });

        // 🛡️ Debug Log: Top 10 sorted (as requested by user)
        logger.info({ 
            top10BeforeFilter: candidates.slice(0, 10).map(p => ({ id: p.id, dist: p.distance.toFixed(2) }))
        }, '[GEOINDEX] Pre-filter order');
        
        // 3. Filter by seenIds and take first N (Issue 1: Optimized loop)
        const finalResults = [];
        let hasMore = false;

        for (const p of candidates) {
            if (!watchedIdsSet.has(p.id)) {
                if (finalResults.length < limit) {
                    finalResults.push(p);
                } else {
                    hasMore = true;
                    break;
                }
            }
        }

        const farthest = finalResults.length > 0 ? finalResults[finalResults.length - 1].distance : 0;
        
        logger.info({ 
            totalInIndex, 
            mediaMatchCount,
            unseenFound: candidates.filter(p => !watchedIdsSet.has(p.id)).length,
            limit,
            returned: finalResults.length
        }, '[GEOINDEX] Query complete');
        
        return { 
            posts: finalResults, 
            maxScannedDistance: farthest,
            hasMore
        };
    }

    get size() { return this._totalCount; }
    get isReady() { return this._isReady; }
}

export const geoIndex = new GeoIndex();
