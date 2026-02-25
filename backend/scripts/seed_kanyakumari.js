import admin from 'firebase-admin';
import { db } from '../src/config/firebase.js';
import ngeohash from 'ngeohash';
import crypto from 'crypto';

/* ===========================
   KANYAKUMARI SEEDING SCRIPT
   Seeds 20 posts around Kanyakumari, Tamil Nadu
=========================== */

const AUTHOR_ID = 'seed-kanyakumari';
const AUTHOR_NAME = 'Kanyakumari Explorer';

// Kanyakumari coordinates (Cape Comorin)
const KANYAKUMARI_LAT = 8.0883;
const KANYAKUMARI_LNG = 77.5385;

// Sample post content for Kanyakumari area
const postTemplates = [
    { title: 'Sunrise at Land\'s End', body: 'Witnessed the magical sunrise where three oceans meet. The southernmost tip of India is breathtaking!' },
    { title: 'Vivekananda Rock Memorial', body: 'Visited the iconic memorial dedicated to Swami Vivekananda. The ferry ride was amazing.' },
    { title: 'Thiruvalluvar Statue', body: 'The 133-foot tall statue of the great Tamil poet stands majestically against the blue ocean.' },
    { title: 'Local Fish Curry', body: 'Had the most delicious fresh fish curry at a beachside shack. Kanyakumari seafood is unmatched!' },
    { title: 'Beach Walk at Dusk', body: 'Evening walk along the Kanyakumari beach. The colors of the sunset are unforgettable.' },
    { title: 'Gandhi Memorial Mandapam', body: 'Paid respects at the Gandhi Memorial where his ashes were kept before immersion.' },
    { title: 'Hidden Coconut Grove', body: 'Discovered a serene coconut grove just outside the main town. Perfect for meditation.' },
    { title: 'Kanyakumari Temple Visit', body: 'The ancient Bhagavathy Amman Temple has such powerful energy. A must-visit!' },
    { title: 'Street Food Adventures', body: 'Tried the famous banana chips and fresh coconut water from local vendors.' },
    { title: 'Ferry to the Rocks', body: 'The short ferry ride to the memorial rocks offers stunning views of the coastline.' },
    { title: 'Local Handicraft Shopping', body: 'Bought beautiful seashell crafts and handmade items from local artisans.' },
    { title: 'Watching the Tides', body: 'Spent hours just watching the waves crash against the rocks. So peaceful.' },
    { title: 'Kanyakumari Lighthouse', body: 'Climbed the lighthouse for a panoramic view of the entire peninsula.' },
    { title: 'Traditional Tamil Breakfast', body: 'Started the day with idli, dosa, and filter coffee at a local eatery.' },
    { title: 'Meeting Local Fishermen', body: 'The fishermen here have such interesting stories about life at the southern tip.' },
    { title: 'Sunset Colors', body: 'The sky turns into a canvas of orange, pink, and purple during sunset here.' },
    { title: 'Peaceful Morning Prayer', body: 'Joined locals for morning prayers by the beach. Such a spiritual experience.' },
    { title: 'Exploring the Backstreets', body: 'Wandered through the colorful streets of Kanyakumari town. So much character!' },
    { title: 'Ocean Breeze', body: 'The constant ocean breeze here is so refreshing. Perfect climate!' },
    { title: 'Goodbye Kanyakumari', body: 'Leaving this beautiful place with memories to last a lifetime. Will definitely return!' }
];

function randomOffset(radiusKm) {
    const radiusInDegrees = radiusKm / 111; // approx conversion
    return (Math.random() - 0.5) * 2 * radiusInDegrees;
}

function generateKanyakumariPost(index) {
    // Generate random location within 5km of Kanyakumari
    const lat = KANYAKUMARI_LAT + randomOffset(5);
    const lng = KANYAKUMARI_LNG + randomOffset(5);
    
    // Generate geohash for the location
    const geoHash = ngeohash.encode(lat, lng, 5);
    
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
        city: 'Kanyakumari',
        country: 'India',
        category: 'General',
        visibility: 'public',
        status: 'active',
        likeCount: Math.floor(Math.random() * 50),
        commentCount: Math.floor(Math.random() * 10),
        createdAt: createdAt,
        updatedAt: createdAt,
        isEvent: false,
        location: {
            lat: lat,
            lng: lng,
            name: 'Kanyakumari'
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
    console.log('🚀 Seeding 20 posts for Kanyakumari, Tamil Nadu...');
    console.log(`📍 Center: ${KANYAKUMARI_LAT}, ${KANYAKUMARI_LNG}`);
    
    const posts = [];
    for (let i = 0; i < 20; i++) {
        posts.push(generateKanyakumariPost(i));
    }
    
    console.log('📤 Inserting posts into Firestore...');
    await batchInsert(posts);
    
    console.log('✅ Successfully seeded 20 posts around Kanyakumari!');
    console.log('\n📋 Post Summary:');
    posts.forEach((post, i) => {
        console.log(`  ${i + 1}. "${post.title}" - (${post.latitude.toFixed(4)}, ${post.longitude.toFixed(4)})`);
    });
    
    process.exit(0);
}

run().catch(err => {
    console.error('❌ Seeding failed:', err);
    process.exit(1);
});
