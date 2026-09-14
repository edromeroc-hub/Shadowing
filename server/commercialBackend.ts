import { randomUUID } from 'node:crypto';
import express, { type NextFunction, type Request, type Response } from 'express';
import { applicationDefault, getApps, initializeApp } from 'firebase-admin/app';
import { getAuth, type DecodedIdToken } from 'firebase-admin/auth';
import {
  FieldValue,
  Timestamp,
  getFirestore,
  type Firestore,
  type Query,
} from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';

type StorageBucket = ReturnType<ReturnType<typeof getStorage>['bucket']>;

type CommercialRequest = Request & { commercialUser?: DecodedIdToken };
type CommercialHandler = (
  req: CommercialRequest,
  res: Response,
  next: NextFunction,
) => Promise<unknown>;

type ContentRights = {
  basis: 'owned' | 'licensed' | 'public_domain' | 'open_license';
  status: 'pending' | 'approved' | 'rejected' | 'expired';
  rightsHolder: string;
  sourceUrl: string;
  licenseName: string | null;
  licenseUrl: string | null;
  attributionText: string | null;
  commercialUse: boolean;
  streamingAllowed: boolean;
  offlineDownloadAllowed: boolean;
  translationAllowed: boolean;
  allowedTerritories: string[];
  validFrom: string | null;
  validThrough: string | null;
};

type ContentAsset = {
  kind: 'video' | 'audio' | 'captions' | 'transcript' | 'artwork';
  storagePath: string;
  languageCode: string | null;
  mimeType: string;
  sizeBytes?: number;
};

type LessonSegment = {
  id: string;
  position: number;
  start: number;
  end: number;
  text: string;
  translation: string;
};

type LessonRecord = {
  id: string;
  contentId: string;
  title: string;
  version: number;
  status: 'draft' | 'review' | 'published' | 'archived';
  segments: LessonSegment[];
};

type ContentRecord = {
  id: string;
  slug: string;
  title: string;
  description: string;
  creator: string;
  sourceCountry: string | null;
  primaryLanguage: string;
  difficulty: 'beginner' | 'intermediate' | 'advanced';
  theme: string;
  durationSeconds: number;
  status: 'draft' | 'review' | 'published' | 'archived';
  publishedAt: Timestamp | string | Date | null;
  publishedLessonId: string | null;
  rights: ContentRights;
  assets: ContentAsset[];
};

type FirebaseServices = {
  db: Firestore;
  bucket: StorageBucket;
  auth: ReturnType<typeof getAuth>;
};

class HttpError extends Error {
  status: number;

  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

function asyncRoute(handler: CommercialHandler) {
  return (req: Request, res: Response, next: NextFunction) => {
    void handler(req as CommercialRequest, res, next).catch(next);
  };
}

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

function asIsoString(value: unknown) {
  if (!value) return null;
  if (value instanceof Timestamp) return value.toDate().toISOString();
  if (value instanceof Date) return value.toISOString();
  return String(value);
}

function dateIsActive(rights: ContentRights) {
  const today = new Date().toISOString().slice(0, 10);
  return (!rights.validFrom || rights.validFrom <= today)
    && (!rights.validThrough || rights.validThrough >= today);
}

function territoryIsAllowed(rights: ContentRights, countryCode: string | null) {
  if (!rights.allowedTerritories?.length) return false;
  return Boolean(countryCode && rights.allowedTerritories.includes(countryCode.toUpperCase()));
}

function contentIsAvailable(content: ContentRecord, countryCode: string | null) {
  const rights = content.rights;
  return Boolean(
    content.status === 'published'
      && rights
      && rights.status === 'approved'
      && rights.commercialUse
      && rights.streamingAllowed
      && dateIsActive(rights)
      && territoryIsAllowed(rights, countryCode),
  );
}

function createFirebaseServices(): FirebaseServices | null {
  const projectId = String(
    process.env.FIREBASE_PROJECT_ID
      || process.env.GCLOUD_PROJECT
      || process.env.GOOGLE_CLOUD_PROJECT
      || '',
  ).trim();
  const storageBucket = String(
    process.env.FIREBASE_STORAGE_BUCKET
      || (projectId ? `${projectId}.firebasestorage.app` : ''),
  ).trim();
  if (!projectId || !storageBucket) return null;

  const app = getApps()[0] || initializeApp({
    credential: applicationDefault(),
    projectId,
    storageBucket,
  });
  return {
    db: getFirestore(app),
    bucket: getStorage(app).bucket(storageBucket),
    auth: getAuth(app),
  };
}

async function signAsset(bucket: StorageBucket, asset: ContentAsset | null, expiresIn = 3600) {
  if (!asset) return null;
  const [url] = await bucket.file(asset.storagePath).getSignedUrl({
    action: 'read',
    expires: Date.now() + expiresIn * 1000,
  });
  return url;
}

async function loadLesson(db: Firestore, content: ContentRecord) {
  if (!content.publishedLessonId) return null;
  const snapshot = await db.collection('lessons').doc(content.publishedLessonId).get();
  if (!snapshot.exists) return null;
  const lesson = { id: snapshot.id, ...snapshot.data() } as LessonRecord;
  return lesson.status === 'published' ? lesson : null;
}

async function serializeContent(services: FirebaseServices, content: ContentRecord, includeLesson: boolean) {
  const artworkAsset = content.assets?.find((asset) => asset.kind === 'artwork') || null;
  const lesson = await loadLesson(services.db, content);
  const segments = [...(lesson?.segments || [])].sort((left, right) => left.position - right.position);

  let artworkUrl: string | null = null;
  try {
    artworkUrl = await signAsset(services.bucket, artworkAsset, 6 * 60 * 60);
  } catch (error) {
    console.warn(`[commercial] artwork unavailable for ${content.slug}`, error);
  }

  return {
    id: content.id,
    slug: content.slug,
    title: content.title,
    description: content.description,
    creator: content.creator,
    sourceCountry: content.sourceCountry,
    primaryLanguage: content.primaryLanguage,
    difficulty: content.difficulty,
    theme: content.theme,
    durationSeconds: Number(content.durationSeconds),
    publishedAt: asIsoString(content.publishedAt),
    artworkUrl,
    offlineAvailable: Boolean(content.rights?.offlineDownloadAllowed),
    rights: content.rights
      ? {
          basis: content.rights.basis,
          rightsHolder: content.rights.rightsHolder,
          sourceUrl: content.rights.sourceUrl,
          licenseName: content.rights.licenseName,
          licenseUrl: content.rights.licenseUrl,
          attributionText: content.rights.attributionText,
        }
      : null,
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

async function deleteQuery(db: Firestore, query: Query) {
  let snapshot = await query.limit(400).get();
  while (!snapshot.empty) {
    const batch = db.batch();
    snapshot.docs.forEach((document) => batch.delete(document.ref));
    await batch.commit();
    snapshot = await query.limit(400).get();
  }
}

export function createCommercialBackend() {
  const router = express.Router();
  const allowedOrigins = parseAllowedOrigins();
  const cloudMode = readBoolean(process.env.COMMERCIAL_CLOUD_MODE, false);
  const services = createFirebaseServices();
  const configured = Boolean(services);

  router.use((req, res, next) => {
    const origin = req.headers.origin;
    if (origin && allowedOrigins.has(origin)) {
      res.setHeader('Access-Control-Allow-Origin', origin);
      res.setHeader('Vary', 'Origin');
      res.setHeader('Access-Control-Allow-Headers', 'Authorization, Content-Type');
      res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
    }
    if (req.method === 'OPTIONS') return res.sendStatus(204);
    return next();
  });

  const ensureUserDocuments = async (user: DecodedIdToken) => {
    if (!services) return;
    const profileRef = services.db.collection('profiles').doc(user.uid);
    const entitlementRef = services.db.collection('entitlements').doc(user.uid);
    const [profile, entitlement] = await Promise.all([profileRef.get(), entitlementRef.get()]);
    const batch = services.db.batch();
    if (!profile.exists) {
      batch.set(profileRef, {
        displayName: user.name || user.email?.split('@')[0] || 'Aluno',
        preferredLocale: 'pt-BR',
        countryCode: 'BR',
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    if (!entitlement.exists) {
      const now = new Date();
      const periodEnd = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + 1, 1));
      batch.set(entitlementRef, {
        plan: 'free',
        status: 'active',
        aiMonthlyLimit: 20,
        aiUsedThisPeriod: 0,
        currentPeriodStart: Timestamp.fromDate(new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1))),
        currentPeriodEnd: Timestamp.fromDate(periodEnd),
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    if (!profile.exists || !entitlement.exists) await batch.commit();
  };

  const requireAuth = async (req: CommercialRequest, res: Response, next: NextFunction) => {
    if (!services) return res.status(503).json({ error: 'O backend Firebase ainda não foi configurado.' });
    const authorization = String(req.headers.authorization || '');
    const token = authorization.startsWith('Bearer ') ? authorization.slice(7).trim() : '';
    if (!token) return res.status(401).json({ error: 'Faça login para continuar.' });
    try {
      const decoded = await services.auth.verifyIdToken(token, true);
      await ensureUserDocuments(decoded);
      req.commercialUser = decoded;
      return next();
    } catch {
      return res.status(401).json({ error: 'Sua sessão expirou. Entre novamente.' });
    }
  };

  const consumeAiQuota = async (userId: string, feature: string) => {
    if (!services) throw new HttpError(503, 'O backend Firebase ainda não foi configurado.');
    const entitlementRef = services.db.collection('entitlements').doc(userId);
    const usageRef = services.db.collection('aiUsage').doc(randomUUID());
    await services.db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(entitlementRef);
      if (!snapshot.exists) throw new HttpError(403, 'Seu plano ainda não foi ativado.');
      const entitlement = snapshot.data()!;
      if (!['active', 'trialing'].includes(String(entitlement.status))) {
        throw new HttpError(403, 'Seu plano não está ativo.');
      }

      const now = new Date();
      const existingEnd = entitlement.currentPeriodEnd instanceof Timestamp
        ? entitlement.currentPeriodEnd.toDate()
        : new Date(0);
      const resetPeriod = existingEnd <= now;
      const used = resetPeriod ? 0 : Number(entitlement.aiUsedThisPeriod || 0);
      const limit = Number(entitlement.aiMonthlyLimit || 0);
      if (used >= limit) throw new HttpError(429, 'Você atingiu o limite mensal de análises por IA.');

      const periodStart = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1));
      const periodEnd = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + 1, 1));
      transaction.update(entitlementRef, {
        aiUsedThisPeriod: used + 1,
        ...(resetPeriod ? {
          currentPeriodStart: Timestamp.fromDate(periodStart),
          currentPeriodEnd: Timestamp.fromDate(periodEnd),
        } : {}),
        updatedAt: FieldValue.serverTimestamp(),
      });
      transaction.set(usageRef, {
        userId,
        feature,
        requestId: usageRef.id,
        inputUnits: 0,
        outputUnits: 0,
        estimatedCostUsd: 0,
        createdAt: FieldValue.serverTimestamp(),
      });
    });
  };

  const protectAi = async (req: CommercialRequest, res: Response, next: NextFunction) => {
    if (!cloudMode) return next();
    return requireAuth(req, res, async () => {
      try {
        await consumeAiQuota(req.commercialUser!.uid, req.path || 'ai');
        return next();
      } catch (error) {
        const status = error instanceof HttpError ? error.status : 500;
        const message = error instanceof Error ? error.message : 'Não foi possível validar o uso da IA.';
        return res.status(status).json({ error: message });
      }
    });
  };

  const getProfileCountry = async (userId: string) => {
    if (!services) return null;
    const profile = await services.db.collection('profiles').doc(userId).get();
    const value = profile.data()?.countryCode;
    return typeof value === 'string' ? value.toUpperCase() : null;
  };

  const getContentBySlug = async (slug: string) => {
    if (!services) return null;
    const snapshot = await services.db.collection('contentItems').where('slug', '==', slug).limit(1).get();
    const document = snapshot.docs[0];
    return document ? ({ id: document.id, ...document.data() } as ContentRecord) : null;
  };

  const ensureContentAccess = async (userId: string, content: ContentRecord | null) => {
    if (!content) return false;
    return contentIsAvailable(content, await getProfileCountry(userId));
  };

  router.get('/health', (_req, res) => {
    res.json({ configured, cloudMode, provider: 'firebase', projectId: process.env.FIREBASE_PROJECT_ID || null });
  });

  router.get('/me', requireAuth, asyncRoute(async (req, res) => {
    if (!services || !req.commercialUser) return;
    const profile = await services.db.collection('profiles').doc(req.commercialUser.uid).get();
    return res.json({
      id: req.commercialUser.uid,
      email: req.commercialUser.email || '',
      displayName: profile.data()?.displayName || req.commercialUser.name || 'Aluno',
      preferredLocale: profile.data()?.preferredLocale || 'pt-BR',
      countryCode: profile.data()?.countryCode || null,
    });
  }));

  router.put('/me', requireAuth, asyncRoute(async (req, res) => {
    if (!services || !req.commercialUser) return;
    const displayName = String(req.body?.displayName || '').trim();
    const countryCode = String(req.body?.countryCode || '').trim().toUpperCase();
    if (!displayName || displayName.length > 80 || !/^[A-Z]{2}$/.test(countryCode)) {
      return res.status(400).json({ error: 'Nome ou país inválido.' });
    }
    await services.db.collection('profiles').doc(req.commercialUser.uid).set({
      displayName,
      countryCode,
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    return res.json({ displayName, preferredLocale: 'pt-BR', countryCode });
  }));

  router.delete('/me', requireAuth, asyncRoute(async (req, res) => {
    if (!services || !req.commercialUser) return;
    if (req.body?.confirm !== 'DELETE') return res.status(400).json({ error: 'Confirmação de exclusão inválida.' });
    const userId = req.commercialUser.uid;
    await Promise.all([
      deleteQuery(services.db, services.db.collection('progress').where('userId', '==', userId)),
      deleteQuery(services.db, services.db.collection('aiUsage').where('userId', '==', userId)),
    ]);
    await Promise.all([
      services.db.collection('profiles').doc(userId).delete(),
      services.db.collection('entitlements').doc(userId).delete(),
    ]);
    await services.auth.deleteUser(userId);
    return res.sendStatus(204);
  }));

  router.get('/catalog', requireAuth, asyncRoute(async (req, res) => {
    if (!services || !req.commercialUser) return;
    const snapshot = await services.db.collection('contentItems').where('status', '==', 'published').get();
    const theme = typeof req.query.theme === 'string' ? req.query.theme : null;
    const difficulty = typeof req.query.difficulty === 'string' ? req.query.difficulty : null;
    const countryCode = await getProfileCountry(req.commercialUser.uid);
    const available = snapshot.docs
      .map((document) => ({ id: document.id, ...document.data() } as ContentRecord))
      .filter((content) => contentIsAvailable(content, countryCode))
      .filter((content) => !theme || content.theme === theme)
      .filter((content) => !difficulty || content.difficulty === difficulty)
      .sort((left, right) => String(asIsoString(right.publishedAt)).localeCompare(String(asIsoString(left.publishedAt))));
    return res.json(await Promise.all(available.map((content) => serializeContent(services, content, false))));
  }));

  router.get('/catalog/:slug', requireAuth, asyncRoute(async (req, res) => {
    if (!services || !req.commercialUser) return;
    try {
      const content = await getContentBySlug(req.params.slug);
      if (!await ensureContentAccess(req.commercialUser.uid, content)) {
        return res.status(404).json({ error: 'Conteúdo não encontrado ou indisponível em sua região.' });
      }
      return res.json(await serializeContent(services, content!, true));
    } catch (error) {
      console.error('[commercial] catalog detail failed', error);
      return res.status(500).json({ error: 'Não foi possível carregar esta aula.' });
    }
  }));

  router.get('/catalog/:slug/media', requireAuth, asyncRoute(async (req, res) => {
    if (!services || !req.commercialUser) return;
    try {
      const content = await getContentBySlug(req.params.slug);
      if (!await ensureContentAccess(req.commercialUser.uid, content)) {
        return res.status(404).json({ error: 'Conteúdo não encontrado ou indisponível em sua região.' });
      }
      const wantsOfflineDownload = req.query.download === '1';
      if (wantsOfflineDownload && !content!.rights.offlineDownloadAllowed) {
        return res.status(403).json({ error: 'A licença deste conteúdo não permite download offline.' });
      }
      const kind = req.query.kind === 'audio' ? 'audio' : 'video';
      const asset = content!.assets?.find((candidate) => candidate.kind === kind) || null;
      if (!asset) return res.status(404).json({ error: 'Mídia indisponível para esta aula.' });
      const signedUrl = await signAsset(services.bucket, asset, 60 * 60);
      return res.json({ url: signedUrl, expiresIn: 3600, mimeType: asset.mimeType });
    } catch (error) {
      console.error('[commercial] signed media failed', error);
      return res.status(500).json({ error: 'Não foi possível liberar a mídia.' });
    }
  }));

  router.get('/progress', requireAuth, asyncRoute(async (req, res) => {
    if (!services || !req.commercialUser) return;
    const snapshot = await services.db.collection('progress').where('userId', '==', req.commercialUser.uid).get();
    const progress = snapshot.docs
      .map((document) => document.data())
      .sort((left, right) => String(asIsoString(right.lastStudiedAt)).localeCompare(String(asIsoString(left.lastStudiedAt))))
      .map((item) => ({
        content_id: item.contentId,
        lesson_id: item.lessonId || null,
        segment_position: item.segmentPosition || 0,
        completed_percent: item.completedPercent || 0,
        seconds_studied: item.secondsStudied || 0,
        state: item.state || {},
        last_studied_at: asIsoString(item.lastStudiedAt),
      }));
    return res.json(progress);
  }));

  router.put('/progress/:contentId', requireAuth, asyncRoute(async (req, res) => {
    if (!services || !req.commercialUser) return;
    const contentId = req.params.contentId;
    const lessonId = req.body?.lessonId;
    const segmentPosition = Number(req.body?.segmentPosition ?? 0);
    const completedPercent = Number(req.body?.completedPercent ?? 0);
    const secondsStudied = Number(req.body?.secondsStudied ?? 0);
    const state = req.body?.state && typeof req.body.state === 'object' && !Array.isArray(req.body.state)
      ? req.body.state
      : {};
    if (!isUuid(contentId) || (lessonId != null && !isUuid(lessonId))) return res.status(400).json({ error: 'Identificador de conteúdo inválido.' });
    if (!Number.isInteger(segmentPosition) || segmentPosition < 0) return res.status(400).json({ error: 'Posição de frase inválida.' });
    if (!Number.isFinite(completedPercent) || completedPercent < 0 || completedPercent > 100) return res.status(400).json({ error: 'Percentual de conclusão inválido.' });
    if (!Number.isInteger(secondsStudied) || secondsStudied < 0) return res.status(400).json({ error: 'Tempo de estudo inválido.' });
    if (Buffer.byteLength(JSON.stringify(state), 'utf8') > 100_000) return res.status(413).json({ error: 'Estado de estudo muito grande.' });

    const contentSnapshot = await services.db.collection('contentItems').doc(contentId).get();
    const content = contentSnapshot.exists ? ({ id: contentSnapshot.id, ...contentSnapshot.data() } as ContentRecord) : null;
    if (!await ensureContentAccess(req.commercialUser.uid, content)) return res.status(404).json({ error: 'Conteúdo indisponível.' });
    const activeLesson = await loadLesson(services.db, content!);
    if (!activeLesson) return res.status(409).json({ error: 'A aula publicada está indisponível.' });
    if (lessonId && lessonId !== activeLesson.id) return res.status(400).json({ error: 'Aula inválida para este conteúdo.' });
    if (segmentPosition >= activeLesson.segments.length) return res.status(400).json({ error: 'Posição de frase fora da aula.' });

    const lastStudiedAt = Timestamp.now();
    const progress = {
      userId: req.commercialUser.uid,
      contentId,
      lessonId: activeLesson.id,
      segmentPosition,
      completedPercent,
      secondsStudied,
      state,
      lastStudiedAt,
      updatedAt: FieldValue.serverTimestamp(),
    };
    await services.db.collection('progress').doc(`${req.commercialUser.uid}_${contentId}`).set({
      ...progress,
      createdAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    return res.json({
      content_id: contentId,
      lesson_id: activeLesson.id,
      segment_position: segmentPosition,
      completed_percent: completedPercent,
      seconds_studied: secondsStudied,
      state,
      last_studied_at: lastStudiedAt.toDate().toISOString(),
    });
  }));

  router.use((error: unknown, _req: Request, res: Response, next: NextFunction) => {
    if (res.headersSent) return next(error);
    console.error('[commercial] unhandled request error', error);
    const status = error instanceof HttpError ? error.status : 500;
    const message = error instanceof HttpError ? error.message : 'Não foi possível concluir esta operação.';
    return res.status(status).json({ error: message });
  });

  return { router, protectAi, configured, cloudMode };
}
