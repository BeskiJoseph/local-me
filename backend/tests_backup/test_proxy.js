import fetch from 'node-fetch'; // Not needed in Node 18+, but let's see if they use it
// Actually Node 24 HAS fetch.

async function test() {
    const url = 'https://media-proxy.beskijosphjr.workers.dev/posts/kwDX89bhAcaa1qVABrSPiX0Dypt1/kwDX89bhAcaa1qVABrSPiX0Dypt1_1774117195571/images/6548b6a1-843f-4e9f-bae0-1910c4eef9bf.jpg';
    try {
        console.log('Fetching:', url);
        const response = await fetch(url, {
            headers: { 'User-Agent': 'LocalMe-Backend-Proxy/1.0' },
            signal: AbortSignal.timeout(15000),
        });
        console.log('Status:', response.status);
        console.log('OK:', response.ok);
    } catch (err) {
        console.error('Fetch Error:', err.message);
        console.error('Error Name:', err.name);
        console.error('Error Code:', err.code);
    }
}

test();
