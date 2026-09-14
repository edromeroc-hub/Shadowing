import 'dotenv/config';
import { createHash } from 'node:crypto';
import path from 'node:path';
import { readFile } from 'node:fs/promises';
import { createClient } from '@supabase/supabase-js';

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
    throw new Error('Cada território autorizado deve usar um código ISO de duas letras, como BR ou US.');
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
  if (!manifestArgument) {
    throw new Error('Uso: npm run content:publish -- content/catalog/meu-conteudo.json');
  }

  const manifestPath = path.resolve(process.cwd(), manifestArgument);
  const manifestDirectory = path.dirname(manifestPath);
  const manifest = JSON.parse(await readFile(manifestPath, 'utf8')) as Manifest;
  validateManifest(manifest);

  const supabase = createClient(
    requiredEnvironment('SUPABASE_URL'),
    requiredEnvironment('SUPABASE_SECRET_KEY'),
    { auth: { autoRefreshToken: false, persistSession: false } },
  );

  const upload = async (bucket: string, objectPath: string, inputFile: string, explicitMimeType?: string) => {
    const absolutePath = resolveInputFile(manifestDirectory, inputFile);
    const body = await readFile(absolutePath);
    const contentType = explicitMimeType || mimeByExtension[path.extname(absolutePath).toLowerCase()];
    if (!contentType) throw new Error(`Informe mimeType para ${inputFile}.`);
    const { error } = await supabase.storage.from(bucket).upload(objectPath, body, {
      contentType,
      upsert: true,
    });
    if (error) throw error;
    return { absolutePath, contentType, sizeBytes: body.byteLength };
  };

  const now = new Date().toISOString();
  const { data: content, error: contentError } = await supabase
    .from('content_items')
    .upsert({
      slug: manifest.slug,
      title: manifest.title.trim(),
      description: manifest.description.trim(),
      creator: manifest.creator.trim(),
      source_country: manifest.sourceCountry?.toUpperCase() || null,
      primary_language: manifest.primaryLanguage || 'en',
      difficulty: manifest.difficulty,
      theme: manifest.theme,
      duration_seconds: manifest.durationSeconds,
      status: 'draft',
      published_at: null,
    }, { onConflict: 'slug' })
    .select('id')
    .single();
  if (contentError) throw contentError;

  const contentId = content.id;
  const evidenceFileName = path.basename(manifest.rights.evidence);
  const evidencePath = `${manifest.slug}/${Date.now()}-${evidenceFileName}`;
  await upload('rights-evidence', evidencePath, manifest.rights.evidence);
  const sourceVideo = await readFile(resolveInputFile(manifestDirectory, manifest.assets.video.file));
  const sourceFileSha256 = createHash('sha256').update(sourceVideo).digest('hex');

  const { error: rightsDraftError } = await supabase.from('content_rights').upsert({
    content_id: contentId,
    basis: manifest.rights.basis,
    status: 'pending',
    rights_holder: manifest.rights.rightsHolder.trim(),
    rights_contact: manifest.rights.rightsContact?.trim() || null,
    source_url: manifest.rights.sourceUrl.trim(),
    source_file_sha256: sourceFileSha256,
    license_name: manifest.rights.licenseName || null,
    license_url: manifest.rights.licenseUrl || null,
    attribution_text: manifest.rights.attributionText || null,
    evidence_path: evidencePath,
    notes: manifest.rights.notes || '',
    allowed_territories: manifest.rights.allowedTerritories.map((territory) => territory.toUpperCase()),
    commercial_use: true,
    derivative_works: manifest.rights.derivativeWorks,
    streaming_allowed: manifest.rights.streamingAllowed,
    offline_download_allowed: manifest.rights.offlineDownloadAllowed,
    translation_allowed: manifest.rights.translationAllowed,
    valid_from: manifest.rights.validFrom || null,
    valid_through: manifest.rights.validThrough || null,
    reviewed_at: null,
    reviewed_by: manifest.rights.reviewedBy || null,
  });
  if (rightsDraftError) throw rightsDraftError;

  const assetEntries = Object.entries(manifest.assets).filter((entry): entry is [keyof Manifest['assets'], AssetInput] => Boolean(entry[1]?.file));
  const uploadedAssets = [];
  let artworkPath: string | null = null;
  for (const [kind, asset] of assetEntries) {
    const bucket = kind === 'artwork' ? 'lesson-artwork' : 'lesson-media';
    const objectPath = `${manifest.slug}/${kind}${path.extname(asset.file).toLowerCase()}`;
    const uploaded = await upload(bucket, objectPath, asset.file, asset.mimeType);
    if (kind === 'artwork') artworkPath = objectPath;
    uploadedAssets.push({
      content_id: contentId,
      kind,
      storage_bucket: bucket,
      storage_path: objectPath,
      language_code: asset.languageCode || (kind === 'captions' || kind === 'transcript' ? 'en' : null),
      mime_type: uploaded.contentType,
      size_bytes: uploaded.sizeBytes,
      duration_seconds: kind === 'video' || kind === 'audio' ? manifest.durationSeconds : null,
    });
  }

  const { error: deleteAssetsError } = await supabase.from('content_assets').delete().eq('content_id', contentId);
  if (deleteAssetsError) throw deleteAssetsError;
  const { error: assetsError } = await supabase.from('content_assets').insert(uploadedAssets);
  if (assetsError) throw assetsError;

  if (artworkPath) {
    const { error } = await supabase.from('content_items').update({ artwork_path: artworkPath }).eq('id', contentId);
    if (error) throw error;
  }

  const { data: lesson, error: lessonError } = await supabase
    .from('lessons')
    .upsert({
      content_id: contentId,
      title: manifest.lesson.title,
      version: manifest.lesson.version,
      status: 'draft',
      ai_model: manifest.lesson.aiModel || null,
      segmentation_prompt_version: manifest.lesson.promptVersion || null,
      reviewed_by: manifest.lesson.reviewedBy || null,
      reviewed_at: null,
    }, { onConflict: 'content_id,version' })
    .select('id')
    .single();
  if (lessonError) throw lessonError;

  const { error: deleteSegmentsError } = await supabase.from('lesson_segments').delete().eq('lesson_id', lesson.id);
  if (deleteSegmentsError) throw deleteSegmentsError;
  const { error: segmentsError } = await supabase.from('lesson_segments').insert(
    manifest.lesson.segments.map((segment, position) => ({
      lesson_id: lesson.id,
      position,
      start_seconds: segment.start,
      end_seconds: segment.end,
      text: segment.text.trim(),
      translation: segment.translation.trim(),
      difficulty: segment.difficulty || manifest.difficulty,
    })),
  );
  if (segmentsError) throw segmentsError;

  const { error: approveRightsError } = await supabase.from('content_rights').update({
    status: 'approved',
    reviewed_at: now,
  }).eq('content_id', contentId);
  if (approveRightsError) throw approveRightsError;

  const { error: publishLessonError } = await supabase.from('lessons').update({
    status: 'published',
    reviewed_at: now,
  }).eq('id', lesson.id);
  if (publishLessonError) throw publishLessonError;

  const { error: publishContentError } = await supabase.from('content_items').update({
    status: 'published',
    published_at: now,
  }).eq('id', contentId);
  if (publishContentError) throw publishContentError;

  console.log(`Conteúdo publicado: ${manifest.title} (${manifest.slug})`);
  console.log(`ID: ${contentId}`);
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
