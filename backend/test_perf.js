const API_URL = 'http://localhost:4001';
const TOKEN = 'PERF_TEST_TOKEN';

const headers = {
    'Authorization': `Bearer ${TOKEN}`,
    'Content-Type': 'application/json'
};

const tests = [
    { name: 'Trending Feed (Global)', url: '/api/posts?feedType=global&limit=20' },
    { name: 'Nearby Feed (Local)', url: '/api/posts?feedType=local&lat=13.0827&lng=80.2707&limit=20' },
    { name: 'Search Posts', url: '/api/search?q=good&type=posts&limit=20' },
    { name: 'Search Users', url: '/api/search?q=beski&type=users&limit=20' },
];

async function runTests() {
    console.log(`🚀 PERFORMANCE FETCHING TEST (ms)`);
    console.log(`=============================`);

    for (const test of tests) {
        const start = Date.now();
        try {
            const resp = await fetch(`${API_URL}${test.url}`, { headers });
            const data = await resp.json();
            const duration = Date.now() - start;
            if (!resp.ok) {
                console.log(`❌ ${test.name.padEnd(25)}: HTTP ${resp.status} - ${data.error || 'Unknown Error'}`);
                continue;
            }
            const count = data.data ? (Array.isArray(data.data) ? data.data.length : 1) : 0;
            console.log(`✅ ${test.name.padEnd(25)}: ${duration.toString().padStart(4)}ms (Count: ${count})`);
        } catch (e) {
            console.log(`❌ ${test.name.padEnd(25)}: FAILED (${e.message})`);
        }
    }

    console.log(`=============================`);
    console.log(`Done.`);
}

runTests();
