import { createYoutubeEngine } from './youtube-engine.mjs';

const input = process.argv[2];
const quality = process.argv[3] || '360p';

if (!input) {
  console.error('Uso: npm run probe -- LINK_OU_VIDEO_ID [360p]');
  process.exit(1);
}

const engine = await createYoutubeEngine();
console.log(JSON.stringify(await engine.probe(input, quality), null, 2));
