import { createYoutubeEngine } from './youtube-engine.mjs';
import path from 'node:path';

const input = process.argv[2];
const quality = process.argv[3] || '360p';

if (!input) {
  console.error('Uso: npm run download -- LINK_OU_VIDEO_ID [360p]');
  process.exit(1);
}

const engine = await createYoutubeEngine();
const result = await engine.download(input, {
  quality,
  libraryDir: path.join(import.meta.dirname, 'library'),
  onProgress(event) {
    console.log(`[${event.stage}] ${event.message}`);
  },
});

console.log(JSON.stringify(result, null, 2));
