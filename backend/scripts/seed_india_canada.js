import admin from 'firebase-admin';
import { db } from '../src/config/firebase.js';
import crypto from 'crypto';
import ngeohash from 'ngeohash';

const AUTHOR_ID = 'geo-seed';
const AUTHOR_NAME = 'Geo Seed';
const AUTHOR_AVATAR = '';

/* ============================= */

function randomOffset(radiusKm) {
    return (Math.random() - 0.5) * (radiusKm / 111);
}

function generatePost(lat, lng, radiusKm, city, country) {
    const finalLat = lat + randomOffset(radiusKm);
    const finalLng = lng + randomOffset(radiusKm);

    return {
        id: crypto.randomUUID(),
        authorId: AUTHOR_ID,
        authorName: AUTHOR_NAME,
        authorProfileImage: AUTHOR_AVATAR,

        title: `Seed Post - ${city}`,
        body: `Geo validation content for ${city}, ${country}. Synthetic post for testing geo-priority.`,

        latitude: finalLat,
        longitude: finalLng,
        geoHash: ngeohash.encode(finalLat, finalLng, 9),

        location: city,
        country: country,
        category: 'General',
        visibility: 'public',
        status: 'active',

        likeCount: 0,
        commentCount: 0,

        createdAt: new Date(),
        updatedAt: new Date(),
        isEvent: false
    };
}

async function batchInsert(posts) {
    while (posts.length) {
        const batch = db.batch();
        posts.splice(0, 450).forEach(post => {
            batch.set(db.collection('posts').doc(post.id), post);
        });
        await batch.commit();
    }
}

async function seedCity(city, country, lat, lng, count, radiusKm) {
    console.log(`Seeding ${count} posts for ${city}, ${country}`);
    const posts = [];

    for (let i = 0; i < count; i++) {
        posts.push(generatePost(lat, lng, radiusKm, city, country));
    }

    await batchInsert(posts);
}

/* ============================= */
/* MAIN EXECUTION */
/* ============================= */

async function run() {
    console.log('🚀 Seeding India + Canada Geo Dataset...');

    // ================= INDIA - Tamil Nadu =================
    await seedCity('Chennai', 'India', 13.0827, 80.2707, 120, 5);
    await seedCity('Coimbatore', 'India', 11.0168, 76.9558, 80, 5);
    await seedCity('Madurai', 'India', 9.9252, 78.1198, 80, 5);
    await seedCity('Tiruchirappalli', 'India', 10.7905, 78.7047, 60, 5);
    await seedCity('Salem', 'India', 11.6643, 78.1460, 60, 5);
    await seedCity('Tirunelveli', 'India', 8.7139, 77.7567, 50, 5);
    await seedCity('Erode', 'India', 11.3410, 77.7172, 50, 5);

    // ================= CANADA =================
    await seedCity('Toronto', 'Canada', 43.6532, -79.3832, 120, 5);
    await seedCity('Ottawa', 'Canada', 45.4215, -75.6972, 60, 5);
    await seedCity('Vancouver', 'Canada', 49.2827, -123.1207, 100, 5);
    await seedCity('Calgary', 'Canada', 51.0447, -114.0719, 80, 5);
    await seedCity('Montreal', 'Canada', 45.5017, -73.5673, 100, 5);
    await seedCity('Winnipeg', 'Canada', 49.8951, -97.1384, 40, 5);

    console.log('✅ 1000 Geo Posts Seeded Successfully');
    process.exit(0);
}

run().catch(err => {
    console.error(err);
    process.exit(1);
});
