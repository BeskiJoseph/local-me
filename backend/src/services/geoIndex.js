import { db } from '../config/firebase.js';
import logger from '../utils/logger.js';

class GeoIndex {
    constructor() {
        this._index = new Map(); // postId → { lat, lng }
        this._isReady = false;
        this._isBuilding = false;
    }

    async build() {
        if (this._isBuilding) return;
        this._isBuilding = true;
        logger.info('[GEO INDEX] Building in-memory index from Firestore...');

        try {
            let totalProcessed = 0;
            let lastDoc = null;

            while (true) {
                let query = db.collection('posts')
                    .where('visibility', '==', 'public')
                    .where('status', '==', 'active')
                    .orderBy('createdAt', 'desc')
                    .select('location', 'latitude', 'longitude', 'createdAt') // Fetch ONLY coords + order field
                    .limit(1000);

                if (lastDoc) {
                    query = query.startAfter(lastDoc);
                }

                const snapshot = await query.get();
                if (snapshot.empty) break;

                snapshot.docs.forEach(doc => {
                    const data = doc.data();
                    let lat = data.latitude;
                    let lng = data.longitude;

                    // Fallback to location object if latitude/longitude are missing
                    if (lat == null || lng == null) {
                        lat = data.location?.lat;
                        lng = data.location?.lng;
                    }

                    if (lat != null && lng != null) {
                        this._index.set(doc.id, {
                            lat: parseFloat(lat),
                            lng: parseFloat(lng)
                        });
                    }
                    lastDoc = doc;
                });

                totalProcessed += snapshot.size;
                if (snapshot.size < 1000) break;
            }

            this._isReady = true;
            this._isBuilding = false;
            logger.info(`[GEO INDEX] Ready - ${this._index.size} posts indexed in RAM (Processed ${totalProcessed})`);
        } catch (error) {
            this._isBuilding = false;
            logger.error({ error: error.message }, '[GEO INDEX] Build failed');
        }
    }

    add(postId, lat, lng) {
        if (lat != null && lng != null) {
            this._index.set(postId, {
                lat: parseFloat(lat),
                lng: parseFloat(lng)
            });
            logger.debug({ postId }, '[GEO INDEX] Added post to RAM index');
        }
    }

    remove(postId) {
        if (this._index.has(postId)) {
            this._index.delete(postId);
            logger.debug({ postId }, '[GEO INDEX] Removed post from RAM index');
        }
    }

    query({ userLat, userLng, lastDistance, lastPostId, watchedIdsSet, limit }) {
        const results = [];

        for (const [postId, coords] of this._index.entries()) {
            // 1. Skip watched
            if (watchedIdsSet && watchedIdsSet.has(postId)) continue;

            // Calculate distance
            const distance = this._getDistance(userLat, userLng, coords.lat, coords.lng);

            // 2. Filter by lastDistance (with 1m tolerance)
            if (distance < lastDistance - 0.001) continue;

            // 3. Tiebreaker: same distance, skip if postId <= lastPostId
            if (
                lastPostId &&
                Math.abs(distance - lastDistance) < 0.001 &&
                postId <= lastPostId
            ) continue;

            results.push({ postId, distance });
        }

        // Sort by distance ASC, then by postId
        results.sort((a, b) => {
            if (Math.abs(a.distance - b.distance) < 0.001) {
                return a.postId.localeCompare(b.postId);
            }
            return a.distance - b.distance;
        });

        return results.slice(0, limit);
    }

    _getDistance(lat1, lon1, lat2, lon2) {
        const R = 6371;
        const dLat = (lat2 - lat1) * Math.PI / 180;
        const dLon = (lon2 - lon1) * Math.PI / 180;
        const a =
            Math.sin(dLat / 2) * Math.sin(dLat / 2) +
            Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
            Math.sin(dLon / 2) * Math.sin(dLon / 2);
        return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    }

    get size() {
        return this._index.size;
    }

    get isReady() {
        return this._isReady;
    }
}

export const geoIndex = new GeoIndex();
