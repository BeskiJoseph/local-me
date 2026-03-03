const API_URL = 'http://localhost:4001';
const TOKEN = 'PERF_TEST_TOKEN';

const headers = {
    'Authorization': `Bearer ${TOKEN}`,
    'Content-Type': 'application/json'
};

async function runTest(name, url, iterations = 3) {
    console.log(`\n--- Testing ${name} ---`);
    for (let i = 1; i <= iterations; i++) {
        const start = Date.now();
        try {
            const resp = await fetch(`${API_URL}${url}`, { headers });
            const data = await resp.json();
            const duration = Date.now() - start;
            if (!resp.ok) {
                console.log(`  [${i}] HTTP ${resp.status}: ${duration}ms`);
            } else {
                const count = data.data ? (Array.isArray(data.data) ? data.data.length : 1) : 0;
                console.log(`  [${i}] SUCCESS: ${duration}ms (Count: ${count})`);
            }
        } catch (e) {
            console.log(`  [${i}] FAILED: ${e.message}`);
        }
    }
}

async function main() {
    console.log(`🚀 DETAILED PERFORMANCE PROFILE`);
    console.log(`=============================`);

    await runTest('Global Trending', '/api/posts?feedType=global&limit=20');
    await runTest('Local Nearby', '/api/posts?feedType=local&lat=13.0827&lng=80.2707&limit=20');
    await runTest('Search Posts', '/api/search?q=good&type=posts&limit=20');

    console.log(`\n=============================`);
    console.log(`Done.`);
}

main();
