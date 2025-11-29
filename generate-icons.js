// Generate macOS app icon PNGs from SVG
// Usage: node generate-icons.js
// Requires: npm install sharp

const sharp = require('sharp');
const path = require('path');
const fs = require('fs');

const SVG_SOURCE = path.join(__dirname, 'AppIcon.svg');
const OUTPUT_DIR = path.join(__dirname, 'MiddleDrag', 'Assets.xcassets', 'AppIcon.appiconset');

// macOS icon sizes: [actual pixels, filename]
const SIZES = [
    [16, 'icon_16x16.png'],
    [32, 'icon_16x16@2x.png'],
    [32, 'icon_32x32.png'],
    [64, 'icon_32x32@2x.png'],
    [128, 'icon_128x128.png'],
    [256, 'icon_128x128@2x.png'],
    [256, 'icon_256x256.png'],
    [512, 'icon_256x256@2x.png'],
    [512, 'icon_512x512.png'],
    [1024, 'icon_512x512@2x.png'],
];

async function generateIcons() {
    // Check if source exists
    if (!fs.existsSync(SVG_SOURCE)) {
        console.error(`Error: ${SVG_SOURCE} not found`);
        process.exit(1);
    }

    // Create output directory if needed
    if (!fs.existsSync(OUTPUT_DIR)) {
        fs.mkdirSync(OUTPUT_DIR, { recursive: true });
    }

    console.log('Generating icons...\n');

    for (const [size, filename] of SIZES) {
        const outputPath = path.join(OUTPUT_DIR, filename);
        
        await sharp(SVG_SOURCE)
            .resize(size, size)
            .png()
            .toFile(outputPath);
        
        console.log(`✓ ${filename} (${size}x${size})`);
    }

    console.log(`\nDone! Icons saved to:\n${OUTPUT_DIR}`);
}

generateIcons().catch(err => {
    console.error('Error:', err.message);
    process.exit(1);
});
