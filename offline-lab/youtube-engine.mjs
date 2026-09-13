import { createWriteStream } from 'node:fs';
import { mkdir, rename, rm, writeFile } from 'node:fs/promises';
import { Readable, Transform } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import path from 'node:path';
import { YoutubeTranscript } from 'youtube-transcript';
import { Innertube, UniversalCache } from 'youtubei.js';

const DOWNLOAD_CLIENTS = ['ANDROID', 'TV', 'TV_SIMPLY'];

export function extractVideoId(input) {
  const value = input.trim();

  if (/^[\w-]{11}$/.test(value)) {
    return value;
  }

  let url;
  try {
    url = new URL(value);
  } catch {
    throw new Error('Informe um link válido do YouTube ou o ID do vídeo.');
  }

  if (url.hostname === 'youtu.be') {
    const id = url.pathname.split('/').filter(Boolean)[0];
    if (id) return id;
  }

  if (url.hostname.endsWith('youtube.com')) {
    const id = url.searchParams.get('v');
    if (id) return id;

    const parts = url.pathname.split('/').filter(Boolean);
    if (['shorts', 'embed', 'live'].includes(parts[0]) && parts[1]) {
      return parts[1];
    }
  }

  throw new Error('Não consegui identificar o vídeo nesse link.');
}

function formatSrtTime(milliseconds) {
  const value = Math.max(0, Math.round(milliseconds));
  const hours = Math.floor(value / 3_600_000);
  const minutes = Math.floor((value % 3_600_000) / 60_000);
  const seconds = Math.floor((value % 60_000) / 1_000);
  const millis = value % 1_000;

  return [hours, minutes, seconds]
    .map((part) => String(part).padStart(2, '0'))
    .join(':') + `,${String(millis).padStart(3, '0')}`;
}

function transcriptToSrt(items) {
  return items.map((item, index) => {
    const start = Number(item.offset || 0);
    const end = start + Math.max(Number(item.duration || 0), 250);
    return `${index + 1}\n${formatSrtTime(start)} --> ${formatSrtTime(end)}\n${item.text.trim()}\n`;
  }).join('\n');
}

async function fetchEnglishTranscript(videoId) {
  const attempts = [
    () => YoutubeTranscript.fetchTranscript(videoId, { lang: 'en' }),
    () => YoutubeTranscript.fetchTranscript(videoId),
  ];
  const errors = [];

  for (const attempt of attempts) {
    try {
      const items = await attempt();
      if (items.length > 0) return items;
    } catch (error) {
      errors.push(error.message);
    }
  }

  throw new Error(`Não encontrei legenda para este vídeo. ${errors.join(' | ')}`);
}

function qualityHeight(qualityLabel) {
  const match = String(qualityLabel || '').match(/(\d+)p/);
  return match ? Number(match[1]) : 0;
}

function selectProgressiveMp4(formats, requestedQuality) {
  const maximumHeight = qualityHeight(requestedQuality) || 360;
  const candidates = formats
    .filter((format) => format.has_audio && format.has_video)
    .filter((format) => format.mime_type?.startsWith('video/mp4'))
    .filter((format) => qualityHeight(format.quality_label) <= maximumHeight)
    .sort((left, right) => qualityHeight(right.quality_label) - qualityHeight(left.quality_label));

  return candidates[0] || null;
}

async function findDownloadFormat(innertube, videoId, requestedQuality) {
  const errors = [];

  for (const client of DOWNLOAD_CLIENTS) {
    try {
      const info = await innertube.getBasicInfo(videoId, { client });
      const format = selectProgressiveMp4(info.streaming_data?.formats || [], requestedQuality);
      if (format) return { client, format, info };
      errors.push(`${client}: nenhum MP4 progressivo compatível`);
    } catch (error) {
      errors.push(`${client}: ${error.message}`);
    }
  }

  throw new Error(`Não encontrei formato com áudio e vídeo juntos. ${errors.join(' | ')}`);
}

async function writeWebStream(stream, destination, totalBytes, onProgress) {
  let downloadedBytes = 0;
  const progressStream = new Transform({
    transform(chunk, encoding, callback) {
      downloadedBytes += chunk.length;
      onProgress?.({
        downloadedBytes,
        totalBytes,
        progress: totalBytes > 0 ? Math.min(100, Math.round((downloadedBytes / totalBytes) * 100)) : null,
      });
      callback(null, chunk);
    },
  });

  await pipeline(Readable.fromWeb(stream), progressStream, createWriteStream(destination));
}

export async function createYoutubeEngine(options = {}) {
  const cacheDirectory = options.cacheDirectory
    ? path.resolve(options.cacheDirectory)
    : undefined;

  if (cacheDirectory) {
    await mkdir(cacheDirectory, { recursive: true });
  }

  const innertube = await Innertube.create({
    cache: new UniversalCache(true, cacheDirectory),
    generate_session_locally: true,
  });

  return {
    async probe(input, quality = '360p') {
      const videoId = extractVideoId(input);
      const transcript = await fetchEnglishTranscript(videoId);
      const { client, format, info } = await findDownloadFormat(innertube, videoId, quality);
      const probeStream = await innertube.download(videoId, {
        client,
        itag: format.itag,
        range: { start: 0, end: 65_535 },
      });
      const reader = probeStream.getReader();
      let downloadedBytes = 0;

      while (downloadedBytes < 65_536) {
        const { done, value } = await reader.read();
        if (done) break;
        downloadedBytes += value.byteLength;
      }
      await reader.cancel();

      return {
        videoId,
        title: info.basic_info.title,
        durationSeconds: info.basic_info.duration,
        client,
        itag: format.itag,
        quality: format.quality_label,
        contentLength: Number(format.content_length || 0),
        transcriptSegments: transcript.length,
        downloadedBytes,
      };
    },

    async download(input, options = {}) {
      const videoId = extractVideoId(input);
      const quality = options.quality || '360p';
      const libraryDir = path.resolve(options.libraryDir || path.join(process.cwd(), 'offline-lab', 'library'));
      const videoDir = path.join(libraryDir, videoId);
      const videoPath = path.join(videoDir, 'video.mp4');
      const partialVideoPath = `${videoPath}.part`;

      await mkdir(videoDir, { recursive: true });

      try {
        options.onProgress?.({ stage: 'captions', message: 'Baixando legenda em inglês...' });
        const transcript = await fetchEnglishTranscript(videoId);
        await writeFile(path.join(videoDir, 'captions.en.srt'), transcriptToSrt(transcript));
        await writeFile(path.join(videoDir, 'captions.raw.json'), JSON.stringify(transcript, null, 2));

        options.onProgress?.({ stage: 'video-info', message: 'Preparando o vídeo...' });
        const { client, format, info } = await findDownloadFormat(innertube, videoId, quality);

        options.onProgress?.({
          stage: 'video',
          message: `Baixando vídeo ${format.quality_label || quality}...`,
          totalBytes: Number(format.content_length || 0),
        });

        const stream = await innertube.download(videoId, {
          client,
          itag: format.itag,
        });
        const totalBytes = Number(format.content_length || 0);
        await writeWebStream(stream, partialVideoPath, totalBytes, (progress) => {
          options.onProgress?.({
            stage: 'video',
            message: progress.progress === null
              ? 'Baixando vídeo...'
              : `Baixando vídeo... ${progress.progress}%`,
            ...progress,
          });
        });
        await rename(partialVideoPath, videoPath);

        const metadata = {
          schemaVersion: 1,
          videoId,
          sourceUrl: `https://www.youtube.com/watch?v=${videoId}`,
          title: info.basic_info.title,
          author: info.basic_info.author,
          durationSeconds: info.basic_info.duration,
          thumbnail: info.basic_info.thumbnail?.at(-1)?.url || null,
          downloadedAt: new Date().toISOString(),
          format: {
            client,
            itag: format.itag,
            quality: format.quality_label,
            mimeType: format.mime_type,
            contentLength: Number(format.content_length || 0),
          },
          files: {
            video: 'video.mp4',
            captions: 'captions.en.srt',
            rawCaptions: 'captions.raw.json',
          },
        };

        await writeFile(path.join(videoDir, 'metadata.json'), JSON.stringify(metadata, null, 2));
        options.onProgress?.({ stage: 'done', message: 'Download concluído.' });

        return { directory: videoDir, metadata };
      } catch (error) {
        await rm(partialVideoPath, { force: true });
        throw error;
      }
    },
  };
}
