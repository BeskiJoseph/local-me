import admin from 'firebase-admin';
import { db } from '../src/config/firebase.js';
import ngeohash from 'ngeohash';
import crypto from 'crypto';

/* ===========================
   TAMIL NADU SEEDING SCRIPT
   Seeds 20 posts across various cities in Tamil Nadu
=========================== */

const AUTHOR_ID = 'seed-tamilnadu';
const AUTHOR_NAME = 'Tamil Nadu Explorer';

// Different cities in Tamil Nadu
const locations = [
    { city: 'Chennai', lat: 13.0827, lng: 80.2707 },
    { city: 'Coimbatore', lat: 11.0168, lng: 76.9558 },
    { city: 'Madurai', lat: 9.9252, lng: 78.1198 },
    { city: 'Tiruchirappalli', lat: 10.7905, lng: 78.7047 },
    { city: 'Salem', lat: 11.6643, lng: 78.1460 },
    { city: 'Tirunelveli', lat: 8.7139, lng: 77.7567 },
    { city: 'Erode', lat: 11.3410, lng: 77.7172 },
    { city: 'Vellore', lat: 12.9165, lng: 79.1325 },
    { city: 'Thoothukudi', lat: 8.7642, lng: 78.1348 },
    { city: 'Kanyakumari', lat: 8.0883, lng: 77.5385 }
];

// Sample post content for Tamil Nadu
const postTemplates = [
    { title: 'Marina Beach Stroll', body: 'Taking a long walk along Marina Beach in Chennai. The evening breeze is amazing!' },
    { title: 'Ooty Toy Train', body: 'The Nilgiri Mountain Railway offers some of the most scenic views of the Western Ghats.' },
    { title: 'Meenakshi Temple', body: 'The architecture of the Madurai Meenakshi Amman Temple is simply breathtaking.' },
    { title: 'Filter Coffee Mornings', body: 'Nothing beats a strong cup of authentic South Indian filter coffee to start the day.' },
    { title: 'Brihadeeswarar Temple', body: 'Marveling at the 1000-year-old Big Temple in Thanjavur. A true architectural wonder.' },
    { title: 'Kodaikanal Lake', body: 'Boating on the serene Kodaikanal Lake surrounded by the misty hills.' },
    { title: 'Chettinad Cuisine', body: 'Trying out some spicy and flavorful authentic Chettinad chicken curry.' },
    { title: 'Pamban Bridge', body: 'The train journey across the Pamban Bridge in Rameswaram is a thrilling experience.' },
    { title: 'Silk Sarees of Kanchipuram', body: 'Exploring the vibrant and intricate silk sarees woven by the artisans of Kanchipuram.' },
    { title: 'Sunrise at Kanyakumari', body: 'Watching the sunrise where the three oceans meet at the southern tip of India.' },
    { title: 'Mahabalipuram Monuments', body: 'Exploring the ancient rock-cut temples and the Shore Temple at Mahabalipuram.' },
    { title: 'Yelagiri Hills', body: 'A quick weekend getaway to the peaceful Yelagiri hills. Perfect nature retreat.' },
    { title: 'Courtallam Waterfalls', body: 'Enjoying a refreshing dip at the Courtallam waterfalls, the spa of South India.' },
    { title: 'Street Food in Madurai', body: 'Jigarthanda and fluffy idlis from the street vendors in Madurai. Absolutely delicious!' },
    { title: 'Coimbatore Weather', body: 'Loving the pleasant weather in Coimbatore today. The Manchester of South India.' },
    { title: 'Pichavaram Mangroves', body: 'Boating through the world\'s second largest mangrove forest in Pichavaram.' },
    { title: 'Dhanushkodi Ruins', body: 'Visiting the ghost town of Dhanushkodi. The history and the views are surreal.' },
    { title: 'Kolli Hills Hairpin Bends', body: 'Driving through the 70 hairpin bends of Kolli Hills. An adventurer\'s delight!' },
    { title: 'Srirangam Temple', body: 'Visiting the massive Sri Ranganathaswamy Temple in Trichy, the largest functioning Hindu temple.' },
    { title: 'Pongal Celebrations', body: 'Experiencing the vibrant harvest festival of Pongal with traditional kolams and sweet pongal.' }
];

function randomOffset(radiusKm) {
    const radiusInDegrees = radiusKm / 111; // approx conversion
    return (Math.random() - 0.5) * 2 * radiusInDegrees;
}

function generateTamilNaduPost(index) {
    // Select a city based on index
    const location = locations[index % locations.length];

    // Generate random location within 5km of the city center
    const lat = location.lat + randomOffset(5);
    const lng = location.lng + randomOffset(5);

    // Generate geohash for the location
    const geoHash = ngeohash.encode(lat, lng, 5);

    // Select a template
    const template = postTemplates[index % postTemplates.length];

    const now = new Date();
    // Create varied timestamps (posts from last 7 days)
    const daysAgo = Math.floor(Math.random() * 7);
    const hoursAgo = Math.floor(Math.random() * 24);
    const createdAt = new Date(now.getTime() - (daysAgo * 24 + hoursAgo) * 60 * 60 * 1000);

    return {
        id: crypto.randomUUID(),
        authorId: AUTHOR_ID,
        authorName: AUTHOR_NAME,
        authorProfileImage: '',
        title: template.title,
        body: template.body,
        latitude: lat,
        longitude: lng,
        geoHash: geoHash,
        city: location.city,
        state: 'Tamil Nadu',
        country: 'India',
        category: 'General',
        visibility: 'public',
        status: 'active',
        likeCount: Math.floor(Math.random() * 100),
        commentCount: Math.floor(Math.random() * 20),
        createdAt: createdAt,
        updatedAt: createdAt,
        isEvent: false,
        location: {
            lat: lat,
            lng: lng,
            name: location.city
        }
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

async function run() {
    console.log('🚀 Seeding 20 posts for Tamil Nadu...');

    const posts = [];
    for (let i = 0; i < 20; i++) {
        posts.push(generateTamilNaduPost(i));
    }

    console.log('📤 Inserting posts into Firestore...');
    await batchInsert(posts);

    console.log('✅ Successfully seeded 20 posts across Tamil Nadu!');
    console.log('\n📋 Post Summary:');
    posts.forEach((post, i) => {
        console.log(`  ${i + 1}. [${post.city}] "${post.title}" - (${post.latitude.toFixed(4)}, ${post.longitude.toFixed(4)})`);
    });

    process.exit(0);
}

run().catch(err => {
    console.error('❌ Seeding failed:', err);
    process.exit(1);
});
