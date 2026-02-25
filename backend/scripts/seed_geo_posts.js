import admin from 'firebase-admin';
import { db } from '../src/config/firebase.js';
import crypto from 'crypto';

/* ===========================
   CONFIGURATION
=========================== */

const TOTAL = 1100;
const AUTHOR_ID = 'seed-system';

/* ===========================
   UTILITIES
=========================== */

function randomOffset(radiusKm) {
    const radiusInDegrees = radiusKm / 111; // approx conversion
    return (Math.random() - 0.5) * radiusInDegrees;
}

function generatePost(centerLat, centerLng, radiusKm, tag) {
    const lat = centerLat + randomOffset(radiusKm);
    const lng = centerLng + randomOffset(radiusKm);

    return {
        id: crypto.randomUUID(),
        authorId: AUTHOR_ID,
        authorName: `Seed ${tag}`,
        authorProfileImage: '',
        title: `Synthetic ${tag} Post`,
        body: 'This is a seeded geo validation post para testing geo distribution and ring priority.',
        latitude: lat,
        longitude: lng,
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
    const batch = db.batch();
    posts.forEach(post => {
        const ref = db.collection('posts').doc(post.id);
        batch.set(ref, post);
    });
    await batch.commit();
}

/* ===========================
   SEEDING LOGIC
=========================== */

async function seedCluster(name, lat, lng, count, radiusKm) {
    console.log(`Seeding ${count} posts for ${name}...`);
    const posts = [];
    for (let i = 0; i < count; i++) {
        posts.push(generatePost(lat, lng, radiusKm, name));
    }

    // Firestore max 500 writes per batch
    while (posts.length) {
        await batchInsert(posts.splice(0, 450));
    }
}

async function run() {
    console.log('🚀 Starting Geo Seeding...');

    // Dense Chennai
    await seedCluster('Chennai Dense', 13.0827, 80.2707, 300, 2);

    // Medium Madurai
    await seedCluster('Madurai Medium', 9.9252, 78.1198, 200, 10);

    // Sparse Rural TN
    await seedCluster('Rural Sparse', 10.5, 77.0, 100, 40);

    // Delhi Noise
    await seedCluster('Delhi Noise', 28.6139, 77.2090, 150, 5);

    // Mumbai Noise
    await seedCluster('Mumbai Noise', 19.0760, 72.8777, 150, 5);

    // Random India Spread
    console.log('Seeding 200 Random India posts...');
    const randomPosts = [];
    for (let i = 0; i < 200; i++) {
        const lat = 8 + Math.random() * 25;
        const lng = 68 + Math.random() * 25;
        randomPosts.push(generatePost(lat, lng, 1, 'Random India'));
    }

    while (randomPosts.length) {
        await batchInsert(randomPosts.splice(0, 450));
    }

    console.log('✅ Seeding complete.');
    process.exit(0);
}

run().catch(err => {
    console.error('Seeding failed:', err);
    process.exit(1);
});
