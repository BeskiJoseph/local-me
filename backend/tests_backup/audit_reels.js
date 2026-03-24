import admin from 'firebase-admin';
import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Load .env from backend root
dotenv.config();

function cleanKey(key) {
    if (!key) return key;
    return key.trim().replace(/^["']|["']$/g, '').replace(/\\n/g, '\n');
}

async function runAudit() {
  if (!process.env.FIREBASE_PROJECT_ID) {
    console.error('❌ Missing FIREBASE_PROJECT_ID in .env');
    process.exit(1);
  }

  admin.initializeApp({
    credential: admin.credential.cert({
      projectId: process.env.FIREBASE_PROJECT_ID,
      privateKey: cleanKey(process.env.FIREBASE_PRIVATE_KEY),
      clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
    }),
  });

  const db = admin.firestore();

  console.log('--- Auditing Posts for Reels Consistency (Env-based) ---');
  const snapshot = await db.collection('posts').get();
  
  const stats = {
    total: 0,
    byCategory: {},
    byMediaType: {},
    reelsMissingVideoType: [],
    videoMissingReelsCategory: [],
    reelsCount: 0
  };

  snapshot.forEach(doc => {
    const data = doc.data();
    stats.total++;
    
    const cat = (data.category || 'none').toLowerCase();
    const type = (data.mediaType || 'none').toLowerCase();
    
    stats.byCategory[cat] = (stats.byCategory[cat] || 0) + 1;
    stats.byMediaType[type] = (stats.byMediaType[type] || 0) + 1;
    
    if (cat === 'reels') {
      stats.reelsCount++;
      if (type !== 'video') {
        stats.reelsMissingVideoType.push({ id: doc.id, type });
      }
    }
    
    if (type === 'video' && cat !== 'reels') {
      stats.videoMissingReelsCategory.push({ id: doc.id, cat });
    }
  });

  console.log('Total Posts:', stats.total);
  console.log('Reels (Category):', stats.reelsCount);
  console.log('By Category Summary:', stats.byCategory);
  console.log('By Media Type Summary:', stats.byMediaType);
  console.log('Reels (Category) but NOT "video" type:', stats.reelsMissingVideoType.length);
  console.log('Video type but NOT "reels" category:', stats.videoMissingReelsCategory.length);
  
  if (stats.reelsMissingVideoType.length > 0) {
    console.log('Sample IDs (Reels missing video type):', stats.reelsMissingVideoType.slice(0, 5));
  }
  
  if (stats.videoMissingReelsCategory.length > 0) {
    console.log('Sample IDs (Video but not Reels category):', stats.videoMissingReelsCategory.slice(0, 5));
  }

  process.exit(0);
}

runAudit().catch(console.error);
