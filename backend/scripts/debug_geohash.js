import ngeohash from 'ngeohash';

const lat = 13.0827;
const lng = 80.2707;

console.log('Chennai (13.0827, 80.2707)');
console.log('P4:', ngeohash.encode(lat, lng, 4));
console.log('P5:', ngeohash.encode(lat, lng, 5));
console.log('P6:', ngeohash.encode(lat, lng, 6));

const torontoLat = 43.6532;
const torontoLng = -79.3832;
console.log('\nToronto (43.6532, -79.3832)');
console.log('P4:', ngeohash.encode(torontoLat, torontoLng, 4));
console.log('P5:', ngeohash.encode(torontoLat, torontoLng, 5));
console.log('P6:', ngeohash.encode(torontoLat, torontoLng, 6));
