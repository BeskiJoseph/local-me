import admin from 'firebase-admin';
import { db } from '../src/config/firebase.js';
import ngeohash from 'ngeohash';

// SAFETY: Only allow in development/test environments
if (process.env.NODE_ENV === 'production') {
    console.error('❌ SAFETY BLOCK: Cannot run seed script in PRODUCTION environment');
    console.error('This script is for development/testing only.');
    console.error('Set NODE_ENV to "development" or "test" to proceed.');
    process.exit(1);
}

const KANYAKUMARI_LAT = 8.0823795;
const KANYAKUMARI_LNG = 77.527002;

const CITIES = [
    { name: 'Chennai', lat: 13.0827, lng: 80.2707 },
    { name: 'Mumbai', lat: 19.0760, lng: 72.8777 },
    { name: 'Delhi', lat: 28.7041, lng: 77.1025 },
    { name: 'Bangalore', lat: 12.9716, lng: 77.5946 },
    { name: 'Hyderabad', lat: 17.3850, lng: 78.4867 }
];

async function seedPosts() {
    console.log('Seeding 100 posts...');
    
    let batch = db.batch();
    let count = 0;

    // Generate 50 Local Posts in Kanyakumari
    for (let i = 1; i <= 50; i++) {
        // slight jitter
        const lat = KANYAKUMARI_LAT + (Math.random() - 0.5) * 0.02; 
        const lng = KANYAKUMARI_LNG + (Math.random() - 0.5) * 0.02;

        const docRef = db.collection('posts').doc();
        batch.set(docRef, {
            title: `Local Kanyakumari Post #${i}`,
            body: `This is a sample local post created in the Kanyakumari area.`,
            authorId: 'seed_bot',
            authorName: 'Seed Bot',
            authorProfileImage: null,
            city: 'Kanyakumari',
            country: 'India',
            status: 'active',
            visibility: 'public',
            mediaType: 'none',
            mediaUrl: null,
            likeCount: Math.floor(Math.random() * 5),
            commentCount: 0,
            viewCount: Math.floor(Math.random() * 10),
            engagementScore: Math.floor(Math.random() * 10),
            latitude: lat,
            longitude: lng,
            location: { lat, lng },
            geoHash: ngeohash.encode(lat, lng, 9),
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        
        count++;
        if (count % 500 === 0) {
            await batch.commit();
            batch = db.batch();
        }
    }

    // Generate 50 Trending Posts in other Indian cities
    for (let i = 1; i <= 50; i++) {
        const city = CITIES[i % CITIES.length];
        const lat = city.lat + (Math.random() - 0.5) * 0.05; 
        const lng = city.lng + (Math.random() - 0.5) * 0.05;

        // Make them highly engaging so they show up on Global Feed
        const engagementScore = 5000 + Math.floor(Math.random() * 5000);

        const docRef = db.collection('posts').doc();
        batch.set(docRef, {
            title: `Trending Indian Post #${i}`,
            body: `This is a highly popular post from ${city.name}. It should appear in the global feed!`,
            authorId: 'seed_bot',
            authorName: 'Seed Bot',
            authorProfileImage: null,
            city: city.name,
            country: 'India',
            status: 'active',
            visibility: 'public',
            mediaType: 'none',
            mediaUrl: null,
            likeCount: Math.floor(Math.random() * 500) + 100,
            commentCount: Math.floor(Math.random() * 50) + 10,
            viewCount: Math.floor(Math.random() * 1000) + 500,
            engagementScore: engagementScore,
            latitude: lat,
            longitude: lng,
            location: { lat, lng },
            geoHash: ngeohash.encode(lat, lng, 9),
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        
        count++;
    }

    await batch.commit();
    console.log('Successfully seeded 100 posts.');
    process.exit(0);
}

seedPosts().catch(err => {
    console.error('Seed failed:', err);
    process.exit(1);
});
