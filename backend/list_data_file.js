import { db } from './src/config/firebase.js';
import fs from 'fs';

async function listData() {
    try {
        const posts = await db.collection('posts').limit(10).get();
        let out = `Posts found: ${posts.size}\n`;
        posts.docs.forEach(doc => {
            const d = doc.data();
            out += `- ID: ${doc.id}\n`;
            out += `  Status: "${d.status}"\n`;
            out += `  Visibility: "${d.visibility}"\n`;
            out += `  CreatedAt: ${d.createdAt ? d.createdAt.toDate().toISOString() : 'null'}\n`;
        });
        fs.writeFileSync('db_inspect.txt', out);
        process.exit(0);
    } catch (e) {
        fs.writeFileSync('db_inspect.txt', e.toString());
        process.exit(1);
    }
}

listData();
