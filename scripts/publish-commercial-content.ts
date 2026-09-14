import 'dotenv/config';
import { createHash, randomUUID } from 'node:crypto';
import { createReadStream } from 'node:fs';
import path from 'node:path';
import { readFile, stat } from 'node:fs/promises';
import { applicationDefault, getApps, initializeApp } from 'firebase-admin/app';
import { FieldValue, Timestamp, getFirestore } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';

type AssetInput = {
  file: string;
  mimeType?: string;
  languageCode?: string;
};

type Manifest = {
  legalReviewConfirmed: boolean;
  slug: string;
  title: string;
  description: string;
  creator: string;
  sourceCountry?: string;
  primaryLanguage?: string;
  difficulty: 'beginner' | 'intermediate' | 'advanced';
  theme: string;
  durationSeconds: number;
  rights: {
    basis: 'owned' | 'licensed' | 'public_domain' | 'open_license';
    rightsHolder: string;
    rightsContact?: string;
    sourceUrl: string;
    licenseName?: string;
    licenseUrl?: string;
    attributionText?: string;
    evidence: string;
    notes?: string;
    allowedTerritories: string[];
    derivativeWorks: boolean;
    streamingAllowed: boolean;
    offlineDownloadAllowed: boolean;
    translationAllowed: boolean;
    validFrom?: string;
    validThrough?: string;
    reviewedBy?: string;
  };
  assets: {
    video: AssetInput;
    artwork?: AssetInput;
    captions?: AssetInput;
    transcript?: AssetInput;
    audio?: AssetInput;
  };
  lesson: {
    title: string;
    version: number;
    aiModel?: string;
    promptVersion?: string;
    reviewedBy?: string;
    segments: Array<{
      start: number;
      end: number;
      text: string;
      translation: string;
      difficulty?: 'beginner' | 'intermediate' | 'advanced';
    }>;
  };
};

const mimeByExtension: Record<string, string> = {
  '.json': 'application/json',
  '.jpeg': 'image/jpeg',
  '.jpg': 'image/jpeg',
  '.m4a': 'audio/mp4',
  '.mov': 'video/quicktime',
  '.mp3': 'audio/mpeg',
  '.mp4': 'video/mp4',
  '.pdf': 'application/pdf',
  '.png': 'image/png',
  '.txt': 'text/plain',
  '.vtt': 'text/vtt',
  '.webp': 'image/webp',
};

function requiredEnvironment(name: string) {
  const value = String(process.env[name] || '').trim();
  if (!value) throw new Error(`Variável obrigatória ausente: ${name}`);
  return value;
}

function resolveInputFile(manifestDirectory: string, file: string) {
  return path.resolve(manifestDirectory, file);
}

async function hashFile(file: string) {
  const hash = createHash('sha256');
  for await (const chunk of createReadStream(file)) hash.update(chunk);
  return hash.digest('hex');
}

function validateManifest(manifest: Manifest) {
  if (manifest.legalReviewConfirmed !== true) {
    throw new Error('A publicação exige legalReviewConfirmed=true após revisão documental dos direitos.');
  }
  if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(manifest.slug)) throw new Error('slug inválido.');
  if (!manifest.title.trim() || !manifest.creator.trim()) throw new Error('Título e criador são obrigatórios.');
  if (!Number.isFinite(manifest.durationSeconds) || manifest.durationSeconds <= 0) throw new Error('durationSeconds inválido.');
  if (!manifest.assets?.video?.file) throw new Error('O arquivo de vídeo é obrigatório.');
  if (!manifest.rights?.evidence) throw new Error('O arquivo de comprovação dos direitos é obrigatório.');
  if (!manifest.rights.rightsHolder?.trim() || !manifest.rights.sourceUrl?.trim()) {
    throw new Error('Titular dos direitos e URL da fonte original são obrigatórios.');
  }
  if (!manifest.rights.streamingAllowed || !manifest.rights.translationAllowed) {
    throw new Error('A licença deve autorizar streaming e tradução para este produto.');
  }
  if (!Array.isArray(manifest.rights.allowedTerritories) || manifest.rights.allowedTerritories.length === 0) {
    throw new Error('Informe explicitamente pelo menos um território autorizado.');
  }
  if (!manifest.rights.allowedTerritories.every((territory) => /^[A-Za-z]{2}$/.test(territory.trim()))) {
    throw new Error('Cada território deve usar um código ISO de duas letras, como BR ou US.');
  }
  if (!Array.isArray(manifest.lesson?.segments) || manifest.lesson.segments.length === 0) {
    throw new Error('A aula precisa de pelo menos um segmento revisado.');
  }
  manifest.lesson.segments.forEach((segment, index) => {
    if (!Number.isFinite(segment.start) || !Number.isFinite(segment.end) || segment.start < 0 || segment.end <= segment.start) {
      throw new Error(`Tempo inválido no segmento ${index + 1}.`);
    }
    if (!segment.text.trim()) throw new Error(`Texto vazio no segmento ${index + 1}.`);
  });
}

async function main() {
  const manifestArgument = process.argv[2];
  if (!manifestArgument) throw new Error('Uso: npm run content:publish -- content/catalog/meu-conteudo.json');

  const manifestPath = path.resolve(process.cwd(), manifestArgument);
  const manifestDirectory = path.dirname(manifestPath);
  const manifest = JSON.parse(await readFile(manifestPath, 'utf8')) as Manifest;
  validateManifest(manifest);

  const projectId = requiredEnvironment('FIREBASE_PROJECT_ID');
  const storageBucket = String(process.env.FIREBASE_STORAGE_BUCKET || `${projectId}.firebasestorage.app`).trim();
  const app = getApps()[0] || initializeApp({
    credential: applicationDefault(),
    projectId,
    storageBucket,
  });
  const db = getFirestore(app);
  const bucket = getStorage(app).bucket(storageBucket);

  const upload = async (objectPath: string, inputFile: string, explicitMimeType?: string) => {
    const absolutePath = resolveInputFile(manifestDirectory, inputFile);
    const fileInfo = await stat(absolutePath);
    const contentType = explicitMimeType || mimeByExtension[path.extname(absolutePath).toLowerCase()];
    if (!contentType) throw new Error(`Informe mimeType para ${inputFile}.`);
    await bucket.upload(absolutePath, {
      destination: objectPath,
      resumable: fileInfo.size > 5 * 1024 * 1024,
      metadata: {
        contentType,
        cacheControl: 'private, max-age=0, no-store',
      },
    });
    return { contentType, sizeBytes: fileInfo.size };
  };

  const existing = await db.collection('contentItems').where('slug', '==', manifest.slug).limit(1).get();
  const contentId = existing.docs[0]?.id || randomUUID();
  const contentRef = db.collection('contentItems').doc(contentId);
  await contentRef.set({
    slug: manifest.slug,
    title: manifest.title.trim(),
    description: manifest.description.trim(),
    creator: manifest.creator.trim(),
    sourceCountry: manifest.sourceCountry?.toUpperCase() || null,
    primaryLanguage: manifest.primaryLanguage || 'en',
    difficulty: manifest.difficulty,
    theme: manifest.theme,
    durationSeconds: manifest.durationSeconds,
    status: 'draft',
    publishedAt: null,
    updatedAt: FieldValue.serverTimestamp(),
    createdAt: existing.empty
      ? FieldValue.serverTimestamp()
      : existing.docs[0].data().createdAt || FieldValue.serverTimestamp(),
  }, { merge: true });

  const evidencePath = `rights-evidence/${manifest.slug}/${Date.now()}-${path.basename(manifest.rights.evidence)}`;
  await upload(evidencePath, manifest.rights.evidence);
  const sourceFileSha256 = await hashFile(resolveInputFile(manifestDirectory, manifest.assets.video.file));

  const assetEntries = Object.entries(manifest.assets)
    .filter((entry): entry is [keyof Manifest['assets'], AssetInput] => Boolean(entry[1]?.file));
  const assets = [];
  for (const [kind, asset] of assetEntries) {
    const objectPath = `lesson-assets/${manifest.slug}/${kind}${path.extname(asset.file).toLowerCase()}`;
    const uploaded = await upload(objectPath, asset.file, asset.mimeType);
    assets.push({
      kind,
      storagePath: objectPath,
      languageCode: asset.languageCode || (kind === 'captions' || kind === 'transcript' ? 'en' : null),
      mimeType: uploaded.contentType,
      sizeBytes: uploaded.sizeBytes,
      durationSeconds: kind === 'video' || kind === 'audio' ? manifest.durationSeconds : null,
    });
  }

  const lessonId = randomUUID();
  const segments = manifest.lesson.segments.map((segment, position) => ({
    id: randomUUID(),
    position,
    start: segment.start,
    end: segment.end,
    text: segment.text.trim(),
    translation: segment.translation.trim(),
    difficulty: segment.difficulty || null,
  }));
  if (Buffer.byteLength(JSON.stringify(segments), 'utf8') > 800_000) {
    throw new Error('A lista de segmentos excede o limite seguro de tamanho de um documento Firestore.');
  }

  const lessonRef = db.collection('lessons').doc(lessonId);
  await lessonRef.set({
    contentId,
    title: manifest.lesson.title,
    version: manifest.lesson.version,
    status: 'draft',
    aiModel: manifest.lesson.aiModel || null,
    segmentationPromptVersion: manifest.lesson.promptVersion || null,
    reviewedBy: manifest.lesson.reviewedBy || null,
    reviewedAt: null,
    segments,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });

  const reviewedAt = Timestamp.now();
  const rights = {
    basis: manifest.rights.basis,
    status: 'approved',
    rightsHolder: manifest.rights.rightsHolder.trim(),
    rightsContact: manifest.rights.rightsContact?.trim() || null,
    sourceUrl: manifest.rights.sourceUrl.trim(),
    sourceFileSha256,
    licenseName: manifest.rights.licenseName || null,
    licenseUrl: manifest.rights.licenseUrl || null,
    attributionText: manifest.rights.attributionText || null,
    evidencePath,
    notes: manifest.rights.notes || '',
    allowedTerritories: [...new Set(manifest.rights.allowedTerritories.map((territory) => territory.trim().toUpperCase()))],
    commercialUse: true,
    derivativeWorks: manifest.rights.derivativeWorks,
    streamingAllowed: manifest.rights.streamingAllowed,
    offlineDownloadAllowed: manifest.rights.offlineDownloadAllowed,
    translationAllowed: manifest.rights.translationAllowed,
    validFrom: manifest.rights.validFrom || null,
    validThrough: manifest.rights.validThrough || null,
    reviewedAt,
    reviewedBy: manifest.rights.reviewedBy || null,
  };

  const batch = db.batch();
  batch.update(lessonRef, { status: 'published', reviewedAt, updatedAt: FieldValue.serverTimestamp() });
  batch.set(contentRef, {
    rights,
    assets,
    publishedLessonId: lessonId,
    status: 'published',
    publishedAt: reviewedAt,
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  await batch.commit();

  console.log(`Conteúdo publicado no Firebase: ${manifest.title} (${contentId})`);
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
