const API_URL = 'http://localhost:4001';
const TOKEN = 'PERF_TEST_TOKEN';

const headers = {
    'Authorization': `Bearer ${TOKEN}`,
    'Content-Type': 'application/json'
};

async function check() {
    try {
        const resp = await fetch(`${API_URL}/api/search?q=good&type=posts&limit=20`, { headers });
        const data = await resp.json();
        if (!resp.ok) {
            console.log('ERROR:', JSON.stringify(data.error, null, 2));
        } else {
            console.log('SUCCESS');
        }
    } catch (e) {
        console.log('FETCH FAILED:', e.message);
    }
}

check();
