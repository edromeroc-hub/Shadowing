import express from "express";
import path from "path";
import { createServer as createViteServer } from "vite";
import { YoutubeTranscript } from "youtube-transcript";
import { GoogleGenAI, Type, Schema } from "@google/genai";
import dotenv from "dotenv";

dotenv.config();

const ai = new GoogleGenAI({ apiKey: process.env.GEMINI_API_KEY });

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

const SHADOWING_LEAD_IN_SECONDS = 0.18;
const SHADOWING_TRAILING_SECONDS = 0.32;
const SHADOWING_MAX_SECONDS = 8;
const SHADOWING_MAX_CHARS = 160;
const SHADOWING_MIN_SECONDS = 0.55;

const ENRICHED_TRANSCRIPT_SCHEMA: Schema = {
  type: Type.ARRAY,
  description: "List of enriched transcript phrases",
  items: {
    type: Type.OBJECT,
    properties: {
      text: { type: Type.STRING, description: "The original English text" },
      phonetic: { type: Type.STRING, description: "Phonetic transcription (IPA)" },
      translation: { type: Type.STRING, description: "Portuguese (PT-BR) translation" },
      start: { type: Type.NUMBER, description: "Start time in seconds" },
      end: { type: Type.NUMBER, description: "End time in seconds" },
    },
    required: ["text", "phonetic", "translation", "start", "end"],
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
    const shouldMerge =
      gap <= 1.1 &&
      combinedDuration <= SHADOWING_MAX_SECONDS &&
      combinedText.length <= SHADOWING_MAX_CHARS &&
      !endsAtNaturalPause(current.text);

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

  return applyShadowingBuffer(phrases)
    .filter((phrase) => phrase.end - phrase.start >= SHADOWING_MIN_SECONDS)
    .slice(0, 60);
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
  const response = await fetch("https://www.youtube.com/youtubei/v1/player?prettyPrint=false", {
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
  const response = await fetch(`https://www.youtube.com/watch?v=${videoId}&hl=en`, {
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
  const response = await fetch(track.baseUrl, {
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
  const transcriptItems = await YoutubeTranscript.fetchTranscript(videoId, lang ? { lang } : undefined);
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
  const prompt = `You are an expert language teacher. I will provide you with a JSON array representing the transcript of an English YouTube video.
For each item in the array, translate the 'text' into Portuguese (PT-BR) and provide its phonetic transcription using the International Phonetic Alphabet (IPA).
Return the exact same structure but include 'phonetic' and 'translation' fields. Do not alter the start and end values.
Keep the original English text exactly as provided.
Here is the transcript data:
${JSON.stringify(transcriptData, null, 2)}`;

  const response = await ai.models.generateContent({
    model: "gemini-1.5-flash",
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

async function startServer() {
  const app = express();
  const PORT = 3000;

  app.use(express.json());

  // API Route for pronunciation analysis
  app.post("/api/analyzePronunciation", async (req, res) => {
    const { audioUrl, phrase } = req.body;

    if (!audioUrl || !phrase) {
      return res.status(400).json({ error: "audioUrl and phrase are required" });
    }

    try {
      console.log(`Analyzing pronunciation for phrase: "${phrase}"`);
      
      const audioRes = await fetch(audioUrl);
      if (!audioRes.ok) {
        throw new Error(`Failed to fetch audio from URL: ${audioRes.statusText}`);
      }
      
      const arrayBuffer = await audioRes.arrayBuffer();
      const buffer = Buffer.from(arrayBuffer);
      const base64Data = buffer.toString("base64");
      const mimeType = audioRes.headers.get("content-type") || "audio/webm";

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

      const response = await ai.models.generateContent({
        model: "gemini-1.5-flash",
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
  app.post("/api/recommendVideos", async (req, res) => {
    const { theme, difficulty } = req.body;

    if (!theme || !difficulty) {
      return res.status(400).json({ error: "theme and difficulty are required" });
    }

    try {
      console.log(`Getting video recommendations for theme: ${theme}, difficulty: ${difficulty}`);

      // Filter catalog
      const themeVids = VIDEO_CATALOG.filter(v => 
        v.theme.toLowerCase() === theme.toLowerCase() || 
        v.difficulty.toLowerCase() === difficulty.toLowerCase().split(' - ')[0].toLowerCase()
      );

      // Shuffle and pick 3
      const shuffled = themeVids.sort(() => 0.5 - Math.random());
      let top3 = shuffled.slice(0, 3);
      
      // Fallback if empty
      if (top3.length === 0) {
        top3 = VIDEO_CATALOG.slice(0, 3);
      }

      const enrichedRecommendations = top3.map((video: any) => ({
        id: video.id,
        title: video.title,
        channel: video.channel,
        difficulty: video.difficulty,
        thumbnail: `https://img.youtube.com/vi/${video.id}/mqdefault.jpg`
      }));

      // Simulate a small delay for the AI feeling requested by the user
      setTimeout(() => {
        res.json(enrichedRecommendations);
      }, 1500);

    } catch (error: any) {
      console.error("Error in recommendVideos:", error);
      res.status(500).json({ error: error.message || "Something went wrong" });
    }
  });

  app.get("/api/test-transcript/:videoId", async (req, res) => {
    try {
      const { videoId } = req.params;
      const response = await fetch(`https://www.youtube.com/watch?v=${videoId}`);
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
  app.post("/api/enrichManualTranscript", async (req, res) => {
    const { transcriptData } = req.body;
    
    if (!transcriptData || !Array.isArray(transcriptData) || transcriptData.length === 0) {
      return res.status(400).json({ error: "transcriptData array is required" });
    }

    try {
      console.log(`Sending ${transcriptData.length} manual transcript items to Gemini...`);

      const prompt = `You are an expert language teacher. I will provide you with a JSON array representing the transcript of an English YouTube video. 
For each item in the array, translate the 'text' into Portuguese (PT-BR) and provide its phonetic transcription using the International Phonetic Alphabet (IPA).
Return the exact same structure but include 'phonetic' and 'translation' fields. Do not alter the start and end values.
Here is the transcript data:
${JSON.stringify(transcriptData, null, 2)}`;

      const response = await ai.models.generateContent({
        model: "gemini-1.5-flash",
        contents: prompt,
        config: {
          responseMimeType: "application/json",
          responseSchema: ENRICHED_TRANSCRIPT_SCHEMA,
          temperature: 0.2, // Low temperature for more deterministic output
        },
      });

      const responseText = response.text;
      if (!responseText) {
          throw new Error("Empty response from Gemini.");
      }
      const enrichedPhrases = JSON.parse(responseText);
      
      console.log(`Successfully generated ${enrichedPhrases.length} enriched phrases (manual).`);
      return res.json(enrichedPhrases);

    } catch (error: any) {
      console.error("Error in enrichManualTranscript:", error);
      res.status(500).json({ error: error.message || "Failed to parse manual transcript" });
    }
  });

  // API Route for fetching and enriching the transcript
  app.post("/api/getEnrichedTranscript", async (req, res) => {
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

      const transcriptData = groupSegmentsForShadowing(transcriptSegments);

      console.log(`Sending ${transcriptData.length} items to Gemini...`);

      let enrichedPhrases;
      try {
        enrichedPhrases = await enrichTranscript(transcriptData);
      } catch (enrichmentError: any) {
        console.error("Transcript enrichment failed:", enrichmentError.message);
        res.setHeader("X-Transcript-Enrichment", "failed");
        return res.json(transcriptData.map((phrase) => ({
          ...phrase,
          phonetic: "",
          translation: "",
        })));
      }
      
      console.log(`Successfully generated ${enrichedPhrases.length} enriched phrases.`);
      res.json(enrichedPhrases);
    } catch (error: any) {
      console.error("Transcript pipeline failed:", error.message);
      return res.status(400).json({
        error: "Não consegui acessar legendas públicas para este vídeo. Tente um vídeo com captions/legenda automática visível no YouTube.",
        details: process.env.NODE_ENV === "production" ? undefined : error.message,
      });
    }
  });

  // Vite middleware for development
  if (process.env.NODE_ENV !== "production") {
    const vite = await createViteServer({
      server: { middlewareMode: true },
      appType: "spa",
    });
    app.use(vite.middlewares);
  } else {
    const distPath = path.join(process.cwd(), "dist");
    app.use(express.static(distPath));
    app.get("*", (req, res) => {
      res.sendFile(path.join(distPath, "index.html"));
    });
  }

  app.listen(PORT, "0.0.0.0", () => {
    console.log(`Server running on http://localhost:${PORT}`);
  });
}

startServer();
