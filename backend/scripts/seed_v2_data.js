import admin from 'firebase-admin';
import { db } from '../src/config/firebase.js';
import ngeohash from 'ngeohash';
import crypto from 'crypto';

/* ============================================================
   V2 SEED SCRIPT: TAMIL NADU & GLOBAL TRENDING
   ============================================================ */

const AUTHOR_ID = 'seed-v2-user';
const AUTHOR_NAME = 'Tamil Nadu Explorer';

const locations = [
    { city: 'Chennai', lat: 13.0827, lng: 80.2707 },
    { city: 'Coimbatore', lat: 11.0168, lng: 76.9558 },
    { city: 'Madurai', lat: 9.9252, lng: 78.1198 },
    { city: 'Trichy', lat: 10.7905, lng: 78.7047 },
    { city: 'Salem', lat: 11.6643, lng: 78.1460 },
    { city: 'Erode', lat: 11.3410, lng: 77.7172 },
    { city: 'Vellore', lat: 12.9165, lng: 79.1325 },
    { city: 'Tirunelveli', lat: 8.7139, lng: 77.7567 }
];

const postTemplates = [
    { title: 'Marina Beach Sunrise', body: 'The sunrise at Marina is one of a kind. Best spot for a morning walk!' },
    { title: 'Coimbatore Foodie Log', body: 'Just had the best Biryani at Valarmathi Mess. Coimbatore food is underrated!' },
    { title: 'Madurai Temple Vibe', body: 'Evening prayers at Meenakshi Amman Temple. The atmosphere is serene.' },
    { title: 'Trichy RockFort View', body: 'The view of the city from the climb is worth every step.' },
    { title: 'Salem Mangoes!', body: 'Tis the season! The Malgoa mangoes from Salem are finally here.' },
    { title: 'Morning Filter Coffee', body: 'Nothing like a strong cup of Kumbakonam degree coffee.' },
    { title: 'Night Market Vibes', body: 'The street food scene tonight is absolutely buzzing with energy.' },
    { title: 'Local Hidden Gem', body: 'Found this small waterfall near the outskirts. Totally peaceful.' }
];

function generatePost({ city, lat, lng, title, body, hoursAgo, likes, comments, views }) {
    const createdAt = new Date(Date.now() - hoursAgo * 3600000);
    const geoHash = ngeohash.encode(lat, lng, 7); // High precision

    return {
        id: crypto.randomUUID(),
        authorId: AUTHOR_ID,
        authorName: AUTHOR_NAME,
        authorDisplayName: 'Tamil Explorer',
        title,
        body,
        text: `${title}\n${body}`,
        latitude: lat,
        longitude: lng,
        geoHash: geoHash,
        city,
        state: 'Tamil Nadu',
        country: 'India',
        category: 'General',
        visibility: 'public',
        status: 'active',
        likeCount: likes,
        commentCount: comments,
        viewCount: views,
        createdAt: admin.firestore.Timestamp.fromDate(createdAt),
        updatedAt: admin.firestore.Timestamp.fromDate(createdAt),
        isEvent: false,
        location: {
            lat: lat,
            lng: lng,
            name: city
        }
    };
}

async function run() {
    console.log('🚀 Starting V2 Data Seeding...');
    const posts = [];

    // 1. TAMIL NADU CITY SPREAD (for Local Feed testing)
    console.log('📍 Seeding city-specific posts for local feed...');
    locations.forEach((loc, i) => {
        const template = postTemplates[i % postTemplates.length];
        posts.push(generatePost({
            ...loc,
            title: template.title,
            body: template.body,
            hoursAgo: Math.floor(Math.random() * 24),
            likes: 10 + Math.floor(Math.random() * 50),
            comments: 2 + Math.floor(Math.random() * 10),
            views: 100 + Math.floor(Math.random() * 500)
        }));
    });

    // 2. GLOBAL TRENDING TEST CASES (to verify time-decay logic)
    console.log('📈 Seeding trending test cases for global feed...');

    // Case A: High Engagement, Very Recent (Should be Top)
    posts.push(generatePost({
        ...locations[0],
        title: '🔥 Trending: Breaking News Chennai',
        body: 'This just happened! Everyone is talking about it.',
        hoursAgo: 1,
        likes: 100,
        comments: 25,
        views: 1000
    }));

    // Case B: High Engagement, Old (Should be Lower than Case A)
    posts.push(generatePost({
        ...locations[1],
        title: '💎 Popular: Old but Gold Coimbatore',
        body: 'This post is two days old but has a lot of likes.',
        hoursAgo: 48,
        likes: 500,
        comments: 100,
        views: 5000
    }));

    // Case C: Medium Engagement, Recent
    posts.push(generatePost({
        ...locations[2],
        title: '⚡ Rising: Madurai Evening',
        body: 'People are starting to engage with this one.',
        hoursAgo: 5,
        likes: 60,
        comments: 15,
        views: 400
    }));

    // Case D: Zero Engagement, Brand New
    posts.push(generatePost({
        ...locations[3],
        title: '🆕 New: Fresh from Trichy',
        body: 'Just posted. No one has seen this yet.',
        hoursAgo: 0.1,
        likes: 0,
        comments: 0,
        views: 1
    }));

    console.log(`📤 Batch inserting ${posts.length} posts...`);
    const batch = db.batch();
    posts.forEach(p => {
        const ref = db.collection('posts').doc(p.id);
        batch.set(ref, p);
    });

    await batch.commit();
    console.log('✅ Seeding complete!');
    process.exit(0);
}

run().catch(err => {
    console.error('❌ Seeding failed:', err);
    process.exit(1);
});
