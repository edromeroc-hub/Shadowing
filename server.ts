import express from "express";
import path from "path";
import { YoutubeTranscript } from "youtube-transcript";
import { GoogleGenAI, Type, Schema } from "@google/genai";
import { ProxyAgent } from "undici";
import dotenv from "dotenv";
import { readdir, readFile, writeFile } from "node:fs/promises";
import { readFileSync } from "node:fs";
import { createYoutubeEngine } from "./offline-lab/youtube-engine.mjs";
import { createCommercialBackend } from "./server/commercialBackend";

dotenv.config({ path: process.env.SHADOWING_ENV_FILE || undefined });

const geminiModel = process.env.GEMINI_MODEL?.trim() || "gemini-2.5-flash";
const geminiSegmentationEnabled = process.env.GEMINI_SEGMENTATION_ENABLED?.trim().toLowerCase() !== "false";
const runtimeSettingsPath = process.env.SHADOWING_SETTINGS_FILE?.trim();
let geminiApiKey = process.env.GEMINI_API_KEY?.trim() || "";

if (runtimeSettingsPath) {
  try {
    const savedSettings = JSON.parse(readFileSync(runtimeSettingsPath, "utf8"));
    geminiApiKey = String(savedSettings.geminiApiKey || geminiApiKey).trim();
  } catch {
  }
}

let ai: GoogleGenAI | null = geminiApiKey ? new GoogleGenAI({ apiKey: geminiApiKey }) : null;
const youtubeProxyUrl = process.env.YOUTUBE_PROXY_URL;
const youtubeProxyAgent = youtubeProxyUrl ? new ProxyAgent(youtubeProxyUrl) : null;
const appRootDir = process.env.SHADOWING_APP_ROOT || process.cwd();
const offlineLibraryDir = process.env.SHADOWING_DATA_DIR || path.join(appRootDir, "offline-lab", "library");

type OfflineDownloadJob = {
  videoId: string;
  status: "downloading" | "ready" | "error";
  stage?: string;
  message?: string;
  progress?: number | null;
  error?: string;
  metadata?: Record<string, unknown>;
};

const offlineDownloadJobs = new Map<string, OfflineDownloadJob>();
let offlineEnginePromise: ReturnType<typeof createYoutubeEngine> | null = null;

function getOfflineEngine() {
  offlineEnginePromise ||= createYoutubeEngine({
    cacheDirectory: path.join(offlineLibraryDir, ".youtube-cache"),
  });
  return offlineEnginePromise;
}

function isValidVideoId(videoId: string) {
  return /^[\w-]{11}$/.test(videoId);
}

async function readOfflineVideoMetadata(videoId: string) {
  if (!isValidVideoId(videoId)) return null;

  try {
    return JSON.parse(await readFile(path.join(offlineLibraryDir, videoId, "metadata.json"), "utf8"));
  } catch {
    return null;
  }
}

async function listOfflineVideos() {
  try {
    const entries = await readdir(offlineLibraryDir, { withFileTypes: true });
    const metadata = await Promise.all(
      entries
        .filter((entry) => entry.isDirectory() && isValidVideoId(entry.name))
        .map((entry) => readOfflineVideoMetadata(entry.name))
    );
    return metadata.filter(Boolean);
  } catch {
    return [];
  }
}

async function ensureOfflineLesson(videoId: string) {
  const lessonPath = path.join(offlineLibraryDir, videoId, "lesson.ai.v4.json");
  try {
    return JSON.parse(await readFile(lessonPath, "utf8"));
  } catch {
    const rawCaptions = JSON.parse(
      await readFile(path.join(offlineLibraryDir, videoId, "captions.raw.json"), "utf8")
    );
    const transcriptSegments = normalizeTranscriptSegments(
      rawCaptions.map((item: { text: string; offset: number; duration: number }) => ({
        text: item.text,
        start: Number(item.offset || 0) / 1000,
        end: (Number(item.offset || 0) + Math.max(Number(item.duration || 0), 250)) / 1000,
      }))
    );

    try {
      const previousLesson = JSON.parse(
        await readFile(path.join(offlineLibraryDir, videoId, "lesson.ai.v3.json"), "utf8")
      );
      const realignedLesson = realignShadowingLessonTimings(previousLesson, transcriptSegments);
      await writeFile(lessonPath, JSON.stringify(realignedLesson, null, 2));
      return realignedLesson;
    } catch {
    }

    let lesson;

    try {
      console.log(`[offline-lesson] AI segmentation started (${videoId})`, { segments: transcriptSegments.length });
      lesson = await buildAiShadowingTranscript(transcriptSegments);
      console.log(`[offline-lesson] AI segmentation completed (${videoId})`, { phrases: lesson.length });
    } catch (error: any) {
      console.warn(`Offline lesson AI segmentation failed (${videoId}):`, error.message);
      const groupedPhrases = groupSegmentsForShadowing(transcriptSegments);
      try {
        lesson = await enrichTranscript(groupedPhrases);
      } catch (enrichmentError: any) {
        console.warn(`Offline lesson enrichment failed (${videoId}):`, enrichmentError.message);
        lesson = toBasicPhrases(groupedPhrases);
      }
    }

    const stabilizedLesson = stabilizeShadowingLessonTimings(lesson);
    await writeFile(lessonPath, JSON.stringify(stabilizedLesson, null, 2));
    return stabilizedLesson;
  }
}

type TranscriptSegment = {
  text: string;
  start: number;
  end: number;
};

type CaptionTrack = {
  baseUrl: string;
  name?: { simpleText?: string; runs?: { text: string }[] };
  languageCode?: string;
  kind?: string;
  vssId?: string;
};

type VideoRecommendation = {
  id: string;
  title: string;
  channel: string;
  difficulty: string;
  thumbnail: string;
  duration?: string;
};

const SHADOWING_LEAD_IN_SECONDS = 0.18;
const SHADOWING_TRAILING_SECONDS = 0.32;
const SHADOWING_MAX_SECONDS = 8;
const SHADOWING_MAX_CHARS = 160;
const SHADOWING_MIN_SECONDS = 0.55;
const SHADOWING_MIN_IDEAL_SECONDS = 1.4;
const SHADOWING_MIN_WORDS = 4;
const SHADOWING_MAX_AI_PHRASES = 60;

const ENRICHED_TRANSCRIPT_SCHEMA: Schema = {
  type: Type.ARRAY,
  description: "List of enriched transcript phrases",
  items: {
    type: Type.OBJECT,
    properties: {
      text: { type: Type.STRING, description: "The original English text" },
      translation: { type: Type.STRING, description: "Portuguese (PT-BR) translation" },
      start: { type: Type.NUMBER, description: "Start time in seconds" },
      end: { type: Type.NUMBER, description: "End time in seconds" },
    },
    required: ["text", "translation", "start", "end"],
  },
};

const AI_SHADOWING_SEGMENTS_SCHEMA: Schema = {
  type: Type.ARRAY,
  description: "Best shadowing practice clips selected from the full YouTube transcript",
  items: {
    type: Type.OBJECT,
    properties: {
      text: { type: Type.STRING, description: "Natural English phrase for shadowing" },
      translation: { type: Type.STRING, description: "Portuguese (PT-BR) translation" },
      start: { type: Type.NUMBER, description: "Clip start time in seconds" },
      end: { type: Type.NUMBER, description: "Clip end time in seconds" },
    },
    required: ["text", "translation", "start", "end"],
  },
};

function decodeHtmlEntities(value: string) {
  const namedEntities: Record<string, string> = {
    amp: "&",
    apos: "'",
    gt: ">",
    lt: "<",
    nbsp: " ",
    quot: "\"",
  };

  return value.replace(/&(#x?[0-9a-fA-F]+|[a-zA-Z]+);/g, (_, entity) => {
    if (entity.startsWith("#x")) {
      return String.fromCodePoint(parseInt(entity.slice(2), 16));
    }
    if (entity.startsWith("#")) {
      return String.fromCodePoint(parseInt(entity.slice(1), 10));
    }
    return namedEntities[entity] ?? `&${entity};`;
  });
}

function cleanTranscriptText(value: string) {
  return decodeHtmlEntities(value)
    .replace(/<[^>]*>/g, " ")
    .replace(/\[[^\]]+\]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function youtubeFetch(input: Parameters<typeof fetch>[0], init: Parameters<typeof fetch>[1] = {}) {
  if (!youtubeProxyAgent) return fetch(input, init);
  return fetch(input, {
    ...init,
    dispatcher: youtubeProxyAgent,
  } as Parameters<typeof fetch>[1] & { dispatcher: ProxyAgent });
}

function normalizeTranscriptSegments(segments: TranscriptSegment[]) {
  return segments
    .map((segment) => ({
      text: cleanTranscriptText(segment.text),
      start: Number(segment.start.toFixed(3)),
      end: Number(segment.end.toFixed(3)),
    }))
    .filter((segment) => segment.text && Number.isFinite(segment.start) && Number.isFinite(segment.end) && segment.end > segment.start)
    .sort((a, b) => a.start - b.start);
}

function makeSequentialSegments(segments: TranscriptSegment[]) {
  return segments.map((segment, index) => {
    const next = segments[index + 1];
    const nextStart = next?.start;
    const hasUsefulNextStart = Number.isFinite(nextStart) && nextStart > segment.start + 0.25;
    const end = hasUsefulNextStart ? Math.min(segment.end, nextStart) : segment.end;

    return {
      ...segment,
      end: Number(Math.max(end, segment.start + 0.35).toFixed(3)),
    };
  });
}

function splitTextIntoClauses(text: string) {
  const clauses = text.match(/[^,.;:!?]+[,.;:!?]+(?:["')\]]+)?|[^,.;:!?]+$/g) || [text];
  return clauses.map((clause) => clause.trim()).filter(Boolean);
}

function splitSegmentByPunctuation(segment: TranscriptSegment) {
  const clauses = splitTextIntoClauses(segment.text);
  if (clauses.length <= 1) return [segment];

  const totalWeight = clauses.reduce((sum, clause) => sum + Math.max(clause.length, 1), 0);
  const duration = segment.end - segment.start;
  let elapsed = 0;

  return clauses.map((clause, index) => {
    const weight = Math.max(clause.length, 1);
    const start = segment.start + (duration * elapsed / totalWeight);
    elapsed += weight;
    const end = index === clauses.length - 1
      ? segment.end
      : segment.start + (duration * elapsed / totalWeight);

    return {
      text: clause,
      start: Number(start.toFixed(3)),
      end: Number(Math.max(end, start + 0.25).toFixed(3)),
    };
  });
}

function endsAtNaturalPause(text: string) {
  return /[,.;:!?]["')\]]?$/.test(text.trim());
}

function countSpokenWords(text: string) {
  return text
    .replace(/[^\w\s'-]/g, " ")
    .split(/\s+/)
    .filter(Boolean)
    .length;
}

function isTooShortForShadowing(phrase: TranscriptSegment) {
  const text = phrase.text.trim().toLowerCase();
  const duration = phrase.end - phrase.start;
  const fillerOnly = /^(ok(?:ay)?|yeah|yes|no|right|well|so|uh|um|hmm|all right)[,.!? ]*$/i.test(text);

  return (
    fillerOnly ||
    countSpokenWords(text) < SHADOWING_MIN_WORDS ||
    duration < SHADOWING_MIN_IDEAL_SECONDS
  );
}

function applyShadowingBuffer(phrases: TranscriptSegment[]) {
  return phrases.map((phrase, index) => {
    const previous = phrases[index - 1];
    const next = phrases[index + 1];
    const bufferedStart = Math.max(previous?.end ?? 0, phrase.start - SHADOWING_LEAD_IN_SECONDS);
    const bufferedEnd = Math.min(next?.start ?? phrase.end + SHADOWING_TRAILING_SECONDS, phrase.end + SHADOWING_TRAILING_SECONDS);

    return {
      ...phrase,
      start: Number(bufferedStart.toFixed(3)),
      end: Number(Math.max(bufferedEnd, bufferedStart + SHADOWING_MIN_SECONDS).toFixed(3)),
    };
  });
}

function groupSegmentsForShadowing(segments: TranscriptSegment[]) {
  const normalized = makeSequentialSegments(normalizeTranscriptSegments(segments))
    .flatMap(splitSegmentByPunctuation);
  const phrases: TranscriptSegment[] = [];
  let current: TranscriptSegment | null = null;

  for (const segment of normalized) {
    if (!current) {
      current = { ...segment };
      continue;
    }

    const gap = segment.start - current.end;
    const combinedText = `${current.text} ${segment.text}`.trim();
    const combinedDuration = segment.end - current.start;
    const currentTooShort = isTooShortForShadowing(current);
    const shouldMerge =
      gap <= (currentTooShort ? 1.8 : 1.1) &&
      combinedDuration <= SHADOWING_MAX_SECONDS &&
      combinedText.length <= SHADOWING_MAX_CHARS &&
      (currentTooShort || !endsAtNaturalPause(current.text));

    if (shouldMerge) {
      current = {
        text: combinedText,
        start: current.start,
        end: segment.end,
      };
    } else {
      phrases.push(current);
      current = { ...segment };
    }
  }

  if (current) {
    phrases.push(current);
  }

  const repairedPhrases = mergeShortShadowingPhrases(phrases);

  return applyShadowingBuffer(repairedPhrases)
    .filter((phrase) => phrase.end - phrase.start >= SHADOWING_MIN_SECONDS)
    .slice(0, 60);
}

function mergeShortShadowingPhrases(phrases: TranscriptSegment[]) {
  const repaired: TranscriptSegment[] = [];

  for (const phrase of phrases) {
    const previous = repaired[repaired.length - 1];
    const canMergePrevious =
      previous &&
      phrase.end - previous.start <= SHADOWING_MAX_SECONDS &&
      `${previous.text} ${phrase.text}`.length <= SHADOWING_MAX_CHARS &&
      phrase.start - previous.end <= 1.8;

    if (canMergePrevious && (isTooShortForShadowing(previous) || isTooShortForShadowing(phrase))) {
      repaired[repaired.length - 1] = {
        text: `${previous.text} ${phrase.text}`.replace(/\s+/g, " ").trim(),
        start: previous.start,
        end: phrase.end,
      };
      continue;
    }

    repaired.push({ ...phrase });
  }

  return repaired.filter((phrase) => !isTooShortForShadowing(phrase) || phrase.end - phrase.start >= SHADOWING_MIN_IDEAL_SECONDS);
}

function isUsableGeminiKey() {
  if (!geminiApiKey) return false;
  const lowerKey = geminiApiKey.toLowerCase();
  return !["dummy", "my_gemini_api_key", "your_gemini_api_key"].includes(lowerKey);
}

function configureGeminiApiKey(apiKey: string) {
  geminiApiKey = apiKey.trim();
  ai = geminiApiKey ? new GoogleGenAI({ apiKey: geminiApiKey }) : null;
}

function toBasicPhrases(transcriptData: TranscriptSegment[]) {
  return transcriptData.map((phrase) => ({
    ...phrase,
    translation: "",
  }));
}

function extractJsonObjectAfter(html: string, marker: string) {
  const markerIndex = html.indexOf(marker);
  if (markerIndex === -1) return null;

  const start = html.indexOf("{", markerIndex);
  if (start === -1) return null;

  let depth = 0;
  let inString = false;
  let escaped = false;

  for (let index = start; index < html.length; index += 1) {
    const char = html[index];

    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (char === "\\") {
        escaped = true;
      } else if (char === "\"") {
        inString = false;
      }
      continue;
    }

    if (char === "\"") {
      inString = true;
    } else if (char === "{") {
      depth += 1;
    } else if (char === "}") {
      depth -= 1;
      if (depth === 0) {
        return html.slice(start, index + 1);
      }
    }
  }

  return null;
}

function getTrackLabel(track: CaptionTrack) {
  return track.name?.simpleText || track.name?.runs?.map((run) => run.text).join("") || "";
}

function pickBestCaptionTrack(tracks: CaptionTrack[]) {
  const englishTracks = tracks.filter((track) =>
    track.languageCode?.toLowerCase().startsWith("en") ||
    track.vssId?.toLowerCase().includes(".en") ||
    getTrackLabel(track).toLowerCase().includes("english")
  );

  const candidates = englishTracks.length > 0 ? englishTracks : tracks;
  return (
    candidates.find((track) => track.kind === "asr") ||
    candidates.find((track) => !track.kind) ||
    candidates[0]
  );
}

async function getCaptionTracksFromYouTubei(videoId: string) {
  const clientVersion = "20.10.38";
  const response = await youtubeFetch("https://www.youtube.com/youtubei/v1/player?prettyPrint=false", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "User-Agent": `com.google.android.youtube/${clientVersion} (Linux; U; Android 14)`,
    },
    body: JSON.stringify({
      context: {
        client: {
          clientName: "ANDROID",
          clientVersion,
        },
      },
      videoId
    }),
  });

  if (!response.ok) {
    throw new Error(`YouTubei player request failed: ${response.status}`);
  }

  const data = await response.json();
  return data.captions?.playerCaptionsTracklistRenderer?.captionTracks || [];
}

async function getCaptionTracksFromWatchPage(videoId: string) {
  const response = await youtubeFetch(`https://www.youtube.com/watch?v=${videoId}&hl=en`, {
    headers: {
      "Accept-Language": "en-US,en;q=0.9",
      "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
    },
  });

  if (!response.ok) {
    throw new Error(`YouTube watch page request failed: ${response.status}`);
  }

  const html = await response.text();
  const playerResponseJson = extractJsonObjectAfter(html, "ytInitialPlayerResponse");
  if (!playerResponseJson) return [];

  const playerResponse = JSON.parse(playerResponseJson);
  return playerResponse.captions?.playerCaptionsTracklistRenderer?.captionTracks || [];
}

function parseJson3Captions(payload: any) {
  const events = Array.isArray(payload.events) ? payload.events : [];
  return normalizeTranscriptSegments(
    events.flatMap((event: any) => {
      if (!event.segs || event.tStartMs === undefined) return [];

      const text = event.segs.map((segment: any) => segment.utf8 || "").join("");
      const start = Number(event.tStartMs) / 1000;
      const duration = Number(event.dDurationMs || 0) / 1000;
      return [{
        text,
        start,
        end: start + Math.max(duration, 0.5),
      }];
    })
  );
}

function parseXmlCaptions(xml: string) {
  const segments: TranscriptSegment[] = [];

  const paragraphRegex = /<p\s+t="(\d+)"\s+d="(\d+)"[^>]*>([\s\S]*?)<\/p>/g;
  let paragraphMatch;

  while ((paragraphMatch = paragraphRegex.exec(xml))) {
    const startMs = Number(paragraphMatch[1]);
    const durationMs = Number(paragraphMatch[2]);
    const inner = paragraphMatch[3];
    const words = [...inner.matchAll(/<s[^>]*>([^<]*)<\/s>/g)].map((wordMatch) => wordMatch[1]);
    const text = words.length > 0 ? words.join("") : inner.replace(/<[^>]+>/g, "");

    segments.push({
      text,
      start: startMs / 1000,
      end: (startMs + durationMs) / 1000,
    });
  }

  if (segments.length > 0) {
    return normalizeTranscriptSegments(segments);
  }

  const textRegex = /<text\b([^>]*)>([\s\S]*?)<\/text>/g;
  let match;

  while ((match = textRegex.exec(xml))) {
    const attrs = match[1];
    const startMatch = attrs.match(/\bstart="([^"]+)"/);
    const durationMatch = attrs.match(/\bdur="([^"]+)"/);
    if (!startMatch) continue;

    const start = Number(startMatch[1]);
    const duration = Number(durationMatch?.[1] || 2);
    segments.push({
      text: match[2],
      start,
      end: start + duration,
    });
  }

  return normalizeTranscriptSegments(segments);
}

async function fetchSegmentsFromCaptionTrack(track: CaptionTrack) {
  const response = await youtubeFetch(track.baseUrl, {
    headers: {
      "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_4) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/85.0.4183.83 Safari/537.36,gzip(gfe)",
    },
  });
  if (!response.ok) {
    throw new Error(`Caption track request failed: ${response.status}`);
  }

  const raw = await response.text();
  try {
    return parseJson3Captions(JSON.parse(raw));
  } catch {
    return parseXmlCaptions(raw);
  }
}

async function fetchSegmentsWithYoutubeTranscript(videoId: string, lang?: string) {
  const transcriptItems = await YoutubeTranscript.fetchTranscript(videoId, {
    ...(lang ? { lang } : {}),
    fetch: youtubeFetch,
  });
  return normalizeTranscriptSegments(
    transcriptItems.map((item) => ({
      text: item.text,
      start: item.offset / 1000,
      end: (item.offset + item.duration) / 1000,
    }))
  );
}

async function fetchYouTubeTranscriptSegments(videoId: string) {
  const attempts: { source: string; run: () => Promise<TranscriptSegment[]> }[] = [
    {
      source: "youtube-transcript-package",
      run: () => fetchSegmentsWithYoutubeTranscript(videoId, "en"),
    },
    {
      source: "youtube-transcript-package-default",
      run: () => fetchSegmentsWithYoutubeTranscript(videoId),
    },
    {
      source: "youtubei-android",
      run: async () => {
        const tracks = await getCaptionTracksFromYouTubei(videoId);
        const track = pickBestCaptionTrack(tracks);
        if (!track) throw new Error("No caption tracks in YouTubei response");
        return fetchSegmentsFromCaptionTrack(track);
      },
    },
    {
      source: "watch-page",
      run: async () => {
        const tracks = await getCaptionTracksFromWatchPage(videoId);
        const track = pickBestCaptionTrack(tracks);
        if (!track) throw new Error("No caption tracks in watch page");
        return fetchSegmentsFromCaptionTrack(track);
      },
    },
  ];

  const errors: string[] = [];

  for (const attempt of attempts) {
    try {
      console.log(`Trying transcript source: ${attempt.source}`);
      const segments = await attempt.run();
      if (segments.length > 0) {
        console.log(`Transcript source ${attempt.source} returned ${segments.length} segments.`);
        return segments;
      }
      errors.push(`${attempt.source}: empty transcript`);
    } catch (error: any) {
      errors.push(`${attempt.source}: ${error.message}`);
      console.warn(`Transcript source failed (${attempt.source}):`, error.message);
    }
  }

  throw new Error(errors.join(" | "));
}

async function enrichTranscript(transcriptData: TranscriptSegment[]) {
  if (!ai || !isUsableGeminiKey()) {
    throw new Error("Gemini API key is not configured.");
  }

  const prompt = `You are an expert language teacher. I will provide you with a JSON array representing the transcript of an English YouTube video.
For each item in the array, translate the 'text' into Portuguese (PT-BR).
Return the exact same structure but include a 'translation' field. Do not alter the start and end values.
Keep the original English text exactly as provided.
Here is the transcript data:
${JSON.stringify(transcriptData, null, 2)}`;

  const response = await ai.models.generateContent({
    model: geminiModel,
    contents: prompt,
    config: {
      responseMimeType: "application/json",
      responseSchema: ENRICHED_TRANSCRIPT_SCHEMA,
      temperature: 0.2,
    },
  });

  const responseText = response.text;
  if (!responseText) {
    throw new Error("Empty response from Gemini.");
  }

  return JSON.parse(responseText);
}

type TimedTranscriptWord = {
  token: string;
  start: number;
  end: number;
};

function tokenizeForTiming(text: string) {
  return (text.toLowerCase().match(/[a-z0-9]+(?:['’][a-z0-9]+)*/g) || [])
    .map((token) => token.replaceAll("’", "'"));
}

function buildTranscriptWordTimeline(transcriptSegments: TranscriptSegment[]) {
  return makeSequentialSegments(normalizeTranscriptSegments(transcriptSegments)).flatMap((segment) => {
    const tokens = tokenizeForTiming(segment.text);
    if (tokens.length === 0) return [];

    const duration = Math.max(0.25, segment.end - segment.start);
    return tokens.map<TimedTranscriptWord>((token, index) => ({
      token,
      start: segment.start + duration * (index / tokens.length),
      end: segment.start + duration * ((index + 1) / tokens.length),
    }));
  });
}

function findAlignedPhraseTiming(text: string, approximateStart: number, timeline: TimedTranscriptWord[]) {
  const phraseTokens = tokenizeForTiming(text);
  if (phraseTokens.length === 0 || phraseTokens.length > timeline.length) return null;

  const candidates: { start: number; end: number }[] = [];
  const lastStartIndex = timeline.length - phraseTokens.length;

  for (let startIndex = 0; startIndex <= lastStartIndex; startIndex += 1) {
    let matches = true;
    for (let tokenIndex = 0; tokenIndex < phraseTokens.length; tokenIndex += 1) {
      if (timeline[startIndex + tokenIndex].token !== phraseTokens[tokenIndex]) {
        matches = false;
        break;
      }
    }

    if (matches) {
      candidates.push({
        start: timeline[startIndex].start,
        end: timeline[startIndex + phraseTokens.length - 1].end,
      });
    }
  }

  if (candidates.length === 0) return null;
  return candidates.reduce((closest, candidate) =>
    Math.abs(candidate.start - approximateStart) < Math.abs(closest.start - approximateStart)
      ? candidate
      : closest
  );
}

function realignShadowingLessonTimings(phrases: any[], transcriptSegments: TranscriptSegment[]) {
  const normalizedTranscript = normalizeTranscriptSegments(transcriptSegments);
  const transcriptStart = normalizedTranscript[0]?.start ?? 0;
  const transcriptEnd = normalizedTranscript[normalizedTranscript.length - 1]?.end ?? Number.MAX_SAFE_INTEGER;
  const timeline = buildTranscriptWordTimeline(normalizedTranscript);

  const alignedPhrases = phrases.map((phrase) => {
    const approximateStart = Number(phrase.start);
    const aligned = findAlignedPhraseTiming(String(phrase.text || ""), approximateStart, timeline);
    if (!aligned) return { ...phrase };

    return {
      ...phrase,
      start: Number(Math.max(transcriptStart, aligned.start - SHADOWING_LEAD_IN_SECONDS).toFixed(3)),
      end: Number(Math.min(transcriptEnd, aligned.end + SHADOWING_TRAILING_SECONDS).toFixed(3)),
    };
  });

  return stabilizeShadowingLessonTimings(alignedPhrases);
}

function normalizeAiShadowingPhrases(phrases: any[], transcriptSegments: TranscriptSegment[]) {
  const normalizedTranscript = normalizeTranscriptSegments(transcriptSegments);
  const transcriptStart = normalizedTranscript[0]?.start ?? 0;
  const transcriptEnd = normalizedTranscript[normalizedTranscript.length - 1]?.end ?? Number.MAX_SAFE_INTEGER;

  const normalizedPhrases = phrases
    .map((phrase) => {
      const start = Number(phrase.start);
      const end = Number(phrase.end);
      const text = cleanTranscriptText(String(phrase.text || ""));

      return {
        text,
        translation: String(phrase.translation || ""),
        start: Number(Math.max(transcriptStart, start - SHADOWING_LEAD_IN_SECONDS).toFixed(3)),
        end: Number(Math.min(transcriptEnd, end + SHADOWING_TRAILING_SECONDS).toFixed(3)),
      };
    })
    .filter((phrase) =>
      phrase.text &&
      Number.isFinite(phrase.start) &&
      Number.isFinite(phrase.end) &&
      phrase.end > phrase.start &&
      phrase.end - phrase.start <= SHADOWING_MAX_SECONDS + SHADOWING_LEAD_IN_SECONDS + SHADOWING_TRAILING_SECONDS &&
      countSpokenWords(phrase.text) >= SHADOWING_MIN_WORDS
    )
    .sort((a, b) => a.start - b.start)
    .slice(0, SHADOWING_MAX_AI_PHRASES);

  return realignShadowingLessonTimings(normalizedPhrases, normalizedTranscript);
}

function stabilizeShadowingLessonTimings(phrases: any[]) {
  const stabilized = phrases
    .map((phrase) => ({ ...phrase }))
    .sort((left, right) => Number(left.start) - Number(right.start));

  for (let index = 1; index < stabilized.length; index += 1) {
    const previous = stabilized[index - 1];
    const current = stabilized[index];
    if (Number(current.start) >= Number(previous.end)) continue;

    const boundary = Number(((Number(current.start) + Number(previous.end)) / 2).toFixed(3));
    previous.end = Number(Math.max(Number(previous.start) + SHADOWING_MIN_SECONDS, boundary).toFixed(3));
    current.start = Number(Math.min(Number(current.end) - SHADOWING_MIN_SECONDS, boundary).toFixed(3));
  }

  return stabilized;
}

async function buildAiShadowingTranscript(transcriptSegments: TranscriptSegment[]) {
  if (!ai || !isUsableGeminiKey()) {
    throw new Error("Gemini API key is not configured.");
  }

  const fullTranscript = makeSequentialSegments(normalizeTranscriptSegments(transcriptSegments));
  const prompt = `You are an expert English shadowing lesson editor. Segment this YouTube auto-caption transcript into a coherent sequence of practice clips.

Goal:
- Start from the earliest useful spoken sentence and keep clips chronological and consecutive.
- Cover the spoken passage continuously. Do not cherry-pick disconnected quotes or skip useful words between clips.
- Combine adjacent auto-caption rows whenever a row is only a sentence fragment.
- Each clip must express a complete thought, complete sentence, or independently meaningful clause.
- Never create a clip from isolated leftovers such as "my cable everything", fillers, or one/two/three-word fragments.
- Never end a clip after a determiner, possessive, conjunction, preposition, auxiliary verb, or other word that clearly continues into the next caption.
- Prefer 5 to 14 spoken words and 2.5 to 7 seconds.
- Maximum clip length: ${SHADOWING_MAX_SECONDS} seconds.
- Return at most ${SHADOWING_MAX_AI_PHRASES} clips in chronological order.
- If a complete thought is slightly longer, split only at a natural grammatical pause.

Timing rules:
- Use only timings from the provided transcript.
- You may combine adjacent caption rows into one clip.
- start should be the first included caption start.
- end should be the last included caption end.
- Do not invent timestamps outside the transcript.
- Do not overlap clips.

Language teacher fields:
- text: exact contiguous English words from the transcript, with only light punctuation added.
- translation: Portuguese (PT-BR) translation.

Full transcript JSON:
${JSON.stringify(fullTranscript)}`;

  const response = await ai.models.generateContent({
    model: geminiModel,
    contents: prompt,
    config: {
      responseMimeType: "application/json",
      responseSchema: AI_SHADOWING_SEGMENTS_SCHEMA,
      temperature: 0.15,
    },
  });

  const responseText = response.text;
  if (!responseText) {
    throw new Error("Empty response from Gemini.");
  }

  const parsed = JSON.parse(responseText);
  if (!Array.isArray(parsed)) {
    throw new Error("Gemini did not return a phrase array.");
  }

  const normalized = normalizeAiShadowingPhrases(parsed, fullTranscript);
  if (normalized.length === 0) {
    throw new Error("Gemini returned no usable shadowing clips.");
  }

  return normalized;
}

async function buildAiShadowingWindow(transcriptSegments: TranscriptSegment[], start: number, end: number, maxPhrases = 5) {
  if (!ai || !isUsableGeminiKey()) {
    throw new Error("Gemini API key is not configured.");
  }

  const windowSegments = makeSequentialSegments(normalizeTranscriptSegments(transcriptSegments))
    .filter((segment) => segment.end >= start && segment.start <= end)
    .slice(0, 80);

  if (windowSegments.length === 0) {
    throw new Error("No transcript segments in requested window.");
  }

  const prompt = `You are refining a small section of a YouTube auto-caption transcript for English shadowing.

Select up to ${maxPhrases} natural shadowing clips from this short transcript window.

Rules:
- Do NOT make clips that are only "ok", "yeah", "right", "um", or one/two words.
- Prefer complete spoken thoughts or meaningful clauses.
- Ideal clip length: 2 to 7 seconds.
- Maximum clip length: ${SHADOWING_MAX_SECONDS} seconds.
- Keep clips chronological.
- Use only the provided timestamps.
- You may combine adjacent caption rows.
- Include Portuguese (PT-BR) translation.

Transcript window JSON:
${JSON.stringify(windowSegments)}`;

  const response = await ai.models.generateContent({
    model: geminiModel,
    contents: prompt,
    config: {
      responseMimeType: "application/json",
      responseSchema: AI_SHADOWING_SEGMENTS_SCHEMA,
      temperature: 0.15,
    },
  });

  const responseText = response.text;
  if (!responseText) {
    throw new Error("Empty response from Gemini.");
  }

  const parsed = JSON.parse(responseText);
  if (!Array.isArray(parsed)) {
    throw new Error("Gemini did not return a phrase array.");
  }

  const normalized = normalizeAiShadowingPhrases(parsed, windowSegments).slice(0, maxPhrases);
  if (normalized.length === 0) {
    throw new Error("Gemini returned no usable clips for this window.");
  }

  return normalized;
}

function getYoutubeText(value: any) {
  if (!value) return "";
  if (typeof value === "string") return value;
  if (typeof value.simpleText === "string") return value.simpleText;
  if (typeof value.text === "string") return value.text;
  if (Array.isArray(value.runs)) return value.runs.map((run: any) => run.text || "").join("");
  return String(value);
}

function decodeJsonString(value: string) {
  try {
    return JSON.parse(`"${value.replace(/"/g, '\\"')}"`);
  } catch {
    return value;
  }
}

function extractHtmlMeta(html: string, property: string) {
  const escaped = property.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const regexes = [
    new RegExp(`<meta[^>]+property=["']${escaped}["'][^>]+content=["']([^"']+)["']`, "i"),
    new RegExp(`<meta[^>]+content=["']([^"']+)["'][^>]+property=["']${escaped}["']`, "i"),
    new RegExp(`<meta[^>]+name=["']${escaped}["'][^>]+content=["']([^"']+)["']`, "i"),
  ];

  for (const regex of regexes) {
    const match = html.match(regex);
    if (match?.[1]) return decodeHtmlEntities(match[1]);
  }

  return "";
}

async function getYouTubeVideoMetadata(videoId: string): Promise<VideoRecommendation> {
  const fallback = {
    id: videoId,
    title: `YouTube ${videoId}`,
    channel: "YouTube",
    difficulty: "Intermediário",
    thumbnail: `https://img.youtube.com/vi/${videoId}/mqdefault.jpg`,
  };

  try {
    const oembedUrl = new URL("https://www.youtube.com/oembed");
    oembedUrl.searchParams.set("url", `https://www.youtube.com/watch?v=${videoId}`);
    oembedUrl.searchParams.set("format", "json");

    const response = await youtubeFetch(oembedUrl, {
      headers: {
        "Accept-Language": "en-US,en;q=0.9",
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
      },
    });

    if (response.ok) {
      const data = await response.json();
      return {
        ...fallback,
        title: cleanTranscriptText(data.title || fallback.title),
        channel: cleanTranscriptText(data.author_name || fallback.channel),
        thumbnail: data.thumbnail_url || fallback.thumbnail,
      };
    }
  } catch (error: any) {
    console.warn("YouTube oEmbed metadata failed:", error.message);
  }

  try {
    const response = await youtubeFetch(`https://www.youtube.com/watch?v=${videoId}&hl=en`, {
      headers: {
        "Accept-Language": "en-US,en;q=0.9",
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
      },
    });

    if (!response.ok) return fallback;
    const html = await response.text();
    const title =
      extractHtmlMeta(html, "og:title") ||
      decodeJsonString(html.match(/"title":"([^"]+)"/)?.[1] || "") ||
      fallback.title;
    const channel =
      decodeJsonString(html.match(/"ownerChannelName":"([^"]+)"/)?.[1] || "") ||
      extractHtmlMeta(html, "author") ||
      fallback.channel;

    return {
      ...fallback,
      title: cleanTranscriptText(title),
      channel: cleanTranscriptText(channel),
      thumbnail: extractHtmlMeta(html, "og:image") || fallback.thumbnail,
    };
  } catch (error: any) {
    console.warn("YouTube watch metadata failed:", error.message);
    return fallback;
  }
}

function getDifficultyLabel(difficulty: string) {
  const id = difficulty.toLowerCase();
  if (id.includes("beginner") || id.includes("iniciante")) return "Iniciante";
  if (id.includes("advanced") || id.includes("avançado")) return "Avançado";
  return "Intermediário";
}

function inferThemeFromText(title = "", channel = "") {
  const haystack = `${title} ${channel}`.toLowerCase();
  if (/flight|aviation|pilot|aircraft|airplane|airport|atc|runway|cockpit/.test(haystack)) return "Viagem e Cultura";
  if (/\b(tech|ai|software|computer|phone|robot|future|innovation)\b/.test(haystack)) return "Tecnologia";
  if (/business|work|career|startup|founder|company|productivity/.test(haystack)) return "Negócios/Trabalho";
  if (/movie|film|actor|cinema|series|trailer|scene/.test(haystack)) return "Cinema e Séries";
  if (/news|debate|politics|world|society|current/.test(haystack)) return "Notícias e Debates";
  return "Viagem e Cultura";
}

function parseDurationSeconds(durationText?: string) {
  if (!durationText) return null;
  const parts = durationText.split(":").map((part) => Number(part));
  if (parts.some((part) => Number.isNaN(part))) return null;
  return parts.reduce((total, part) => total * 60 + part, 0);
}

function getDifficultySearchTerms(difficulty: string) {
  const difficultyTerms: Record<string, string> = {
    beginner: "simple short clear English",
    intermediate: "clear English interview explained",
    advanced: "advanced English documentary debate lecture",
  };

  return difficultyTerms[difficulty] || "clear English explained";
}

function getThemeSearchConfig(theme: string) {
  const configs: Record<string, { queries: string[]; keywords: string[] }> = {
    "Viagem e Cultura": {
      queries: [
        "travel culture vlog real conversation",
        "city culture documentary travel guide",
        "street interview culture travel",
      ],
      keywords: ["travel", "culture", "city", "country", "street", "tour", "vlog", "guide", "people"],
    },
    "Tecnologia": {
      queries: [
        "technology explained innovation",
        "artificial intelligence technology explained",
        "tech interview innovation future",
        "Marques Brownlee tech interview",
      ],
      keywords: ["technology", "technologies", "tech", "ai", "artificial intelligence", "innovation", "software", "computer", "robot", "future", "machine learning", "generative"],
    },
    "Negócios/Trabalho": {
      queries: [
        "business interview startup founder",
        "workplace productivity career advice",
        "entrepreneurship business explained",
      ],
      keywords: ["business", "work", "workplace", "career", "startup", "founder", "company", "productivity", "entrepreneur", "professional"],
    },
    "Cinema e Séries": {
      queries: [
        "movie review interview film",
        "actor interview movie scene",
        "film analysis TV series explained",
      ],
      keywords: ["movie", "film", "actor", "cinema", "series", "tv", "scene", "review", "interview", "trailer"],
    },
    "Notícias e Debates": {
      queries: [
        "news debate current events discussion",
        "world news explained discussion",
        "debate interview politics society",
      ],
      keywords: ["news", "debate", "world", "politics", "society", "current", "explained", "interview", "discussion"],
    },
  };

  return configs[theme] || {
    queries: [`${theme} English explained`, `${theme} interview discussion`],
    keywords: theme.toLowerCase().split(/\s+/),
  };
}

function buildRecommendationQueries(theme: string, difficulty: string) {
  const config = getThemeSearchConfig(theme);
  const levelTerms = getDifficultySearchTerms(difficulty);
  return config.queries.map((query) => `${query} ${levelTerms}`);
}

function scoreVideoForTheme(video: VideoRecommendation, theme: string) {
  const config = getThemeSearchConfig(theme);
  const haystack = `${video.title} ${video.channel}`.toLowerCase();
  const keywordScore = config.keywords.reduce((score, keyword) => (
    haystack.includes(keyword.toLowerCase()) ? score + 2 : score
  ), 0);
  const learningPenalty = /learn english|learning english|english lesson|english grammar|vocabulary/i.test(haystack) ? 4 : 0;
  const careerPenalty = theme === "Negócios/Trabalho"
    ? 0
    : /job interview questions|how to pass|recruiter|resume|cv|hiring/i.test(haystack) ? 4 : 0;
  return keywordScore - learningPenalty - careerPenalty;
}

function mapSearchVideo(video: any, difficulty: string): VideoRecommendation | null {
  const id = video.id || video.video_id;
  const title = getYoutubeText(video.title);
  const duration = getYoutubeText(video.duration);
  const durationSeconds = parseDurationSeconds(duration);

  if (!id || !title) return null;
  if (durationSeconds !== null && (durationSeconds < 60 || durationSeconds > 20 * 60)) return null;
  if (/shorts?|compilation|playlist|live/i.test(title)) return null;

  return {
    id,
    title,
    channel: video.author?.name || getYoutubeText(video.author) || "YouTube",
    difficulty: getDifficultyLabel(difficulty),
    thumbnail: `https://img.youtube.com/vi/${id}/mqdefault.jpg`,
    duration,
  };
}

function collectVideoRenderers(value: any, output: any[] = []) {
  if (!value || typeof value !== "object") return output;

  if (value.videoRenderer) {
    output.push(value.videoRenderer);
  }

  if (Array.isArray(value)) {
    for (const item of value) {
      collectVideoRenderers(item, output);
    }
    return output;
  }

  for (const item of Object.values(value)) {
    collectVideoRenderers(item, output);
  }

  return output;
}

function mapVideoRenderer(videoRenderer: any, difficulty: string): VideoRecommendation | null {
  const id = videoRenderer.videoId;
  const title = getYoutubeText(videoRenderer.title);
  const duration = getYoutubeText(videoRenderer.lengthText);
  const durationSeconds = parseDurationSeconds(duration);

  if (!id || !title) return null;
  if (durationSeconds !== null && (durationSeconds < 60 || durationSeconds > 20 * 60)) return null;
  if (/shorts?|compilation|playlist|live/i.test(title)) return null;

  return {
    id,
    title,
    channel: getYoutubeText(videoRenderer.ownerText) || getYoutubeText(videoRenderer.shortBylineText) || "YouTube",
    difficulty: getDifficultyLabel(difficulty),
    thumbnail: `https://img.youtube.com/vi/${id}/mqdefault.jpg`,
    duration,
  };
}

function getCatalogRecommendations(catalog: any[], theme: string, difficulty: string, excludeIds = new Set<string>()) {
  const difficultyLabel = getDifficultyLabel(difficulty);
  const exactMatches = catalog.filter(v => 
    v.theme.toLowerCase() === theme.toLowerCase() && 
    v.difficulty.toLowerCase() === difficultyLabel.toLowerCase() &&
    !excludeIds.has(v.id)
  );
  const themeMatches = catalog.filter(v =>
    v.theme.toLowerCase() === theme.toLowerCase() &&
    !excludeIds.has(v.id)
  );
  const fallbackMatches = catalog.filter(v => !excludeIds.has(v.id));
  const candidates = [...exactMatches, ...themeMatches, ...fallbackMatches];
  const deduped = candidates.filter((video, index) => (
    candidates.findIndex((candidate) => candidate.id === video.id) === index
  ));

  return deduped.map((video: any) => ({
    id: video.id,
    title: video.title,
    channel: video.channel,
    difficulty: video.difficulty,
    thumbnail: `https://img.youtube.com/vi/${video.id}/mqdefault.jpg`
  }));
}

async function searchYoutubePage(query: string, difficulty: string) {
  const url = new URL("https://www.youtube.com/results");
  url.searchParams.set("search_query", query);
  url.searchParams.set("sp", "EgIQAQ%3D%3D");

  const response = await youtubeFetch(url, {
    headers: {
      "Accept-Language": "en-US,en;q=0.9",
      "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
    },
  });

  if (!response.ok) {
    throw new Error(`YouTube search failed: ${response.status}`);
  }

  const html = await response.text();
  const initialDataJson = extractJsonObjectAfter(html, "ytInitialData");
  if (!initialDataJson) return [];

  const initialData = JSON.parse(initialDataJson);
  return collectVideoRenderers(initialData)
    .map((videoRenderer) => mapVideoRenderer(videoRenderer, difficulty))
    .filter(Boolean) as VideoRecommendation[];
}

async function hasAccessibleTranscript(videoId: string) {
  try {
    const segments = await fetchYouTubeTranscriptSegments(videoId);
    return segments.length > 0;
  } catch {
    return false;
  }
}

async function searchYoutubeRecommendations(theme: string, difficulty: string) {
  const seen = new Set<string>();
  const videos: VideoRecommendation[] = [];

  for (const query of buildRecommendationQueries(theme, difficulty)) {
    const mappedVideos = await searchYoutubePage(query, difficulty);

    for (const video of mappedVideos) {
      if (seen.has(video.id)) continue;
      seen.add(video.id);
      videos.push(video);
    }
  }

  const rankedVideos = videos
    .map((video) => ({ video, score: scoreVideoForTheme(video, theme) }))
    .filter((result) => result.score > 0)
    .sort((a, b) => b.score - a.score)
    .map((result) => result.video)
    .slice(0, 12);

  const checked = await Promise.all(rankedVideos.map(async (video) => ({
    video,
    hasTranscript: await hasAccessibleTranscript(video.id),
  })));

  return checked
    .filter((result) => result.hasTranscript)
    .map((result) => result.video)
    .slice(0, 6);
}

export async function createApp({ includeFrontend = true } = {}) {
  const app = express();
  const commercialBackend = createCommercialBackend();
  const legacyYoutubeEnabled = process.env.ENABLE_LEGACY_YOUTUBE?.trim().toLowerCase() === "true"
    || !commercialBackend.cloudMode;

  app.use(express.json({ limit: "4mb" }));
  app.use("/offline-library", express.static(offlineLibraryDir));
  app.use("/api/commercial", commercialBackend.router);

  const requireLegacyYoutube = (_req: express.Request, res: express.Response, next: express.NextFunction) => {
    if (!legacyYoutubeEnabled) {
      return res.status(404).json({
        error: "Esta versão usa somente a biblioteca própria de conteúdos licenciados.",
      });
    }
    return next();
  };

  app.get("/api/settings/ai", (_req, res) => {
    if (commercialBackend.cloudMode || !runtimeSettingsPath) return res.sendStatus(404);
    return res.json({ configured: isUsableGeminiKey(), model: geminiModel });
  });

  app.post("/api/settings/ai", async (req, res) => {
    if (commercialBackend.cloudMode || !runtimeSettingsPath) return res.sendStatus(404);

    const apiKey = String(req.body?.apiKey || "").trim();
    if (apiKey.length < 20) {
      return res.status(400).json({ error: "Cole uma chave válida da API do Google Gemini." });
    }

    try {
      await writeFile(runtimeSettingsPath, JSON.stringify({ geminiApiKey: apiKey }, null, 2), { mode: 0o600 });
      configureGeminiApiKey(apiKey);
      return res.json({ configured: true, model: geminiModel });
    } catch (error: any) {
      return res.status(500).json({ error: error.message || "Não foi possível salvar a chave." });
    }
  });

  const allowMobileLessonRequests = (_req: express.Request, res: express.Response, next: express.NextFunction) => {
    res.setHeader("Access-Control-Allow-Origin", "*");
    res.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization");
    res.setHeader("Access-Control-Allow-Methods", "POST, OPTIONS");
    next();
  };

  app.options("/api/segmentTranscript", allowMobileLessonRequests, (_req, res) => res.sendStatus(204));
  app.post("/api/segmentTranscript", allowMobileLessonRequests, commercialBackend.protectAi, async (req, res) => {
    const transcriptData = normalizeTranscriptSegments(Array.isArray(req.body?.transcriptData) ? req.body.transcriptData : []);
    if (transcriptData.length === 0) {
      return res.status(400).json({ error: "transcriptData array is required" });
    }

    if (geminiSegmentationEnabled) {
      try {
        const phrases = await buildAiShadowingTranscript(transcriptData);
        res.setHeader("X-Transcript-Segmentation", "gemini");
        return res.json(phrases);
      } catch (error: any) {
        console.warn("Mobile AI segmentation failed:", error.message);
      }
    }

    const groupedPhrases = groupSegmentsForShadowing(transcriptData);
    res.setHeader("X-Transcript-Segmentation", "local-fallback");
    try {
      return res.json(await enrichTranscript(groupedPhrases));
    } catch (error: any) {
      console.warn("Mobile transcript enrichment failed:", error.message);
      return res.json(toBasicPhrases(groupedPhrases));
    }
  });

  // API Route for pronunciation analysis
  app.post("/api/analyzePronunciation", commercialBackend.protectAi, async (req, res) => {
    const { audioUrl, audioBase64, mimeType: requestedMimeType, phrase } = req.body;

    if (!phrase || (!audioBase64 && !audioUrl)) {
      return res.status(400).json({ error: "Áudio e frase são obrigatórios." });
    }

    try {
      console.log(`Analyzing pronunciation for phrase: "${phrase}"`);

      let base64Data: string;
      let mimeType: string;
      if (audioBase64) {
        base64Data = String(audioBase64).replace(/^data:[^;]+;base64,/, '');
        mimeType = String(requestedMimeType || 'audio/webm').split(';')[0].toLowerCase();
        const allowedMimeTypes = new Set(['audio/webm', 'audio/mp4', 'audio/mpeg', 'audio/wav', 'audio/ogg']);
        if (!allowedMimeTypes.has(mimeType) || base64Data.length > 2_500_000 || !/^[A-Za-z0-9+/=]+$/.test(base64Data)) {
          return res.status(400).json({ error: 'Formato de áudio inválido ou arquivo muito grande.' });
        }
      } else {
        if (commercialBackend.cloudMode) {
          return res.status(400).json({ error: 'Envie a gravação diretamente pelo aplicativo.' });
        }
        const audioRes = await fetch(audioUrl);
        if (!audioRes.ok) throw new Error(`Failed to fetch audio from URL: ${audioRes.statusText}`);
        const arrayBuffer = await audioRes.arrayBuffer();
        base64Data = Buffer.from(arrayBuffer).toString("base64");
        mimeType = audioRes.headers.get("content-type") || "audio/webm";
      }

      const schema: Schema = {
        type: Type.OBJECT,
        properties: {
          score: { type: Type.NUMBER, description: "Overall score from 0 to 100" },
          words: {
            type: Type.ARRAY,
            items: {
              type: Type.OBJECT,
              properties: {
                word: { type: Type.STRING, description: "Word from the original phrase" },
                correct: { type: Type.BOOLEAN, description: "Whether the pronunciation was correct" },
                tip: { type: Type.STRING, description: "Phonetic tip in Portuguese if incorrect, else empty string" },
              },
              required: ["word", "correct", "tip"],
            },
          },
        },
        required: ["score", "words"],
      };

      const prompt = `You are an expert language teacher. Listen to the user's spoken audio and compare it to the following reference phrase: "${phrase}".
Evaluate each word. For each word in the reference phrase, determine if it was pronounced correctly.
If a word was pronounced poorly, set 'correct' to false and provide a short phonetic tip in Portuguese (PT-BR). Example: 'O som do "th" deve ser feito com a ponta da língua nos dentes superiores'.
If the word was pronounced ok, set 'correct' to true and tip to "".
Return an overall score 0-100.`;

      if (!ai || !isUsableGeminiKey()) {
        throw new Error("Gemini API key is not configured.");
      }

      const response = await ai.models.generateContent({
        model: geminiModel,
        contents: [
          prompt,
          {
            inlineData: {
              data: base64Data,
              mimeType: mimeType,
            },
          },
        ],
        config: {
          responseMimeType: "application/json",
          responseSchema: schema,
          temperature: 0.2,
        },
      });

      const responseText = response.text;
      if (!responseText) {
        throw new Error("Empty response from Gemini.");
      }
      const data = JSON.parse(responseText);
      
      console.log(`Pronunciation analysis generated. Score: ${data.score}`);
      res.json(data);
    } catch (error: any) {
      console.error("Error in analyzePronunciation:", error);
      res.status(500).json({ error: error.message || "Something went wrong" });
    }
  });

  // Pre-curated list of excellent, real YouTube videos organized by theme and difficulty
  const VIDEO_CATALOG = [
    // Viagem e Cultura
    { id: "Jv-cnD17k7s", title: "Why Tokyo Is Insanely Well Designed", channel: "PolyMatter", theme: "Viagem e Cultura", difficulty: "Avançado" },
    { id: "tH2w6Oxx0kQ", title: "A trip to London - English Conversation", channel: "English Speaking Course", theme: "Viagem e Cultura", difficulty: "Iniciante" },
    { id: "Qmi-Xwq-MEc", title: "10 Best Places to Visit in Europe", channel: "touropia", theme: "Viagem e Cultura", difficulty: "Intermediário" },
    
    // Tecnologia
    { id: "RQPRaWqTMTc", title: "I Reviewed The Boring Phone", channel: "Marques Brownlee", theme: "Tecnologia", difficulty: "Intermediário" },
    { id: "jNQXAC9IVRw", title: "Me at the zoo", channel: "jawed", theme: "Tecnologia", difficulty: "Iniciante" },
    { id: "5sJbCIfX7p8", title: "How computers translate human language", channel: "TED-Ed", theme: "Tecnologia", difficulty: "Avançado" },
    { id: "k-zKCU5qFWE", title: "The Next Big Leap in Tech", channel: "Tech Vision", theme: "Tecnologia", difficulty: "Avançado" },

    // Negócios/Trabalho
    { id: "j5v8D-alAKE", title: "How to Sound More Professional at Work", channel: "English with Lucy", theme: "Negócios/Trabalho", difficulty: "Intermediário" },
    { id: "d_m5csmrf7I", title: "How to win friends and influence people", channel: "The Animated Book", theme: "Negócios/Trabalho", difficulty: "Intermediário" },
    { id: "Z9bX_VInB_A", title: "Steve Jobs' 2005 Stanford Commencement Address", channel: "Stanford", theme: "Negócios/Trabalho", difficulty: "Avançado" },
    
    // Cinema e Séries
    { id: "4TzEU-iN_d4", title: "Why Movies Look So Dark Now", channel: "Vox", theme: "Cinema e Séries", difficulty: "Intermediário" },
    { id: "kZb1WnU0qB0", title: "Harry Potter and the Sorcerer's Stone - Trailer", channel: "Warner Bros", theme: "Cinema e Séries", difficulty: "Iniciante" },
    { id: "1ROY4C51z6U", title: "The Making of Interstellar", channel: "Movie Behind", theme: "Cinema e Séries", difficulty: "Avançado" },
    
    // Notícias e Debates
    { id: "P2QkP6pP2vI", title: "The unexpected math behind this simple game", channel: "TED-Ed", theme: "Notícias e Debates", difficulty: "Intermediário" },
    { id: "T1eCqWEMf98", title: "Is the World Getting Better or Worse?", channel: "Kurzgesagt", theme: "Notícias e Debates", difficulty: "Avançado" },
    { id: "VyoN4BtvVbU", title: "Basic English News for Beginners", channel: "English News", theme: "Notícias e Debates", difficulty: "Iniciante" }
  ];

  // API Route for recommending YouTube videos
  app.post("/api/recommendVideos", requireLegacyYoutube, async (req, res) => {
    const { theme, difficulty } = req.body;

    if (!theme || !difficulty) {
      return res.status(400).json({ error: "theme and difficulty are required" });
    }

    try {
      console.log(`Getting video recommendations for theme: ${theme}, difficulty: ${difficulty}`);

      const liveRecommendations = await searchYoutubeRecommendations(theme, difficulty);

      if (liveRecommendations.length >= 3) {
        return res.json(liveRecommendations);
      }

      if (liveRecommendations.length > 0) {
        const excludeIds = new Set(liveRecommendations.map((video) => video.id));
        const topUpRecommendations = getCatalogRecommendations(VIDEO_CATALOG, theme, difficulty, excludeIds)
          .slice(0, 3 - liveRecommendations.length);
        return res.json([...liveRecommendations, ...topUpRecommendations]);
      }

      console.warn("Live YouTube recommendation search returned no usable videos. Falling back to catalog.");

      res.json(getCatalogRecommendations(VIDEO_CATALOG, theme, difficulty).slice(0, 3));

    } catch (error: any) {
      console.error("Error in recommendVideos:", error);
      res.json(getCatalogRecommendations(VIDEO_CATALOG, theme, difficulty).slice(0, 3));
    }
  });

  app.get("/api/videoMetadata/:videoId", requireLegacyYoutube, async (req, res) => {
    const { videoId } = req.params;

    if (!videoId) {
      return res.status(400).json({ error: "videoId is required" });
    }

    try {
      const metadata = await getYouTubeVideoMetadata(videoId);
      res.json(metadata);
    } catch (error: any) {
      console.error("Error in videoMetadata:", error);
      res.status(500).json({ error: error.message || "Failed to fetch video metadata" });
    }
  });

  app.get("/api/offline/library", requireLegacyYoutube, async (_req, res) => {
    res.json({ videos: await listOfflineVideos() });
  });

  app.get("/api/offline/status/:videoId", requireLegacyYoutube, async (req, res) => {
    const { videoId } = req.params;
    if (!isValidVideoId(videoId)) {
      return res.status(400).json({ error: "videoId is invalid" });
    }

    const metadata = await readOfflineVideoMetadata(videoId);
    if (metadata) {
      return res.json({ videoId, status: "ready", progress: 100, metadata });
    }

    const job = offlineDownloadJobs.get(videoId);
    return res.json(job || { videoId, status: "missing", progress: 0 });
  });

  app.get("/api/offline/lesson/:videoId", requireLegacyYoutube, async (req, res) => {
    const { videoId } = req.params;
    if (!isValidVideoId(videoId) || !(await readOfflineVideoMetadata(videoId))) {
      return res.status(404).json({ error: "Offline video not found" });
    }

    try {
      return res.json(await ensureOfflineLesson(videoId));
    } catch (error: any) {
      console.error(`Offline lesson failed (${videoId}):`, error.message);
      return res.status(500).json({ error: "Não foi possível preparar a aula offline." });
    }
  });

  app.post("/api/offline/download", requireLegacyYoutube, async (req, res) => {
    const { videoId, url, quality = "360p" } = req.body;
    if (!videoId || !isValidVideoId(videoId)) {
      return res.status(400).json({ error: "videoId is required" });
    }

    const existingMetadata = await readOfflineVideoMetadata(videoId);
    if (existingMetadata) {
      return res.json({ videoId, status: "ready", progress: 100, metadata: existingMetadata });
    }

    const existingJob = offlineDownloadJobs.get(videoId);
    if (existingJob?.status === "downloading") {
      return res.status(202).json(existingJob);
    }

    const initialJob: OfflineDownloadJob = {
      videoId,
      status: "downloading",
      stage: "starting",
      message: "Preparando download...",
      progress: 0,
    };
    offlineDownloadJobs.set(videoId, initialJob);
    console.log("[offline-download] started", { videoId, quality });
    res.status(202).json(initialJob);

    void (async () => {
      try {
        const engine = await getOfflineEngine();
        const result = await engine.download(url || videoId, {
          quality,
          libraryDir: offlineLibraryDir,
          onProgress(event: { stage?: string; message?: string; progress?: number | null }) {
            offlineDownloadJobs.set(videoId, {
              videoId,
              status: "downloading",
              stage: event.stage,
              message: event.message,
              progress: event.progress ?? offlineDownloadJobs.get(videoId)?.progress ?? 0,
            });
          },
        });
        await ensureOfflineLesson(videoId);
        offlineDownloadJobs.set(videoId, {
          videoId,
          status: "ready",
          stage: "done",
          message: "Pronto para uso offline.",
          progress: 100,
          metadata: result.metadata,
        });
        console.log("[offline-download] completed", {
          videoId,
          quality: result.metadata.format?.quality,
          contentLength: result.metadata.format?.contentLength,
        });
      } catch (error: any) {
        console.error(`Offline download failed (${videoId}):`, error.message);
        offlineDownloadJobs.set(videoId, {
          videoId,
          status: "error",
          stage: "error",
          message: "Não foi possível baixar este vídeo.",
          progress: 0,
          error: error.message,
        });
      }
    })();
  });

  app.post("/api/recommendSimilarVideos", requireLegacyYoutube, async (req, res) => {
    const { videoId, title, channel, theme } = req.body;

    try {
      const metadata = videoId ? await getYouTubeVideoMetadata(videoId) : null;
      const baseTitle = cleanTranscriptText(title || metadata?.title || "");
      const baseChannel = cleanTranscriptText(channel || metadata?.channel || "");
      const queryParts = [
        baseChannel,
        baseTitle
          .replace(/[^\w\s]/g, " ")
          .split(/\s+/)
          .filter((word) => word.length > 3)
          .slice(0, 6)
          .join(" "),
        "English video clear speech",
      ].filter(Boolean);

      const liveVideos = await searchYoutubePage(queryParts.join(" "), "intermediate");
      const fallbackTheme = theme || inferThemeFromText(baseTitle, baseChannel);
      const deduped = liveVideos
        .filter((video) => video.id !== videoId)
        .filter((video) => !/learn english|english learners|pronunciation practice|english lesson|grammar|vocabulary/i.test(`${video.title} ${video.channel}`))
        .map((video) => ({
          ...video,
          difficulty: "Parecido",
        }));
      const themedVideos = deduped.filter((video) => (
        (baseChannel && video.channel.toLowerCase().includes(baseChannel.toLowerCase())) ||
        scoreVideoForTheme(video, fallbackTheme) > 0
      ));

      if (themedVideos.length > 0) {
        return res.json(themedVideos.slice(0, 6));
      }

      return res.json(getCatalogRecommendations(VIDEO_CATALOG, fallbackTheme, "intermediate", new Set(videoId ? [videoId] : [])).slice(0, 6));
    } catch (error: any) {
      console.error("Error in recommendSimilarVideos:", error);
      res.json(getCatalogRecommendations(VIDEO_CATALOG, theme || "Viagem e Cultura", "intermediate", new Set(videoId ? [videoId] : [])).slice(0, 6));
    }
  });

  app.post("/api/refineShadowingWindow", requireLegacyYoutube, commercialBackend.protectAi, async (req, res) => {
    const { videoId, start, end, maxPhrases } = req.body;

    if (!videoId || !Number.isFinite(Number(start)) || !Number.isFinite(Number(end)) || Number(end) <= Number(start)) {
      return res.status(400).json({ error: "videoId, start and end are required" });
    }

    try {
      const transcriptSegments = await fetchYouTubeTranscriptSegments(videoId);
      const windowStart = Math.max(0, Number(start) - 0.4);
      const windowEnd = Number(end) + 0.6;
      const phraseLimit = Math.max(1, Math.min(Number(maxPhrases) || 5, 8));

      try {
        const aiPhrases = await buildAiShadowingWindow(transcriptSegments, windowStart, windowEnd, phraseLimit);
        res.setHeader("X-Transcript-Segmentation", "gemini-window");
        return res.json(aiPhrases);
      } catch (aiError: any) {
        console.error("AI window refinement failed:", aiError.message);
      }

      const fallbackWindowSegments = normalizeTranscriptSegments(transcriptSegments)
        .filter((segment) => segment.end >= windowStart && segment.start <= windowEnd);
      const fallbackPhrases = groupSegmentsForShadowing(fallbackWindowSegments).slice(0, phraseLimit);

      res.setHeader("X-Transcript-Segmentation", "local-window-fallback");
      return res.json(toBasicPhrases(fallbackPhrases));
    } catch (error: any) {
      console.error("Error in refineShadowingWindow:", error);
      return res.status(500).json({ error: error.message || "Failed to refine shadowing window" });
    }
  });

  app.get("/api/test-transcript/:videoId", requireLegacyYoutube, async (req, res) => {
    try {
      const { videoId } = req.params;
      const response = await youtubeFetch(`https://www.youtube.com/watch?v=${videoId}`);
      const html = await response.text();
      let hasCaptionTracks = html.includes('"captionTracks"');
      let hasPlayerResponse = html.includes('ytInitialPlayerResponse');
      let status = "Not found";
      
      const match = html.match(/ytInitialPlayerResponse\s*=\s*(\{.+?\});/);
      let captionsStr = null;
      if (match) {
        status = "Found player response";
        try {
          const playerRes = JSON.parse(match[1]);
          captionsStr = playerRes.captions ? playerRes.captions.playerCaptionsTracklistRenderer : null;
        } catch(e) {}
      }

      res.json({
         hasCaptionTracks,
         hasPlayerResponse,
         status,
         captions: captionsStr,
         isRecaptcha: html.includes('g-recaptcha')
      });
    } catch(e: any) {
      res.status(500).json({ error: e.message });
    }
  });

  // Parse manually uploaded SRT transcript logic
  app.post("/api/enrichManualTranscript", commercialBackend.protectAi, async (req, res) => {
    const { transcriptData } = req.body;
    
    if (!transcriptData || !Array.isArray(transcriptData) || transcriptData.length === 0) {
      return res.status(400).json({ error: "transcriptData array is required" });
    }

    try {
      const manualPhrases = groupSegmentsForShadowing(transcriptData);
      console.log(`Processing ${manualPhrases.length} manual transcript items...`);

      let enrichedPhrases;
      try {
        enrichedPhrases = await enrichTranscript(manualPhrases);
      } catch (enrichmentError: any) {
        console.error("Manual transcript enrichment failed:", enrichmentError.message);
        res.setHeader("X-Transcript-Enrichment", "failed");
        return res.json(toBasicPhrases(manualPhrases));
      }
      
      console.log(`Successfully generated ${enrichedPhrases.length} enriched phrases (manual).`);
      return res.json(enrichedPhrases);

    } catch (error: any) {
      console.error("Error in enrichManualTranscript:", error);
      res.status(500).json({ error: error.message || "Failed to parse manual transcript" });
    }
  });

  // API Route for fetching and enriching the transcript
  app.post("/api/getEnrichedTranscript", requireLegacyYoutube, commercialBackend.protectAi, async (req, res) => {
    const { videoId } = req.body;

    if (!videoId) {
      return res.status(400).json({ error: "videoId is required" });
    }

    try {
      console.log(`Fetching transcript for video: ${videoId}`);
      let transcriptSegments: TranscriptSegment[];

      try {
        transcriptSegments = await fetchYouTubeTranscriptSegments(videoId);
      } catch (transcriptError: any) {
        console.error("Transcript fetch failed:", transcriptError.message);
        return res.status(400).json({
          error: "Não consegui acessar legendas públicas para este vídeo. Tente um vídeo com captions/legenda automática visível no YouTube.",
          details: process.env.NODE_ENV === "production" ? undefined : transcriptError.message,
        });
      }

      if (!transcriptSegments || transcriptSegments.length === 0) {
        return res.status(404).json({ error: "No transcript found for this video." });
      }

      if (geminiSegmentationEnabled) {
        let shadowingPhrases;
        try {
          console.log(`Sending full transcript (${transcriptSegments.length} segments) to Gemini for shadowing segmentation...`);
          shadowingPhrases = await buildAiShadowingTranscript(transcriptSegments);
          res.setHeader("X-Transcript-Segmentation", "gemini");
          console.log(`Gemini selected ${shadowingPhrases.length} shadowing clips.`);
          return res.json(shadowingPhrases);
        } catch (segmentationError: any) {
          console.error("AI shadowing segmentation failed:", segmentationError.message);
        }
      }

      const transcriptData = groupSegmentsForShadowing(transcriptSegments);
      res.setHeader("X-Transcript-Segmentation", "local-fallback");
      console.log(`Using local fallback with ${transcriptData.length} shadowing clips.`);

      let enrichedPhrases;
      try {
        console.log(`Sending ${transcriptData.length} fallback items to Gemini for enrichment...`);
        enrichedPhrases = await enrichTranscript(transcriptData);
      } catch (enrichmentError: any) {
        console.error("Transcript enrichment failed:", enrichmentError.message);
        res.setHeader("X-Transcript-Enrichment", "failed");
        return res.json(toBasicPhrases(transcriptData));
      }

      console.log(`Successfully generated ${enrichedPhrases.length} enriched fallback phrases.`);
      return res.json(enrichedPhrases);
    } catch (error: any) {
      console.error("Transcript pipeline failed:", error.message);
      return res.status(400).json({
        error: "Não consegui acessar legendas públicas para este vídeo. Tente um vídeo com captions/legenda automática visível no YouTube.",
        details: process.env.NODE_ENV === "production" ? undefined : error.message,
      });
    }
  });

  if (includeFrontend) {
    // Vite middleware for development
    if (process.env.NODE_ENV !== "production") {
      const { createServer: createViteServer } = await import("vite");
      const vite = await createViteServer({
        server: {
          middlewareMode: true,
          watch: {
            ignored: ["**/offline-lab/library/**"],
          },
        },
        appType: "spa",
      });
      app.use(vite.middlewares);
    } else {
      const distPath = process.env.SHADOWING_WEB_DIR || path.join(appRootDir, "dist");
      app.use(express.static(distPath));
      app.get("*", (req, res) => {
        res.sendFile(path.join(distPath, "index.html"));
      });
    }
  }

  return app;
}

async function startServer() {
  const PORT = Number(process.env.PORT || 3000);
  const app = await createApp({ includeFrontend: true });

  app.listen(PORT, "0.0.0.0", () => {
    console.log(`Server running on http://localhost:${PORT}`);
  });
}

if (process.env.VERCEL !== "1") {
  startServer();
}
