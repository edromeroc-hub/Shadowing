import { randomUUID } from 'node:crypto';
import express, { type NextFunction, type Request, type Response } from 'express';
import { createClient, type SupabaseClient, type User } from '@supabase/supabase-js';

type CommercialRequest = Request & {
  commercialUser?: User;
};

type ContentRights = {
  basis: string;
  status: string;
  rights_holder: string;
  source_url: string;
  license_name: string | null;
  license_url: string | null;
  attribution_text: string | null;
  commercial_use: boolean;
  streaming_allowed: boolean;
  offline_download_allowed: boolean;
  allowed_territories: string[] | null;
  valid_from: string | null;
  valid_through: string | null;
};

type ContentAsset = {
  id: string;
  kind: string;
  storage_bucket: string;
  storage_path: string;
  language_code: string | null;
  mime_type: string;
};

type LessonSegment = {
  id: string;
  position: number;
  start_seconds: number | string;
  end_seconds: number | string;
  text: string;
  translation: string;
};

type Lesson = {
  id: string;
  title: string;
  version: number;
  status: string;
  lesson_segments: LessonSegment[] | null;
};

type ContentRecord = {
  id: string;
  slug: string;
  title: string;
  description: string;
  creator: string;
  source_country: string | null;
  primary_language: string;
  difficulty: string;
  theme: string;
  duration_seconds: number | string;
  artwork_path: string | null;
  published_at: string | null;
  content_rights: ContentRights | ContentRights[] | null;
  content_assets: ContentAsset[] | null;
  lessons: Lesson[] | null;
};

function readBoolean(value: string | undefined, fallback = false) {
  if (value == null || value.trim() === '') return fallback;
  return value.trim().toLowerCase() === 'true';
}

function parseAllowedOrigins() {
  const defaults = ['capacitor://localhost', 'http://localhost', 'http://localhost:3000'];
  const configured = String(process.env.APP_ALLOWED_ORIGINS || '')
    .split(',')
    .map((origin) => origin.trim())
    .filter(Boolean);
  return new Set([...defaults, ...configured]);
}

function isUuid(value: unknown): value is string {
  return typeof value === 'string'
    && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

function singleRelation<T>(value: T | T[] | null | undefined): T | null {
  if (Array.isArray(value)) return value[0] || null;
  return value || null;
}

function dateIsActive(rights: ContentRights) {
  const today = new Date().toISOString().slice(0, 10);
  return (!rights.valid_from || rights.valid_from <= today)
    && (!rights.valid_through || rights.valid_through >= today);
}

function territoryIsAllowed(rights: ContentRights, countryCode: string | null) {
  const territories = rights.allowed_territories || [];
  if (territories.length === 0) return false;
  return Boolean(countryCode && territories.includes(countryCode.toUpperCase()));
}

function contentIsAvailable(content: ContentRecord, countryCode: string | null) {
  const rights = singleRelation(content.content_rights);
  return Boolean(
    rights
      && rights.status === 'approved'
      && rights.commercial_use
      && rights.streaming_allowed
      && dateIsActive(rights)
      && territoryIsAllowed(rights, countryCode),
  );
}

function createServerClient(url: string, key: string) {
  return createClient(url, key, {
    auth: {
      autoRefreshToken: false,
      detectSessionInUrl: false,
      persistSession: false,
    },
  });
}

async function signAsset(client: SupabaseClient, asset: ContentAsset | null, expiresIn = 3600) {
  if (!asset) return null;
  const { data, error } = await client.storage
    .from(asset.storage_bucket)
    .createSignedUrl(asset.storage_path, expiresIn);
  if (error) throw error;
  return data.signedUrl;
}

function pickPublishedLesson(content: ContentRecord) {
  return [...(content.lessons || [])]
    .filter((lesson) => lesson.status === 'published')
    .sort((left, right) => right.version - left.version)[0] || null;
}

async function serializeContent(client: SupabaseClient, content: ContentRecord, includeLesson: boolean) {
  const assets = content.content_assets || [];
  const artworkAsset = assets.find((asset) => asset.kind === 'artwork') || null;
  const lesson = pickPublishedLesson(content);
  const segments = [...(lesson?.lesson_segments || [])]
    .sort((left, right) => left.position - right.position)
    .map((segment) => ({
      id: segment.id,
      position: segment.position,
      start: Number(segment.start_seconds),
      end: Number(segment.end_seconds),
      text: segment.text,
      translation: segment.translation,
    }));

  let artworkUrl: string | null = null;
  try {
    artworkUrl = await signAsset(client, artworkAsset, 6 * 60 * 60);
  } catch (error) {
    console.warn(`[commercial] artwork unavailable for ${content.slug}`, error);
  }

  return {
    id: content.id,
    slug: content.slug,
    title: content.title,
    description: content.description,
    creator: content.creator,
    sourceCountry: content.source_country,
    primaryLanguage: content.primary_language,
    difficulty: content.difficulty,
    theme: content.theme,
    durationSeconds: Number(content.duration_seconds),
    publishedAt: content.published_at,
    artworkUrl,
    offlineAvailable: Boolean(singleRelation(content.content_rights)?.offline_download_allowed),
    rights: (() => {
      const rights = singleRelation(content.content_rights);
      return rights
        ? {
            basis: rights.basis,
            rightsHolder: rights.rights_holder,
            sourceUrl: rights.source_url,
            licenseName: rights.license_name,
            licenseUrl: rights.license_url,
            attributionText: rights.attribution_text,
          }
        : null;
    })(),
    lesson: lesson
      ? {
          id: lesson.id,
          title: lesson.title,
          version: lesson.version,
          segmentCount: segments.length,
          ...(includeLesson ? { segments } : {}),
        }
      : null,
  };
}

const CONTENT_SELECT = `
  id,
  slug,
  title,
  description,
  creator,
  source_country,
  primary_language,
  difficulty,
  theme,
  duration_seconds,
  artwork_path,
  published_at,
  content_rights!inner(basis, status, rights_holder, source_url, license_name, license_url, attribution_text, commercial_use, streaming_allowed, offline_download_allowed, allowed_territories, valid_from, valid_through),
  content_assets(id, kind, storage_bucket, storage_path, language_code, mime_type),
  lessons(id, title, version, status, lesson_segments(id, position, start_seconds, end_seconds, text, translation))
`;

export function createCommercialBackend() {
  const router = express.Router();
  const allowedOrigins = parseAllowedOrigins();
  const cloudMode = readBoolean(process.env.COMMERCIAL_CLOUD_MODE, false);
  const supabaseUrl = String(process.env.SUPABASE_URL || '').trim();
  const publishableKey = String(process.env.SUPABASE_PUBLISHABLE_KEY || '').trim();
  const secretKey = String(process.env.SUPABASE_SECRET_KEY || process.env.SUPABASE_SERVICE_ROLE_KEY || '').trim();
  const configured = Boolean(supabaseUrl && publishableKey && secretKey);
  const authClient = configured ? createServerClient(supabaseUrl, publishableKey) : null;
  const adminClient = configured ? createServerClient(supabaseUrl, secretKey) : null;

  router.use((req, res, next) => {
    const origin = req.headers.origin;
    if (origin && allowedOrigins.has(origin)) {
      res.setHeader('Access-Control-Allow-Origin', origin);
      res.setHeader('Vary', 'Origin');
      res.setHeader('Access-Control-Allow-Headers', 'Authorization, Content-Type');
      res.setHeader('Access-Control-Allow-Methods', 'GET, PUT, DELETE, OPTIONS');
    }
    if (req.method === 'OPTIONS') return res.sendStatus(204);
    return next();
  });

  const requireAuth = async (req: CommercialRequest, res: Response, next: NextFunction) => {
    if (!configured || !authClient) {
      return res.status(503).json({ error: 'O backend comercial ainda não foi configurado.' });
    }

    const authorization = String(req.headers.authorization || '');
    const token = authorization.startsWith('Bearer ') ? authorization.slice(7).trim() : '';
    if (!token) return res.status(401).json({ error: 'Faça login para continuar.' });

    const { data, error } = await authClient.auth.getUser(token);
    if (error || !data.user) return res.status(401).json({ error: 'Sua sessão expirou. Entre novamente.' });

    req.commercialUser = data.user;
    return next();
  };

  async function getCountryCode(userId: string) {
    if (!adminClient) return null;
    const { data } = await adminClient
      .from('profiles')
      .select('country_code')
      .eq('id', userId)
      .maybeSingle();
    return data?.country_code ? String(data.country_code).toUpperCase() : null;
  }

  async function getContentBySlug(slug: string) {
    if (!adminClient) return null;
    const { data, error } = await adminClient
      .from('content_items')
      .select(CONTENT_SELECT)
      .eq('slug', slug)
      .eq('status', 'published')
      .maybeSingle();
    if (error) throw error;
    return data as unknown as ContentRecord | null;
  }

  async function ensureContentAccess(userId: string, content: ContentRecord | null) {
    if (!content) return false;
    return contentIsAvailable(content, await getCountryCode(userId));
  }

  const protectAi = async (req: CommercialRequest, res: Response, next: NextFunction) => {
    if (!cloudMode) return next();

    return requireAuth(req, res, async () => {
      if (!adminClient || !req.commercialUser) return;

      const { data: entitlement, error } = await adminClient
        .from('user_entitlements')
        .select('plan, status, ai_monthly_limit, current_period_start, current_period_end')
        .eq('user_id', req.commercialUser.id)
        .maybeSingle();

      if (error) return res.status(500).json({ error: 'Não foi possível validar seu plano.' });
      if (!entitlement || !['active', 'trialing'].includes(entitlement.status)) {
        return res.status(403).json({ error: 'Seu plano não está ativo.' });
      }

      const { count, error: countError } = await adminClient
        .from('ai_usage_events')
        .select('id', { count: 'exact', head: true })
        .eq('user_id', req.commercialUser.id)
        .gte('created_at', entitlement.current_period_start)
        .lt('created_at', entitlement.current_period_end);

      if (countError) return res.status(500).json({ error: 'Não foi possível validar seu limite de IA.' });
      if ((count || 0) >= entitlement.ai_monthly_limit) {
        return res.status(429).json({ error: 'Você atingiu o limite mensal de recursos com IA.' });
      }

      const { error: usageError } = await adminClient.from('ai_usage_events').insert({
        user_id: req.commercialUser.id,
        feature: req.path.replace(/^\//, '') || 'ai',
        request_id: randomUUID(),
      });
      if (usageError) return res.status(500).json({ error: 'Não foi possível registrar o uso da IA.' });

      return next();
    });
  };

  router.get('/health', (_req, res) => {
    res.json({ configured, cloudMode, service: 'shadowing-commercial-backend' });
  });

  router.get('/me', requireAuth, async (req: CommercialRequest, res) => {
    if (!adminClient || !req.commercialUser) return;
    const [profileResult, entitlementResult] = await Promise.all([
      adminClient.from('profiles').select('display_name, preferred_locale, country_code').eq('id', req.commercialUser.id).maybeSingle(),
      adminClient.from('user_entitlements').select('plan, status, ai_monthly_limit, current_period_start, current_period_end').eq('user_id', req.commercialUser.id).maybeSingle(),
    ]);
    if (profileResult.error || entitlementResult.error) {
      return res.status(500).json({ error: 'Não foi possível carregar sua conta.' });
    }
    return res.json({
      id: req.commercialUser.id,
      email: req.commercialUser.email,
      profile: profileResult.data,
      entitlement: entitlementResult.data,
    });
  });

  router.put('/me', requireAuth, async (req: CommercialRequest, res) => {
    if (!adminClient || !req.commercialUser) return;
    const displayName = String(req.body?.displayName || '').trim();
    const countryCode = String(req.body?.countryCode || '').trim().toUpperCase();
    if (displayName.length < 2 || displayName.length > 80) {
      return res.status(400).json({ error: 'Informe um nome entre 2 e 80 caracteres.' });
    }
    if (!/^[A-Z]{2}$/.test(countryCode)) {
      return res.status(400).json({ error: 'País inválido.' });
    }
    const { data, error } = await adminClient
      .from('profiles')
      .update({ display_name: displayName, country_code: countryCode })
      .eq('id', req.commercialUser.id)
      .select('display_name, preferred_locale, country_code')
      .single();
    if (error) return res.status(500).json({ error: 'Não foi possível atualizar seu perfil.' });
    return res.json(data);
  });

  router.delete('/me', requireAuth, async (req: CommercialRequest, res) => {
    if (!adminClient || !req.commercialUser) return;
    if (req.body?.confirm !== 'DELETE') {
      return res.status(400).json({ error: 'Confirmação de exclusão inválida.' });
    }
    const { error } = await adminClient.auth.admin.deleteUser(req.commercialUser.id);
    if (error) return res.status(500).json({ error: 'Não foi possível excluir sua conta.' });
    return res.sendStatus(204);
  });

  router.get('/catalog', requireAuth, async (req: CommercialRequest, res) => {
    if (!adminClient || !req.commercialUser) return;
    const theme = typeof req.query.theme === 'string' ? req.query.theme : null;
    const difficulty = typeof req.query.difficulty === 'string' ? req.query.difficulty : null;
    let query = adminClient
      .from('content_items')
      .select(CONTENT_SELECT)
      .eq('status', 'published')
      .order('published_at', { ascending: false });
    if (theme) query = query.eq('theme', theme);
    if (difficulty) query = query.eq('difficulty', difficulty);

    const { data, error } = await query;
    if (error) return res.status(500).json({ error: 'Não foi possível carregar o catálogo.' });

    const countryCode = await getCountryCode(req.commercialUser.id);
    const available = (data as unknown as ContentRecord[]).filter((content) => contentIsAvailable(content, countryCode));
    return res.json(await Promise.all(available.map((content) => serializeContent(adminClient, content, false))));
  });

  router.get('/catalog/:slug', requireAuth, async (req: CommercialRequest, res) => {
    if (!adminClient || !req.commercialUser) return;
    try {
      const content = await getContentBySlug(req.params.slug);
      if (!await ensureContentAccess(req.commercialUser.id, content)) {
        return res.status(404).json({ error: 'Conteúdo não encontrado ou indisponível em sua região.' });
      }
      return res.json(await serializeContent(adminClient, content!, true));
    } catch (error) {
      console.error('[commercial] catalog detail failed', error);
      return res.status(500).json({ error: 'Não foi possível carregar esta aula.' });
    }
  });

  router.get('/catalog/:slug/media', requireAuth, async (req: CommercialRequest, res) => {
    if (!adminClient || !req.commercialUser) return;
    try {
      const content = await getContentBySlug(req.params.slug);
      if (!await ensureContentAccess(req.commercialUser.id, content)) {
        return res.status(404).json({ error: 'Conteúdo não encontrado ou indisponível em sua região.' });
      }
      const wantsOfflineDownload = req.query.download === '1';
      const rights = singleRelation(content!.content_rights);
      if (wantsOfflineDownload && !rights?.offline_download_allowed) {
        return res.status(403).json({ error: 'A licença deste conteúdo não permite download offline.' });
      }
      const kind = req.query.kind === 'audio' ? 'audio' : 'video';
      const asset = content!.content_assets?.find((candidate) => candidate.kind === kind) || null;
      if (!asset) return res.status(404).json({ error: 'Mídia indisponível para esta aula.' });
      const signedUrl = await signAsset(adminClient, asset, 60 * 60);
      return res.json({ url: signedUrl, expiresIn: 3600, mimeType: asset.mime_type });
    } catch (error) {
      console.error('[commercial] signed media failed', error);
      return res.status(500).json({ error: 'Não foi possível liberar a mídia.' });
    }
  });

  router.get('/progress', requireAuth, async (req: CommercialRequest, res) => {
    if (!adminClient || !req.commercialUser) return;
    const { data, error } = await adminClient
      .from('user_progress')
      .select('content_id, lesson_id, segment_position, completed_percent, seconds_studied, state, last_studied_at')
      .eq('user_id', req.commercialUser.id)
      .order('last_studied_at', { ascending: false });
    if (error) return res.status(500).json({ error: 'Não foi possível carregar seu progresso.' });
    return res.json(data);
  });

  router.put('/progress/:contentId', requireAuth, async (req: CommercialRequest, res) => {
    if (!adminClient || !req.commercialUser) return;
    const contentId = req.params.contentId;
    const lessonId = req.body?.lessonId;
    const segmentPosition = Number(req.body?.segmentPosition ?? 0);
    const completedPercent = Number(req.body?.completedPercent ?? 0);
    const secondsStudied = Number(req.body?.secondsStudied ?? 0);
    const state = req.body?.state && typeof req.body.state === 'object' ? req.body.state : {};

    if (!isUuid(contentId) || (lessonId != null && !isUuid(lessonId))) {
      return res.status(400).json({ error: 'Identificador de conteúdo inválido.' });
    }
    if (!Number.isInteger(segmentPosition) || segmentPosition < 0) {
      return res.status(400).json({ error: 'Posição de frase inválida.' });
    }
    if (!Number.isFinite(completedPercent) || completedPercent < 0 || completedPercent > 100) {
      return res.status(400).json({ error: 'Percentual de conclusão inválido.' });
    }
    if (!Number.isInteger(secondsStudied) || secondsStudied < 0) {
      return res.status(400).json({ error: 'Tempo de estudo inválido.' });
    }

    const { data: content } = await adminClient
      .from('content_items')
      .select(CONTENT_SELECT)
      .eq('id', contentId)
      .eq('status', 'published')
      .maybeSingle();
    if (!await ensureContentAccess(req.commercialUser.id, content as unknown as ContentRecord | null)) {
      return res.status(404).json({ error: 'Conteúdo indisponível.' });
    }

    const { data, error } = await adminClient
      .from('user_progress')
      .upsert({
        user_id: req.commercialUser.id,
        content_id: contentId,
        lesson_id: lessonId || null,
        segment_position: segmentPosition,
        completed_percent: completedPercent,
        seconds_studied: secondsStudied,
        state,
        last_studied_at: new Date().toISOString(),
      }, { onConflict: 'user_id,content_id' })
      .select('content_id, lesson_id, segment_position, completed_percent, seconds_studied, state, last_studied_at')
      .single();
    if (error) return res.status(500).json({ error: 'Não foi possível salvar seu progresso.' });
    return res.json(data);
  });

  return {
    router,
    protectAi,
    configured,
    cloudMode,
  };
}
