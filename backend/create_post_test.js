const API_URL = 'http://localhost:4000';
const TOKEN = 'PERF_TEST_TOKEN';

const headers = {
    'Authorization': `Bearer ${TOKEN}`,
    'Content-Type': 'application/json'
};

const postData = {
    title: "Perf Test Post",
    body: "Testing performance with real data",
    location: {
        lat: 13.0827,
        lng: 80.2707,
        name: "Chennai Test Hub"
    },
    isEvent: false
};

async function createPost() {
    try {
        const resp = await fetch(`${API_URL}/api/posts`, {
            method: 'POST',
            headers,
            body: JSON.stringify(postData)
        });
        const data = await resp.json();
        console.log(`✅ Post Created: ID = ${data.id || 'unknown'}`);
        process.exit(0);
    } catch (e) {
        console.error(`❌ Failed: ${e.message}`);
        process.exit(1);
    }
}

createPost();
