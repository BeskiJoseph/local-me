import admin from 'firebase-admin';
import dotenv from 'dotenv';

dotenv.config();

function cleanKey(key) {
    if (!key) return key;
    return key.trim().replace(/^["']|["']$/g, '').replace(/\\n/g, '\n');
}

async function inspectDocs() {
  admin.initializeApp({
    credential: admin.credential.cert({
      projectId: process.env.FIREBASE_PROJECT_ID,
      privateKey: cleanKey(process.env.FIREBASE_PRIVATE_KEY),
      clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
    }),
  });

  const db = admin.firestore();
  const ids = ['IGYgD6AJX2P9DZVKx9Yo', 'R0D8gBZnbFjiASBmKHah', 'VyqEXCQ0mbb0MVD7kQLf'];
  
  for (const id of ids) {
    const doc = await db.collection('posts').doc(id).get();
    const data = doc.data();
    console.log(`Document ID: ${id}`);
    console.log(`  Category: ${data.category}`);
    console.log(`  MediaType: ${data.mediaType}`);
    console.log(`  MediaUrl: ${data.mediaUrl}`);
    console.log('-------------------');
  }
  process.exit(0);
}

inspectDocs();
