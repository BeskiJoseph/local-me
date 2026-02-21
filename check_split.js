const fs = require('fs');
const path = require('path');
const routesDir = path.join(__dirname, 'backend', 'src', 'routes');

let issues = 0;
fs.readdirSync(routesDir).forEach(file => {
    if (file.endsWith('.js')) {
        const filePath = path.join(routesDir, file);
        const content = fs.readFileSync(filePath, 'utf8');
        const lines = content.split(/\r?\n/);
        lines.forEach((line, index) => {
            const trimmed = line.trim();
            if (trimmed === 'return') {
                const nextLine = lines[index + 1] ? lines[index + 1].trim() : '';
                if (nextLine.startsWith('res.') || nextLine.startsWith('next(')) {
                    console.log(`SPLIT DETECTED in ${file}:${index + 1}`);
                    console.log(`  Line ${index + 1}: ${line}`);
                    console.log(`  Line ${index + 2}: ${lines[index + 1]}`);
                    issues++;
                }
            }
        });
    }
});

if (issues === 0) {
    console.log("No split returns found. All 'return' statements are correctly followed on the same line or not split from their responses.");
} else {
    console.log(`Found ${issues} issues.`);
}
