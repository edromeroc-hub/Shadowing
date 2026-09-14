import { supabase } from './supabase';

const apiBaseUrl = String(import.meta.env.VITE_API_URL || import.meta.env.VITE_SHADOWING_API_URL || '')
  .trim()
  .replace(/\/$/, '');

export type CommercialSegment = {
  id: string;
  position: number;
  start: number;
  end: number;
  text: string;
  translation: string;
};

export type CommercialContent = {
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
  publishedAt: string | null;
  artworkUrl: string | null;
  offlineAvailable: boolean;
  rights: null | {
    basis: 'owned' | 'licensed' | 'public_domain' | 'open_license';
    rightsHolder: string;
    sourceUrl: string;
    licenseName: string | null;
    licenseUrl: string | null;
    attributionText: string | null;
  };
  lesson: null | {
    id: string;
    title: string;
    version: number;
    segmentCount: number;
    segments?: CommercialSegment[];
  };
};

export type CommercialProgress = {
  content_id: string;
  lesson_id: string | null;
  segment_position: number;
  completed_percent: number;
  seconds_studied: number;
  state: Record<string, unknown>;
  last_studied_at: string;
};

export async function commercialAuthorizedFetch(path: string, init: RequestInit = {}) {
  if (!supabase) throw new Error('O login comercial ainda não foi configurado.');
  const { data, error } = await supabase.auth.getSession();
  if (error) throw error;
  const token = data.session?.access_token;
  if (!token) throw new Error('Faça login para continuar.');

  const headers = new Headers(init.headers);
  headers.set('Authorization', `Bearer ${token}`);
  if (init.body && !headers.has('Content-Type')) headers.set('Content-Type', 'application/json');

  return fetch(`${apiBaseUrl}${path}`, { ...init, headers });
}

export async function commercialApiFetch(path: string, init: RequestInit = {}) {
  const response = await commercialAuthorizedFetch(path, init);
  const payload = await response.json().catch(() => null);
  if (!response.ok) {
    throw new Error(payload?.error || `Falha ao acessar o servidor (${response.status}).`);
  }
  return payload;
}

export async function loadCommercialCatalog(filters: { theme?: string; difficulty?: string } = {}) {
  const params = new URLSearchParams();
  if (filters.theme) params.set('theme', filters.theme);
  if (filters.difficulty) params.set('difficulty', filters.difficulty);
  const suffix = params.size ? `?${params.toString()}` : '';
  return commercialApiFetch(`/api/commercial/catalog${suffix}`) as Promise<CommercialContent[]>;
}

export function loadCommercialContent(slug: string) {
  return commercialApiFetch(`/api/commercial/catalog/${encodeURIComponent(slug)}`) as Promise<CommercialContent>;
}

export function loadCommercialMedia(slug: string) {
  return commercialApiFetch(`/api/commercial/catalog/${encodeURIComponent(slug)}/media`) as Promise<{
    url: string;
    expiresIn: number;
    mimeType: string;
  }>;
}

export function loadCommercialProgress() {
  return commercialApiFetch('/api/commercial/progress') as Promise<CommercialProgress[]>;
}

export async function deleteCommercialAccount() {
  const response = await commercialAuthorizedFetch('/api/commercial/me', {
    method: 'DELETE',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ confirm: 'DELETE' }),
  });
  if (!response.ok) {
    const payload = await response.json().catch(() => null);
    throw new Error(payload?.error || 'Não foi possível excluir sua conta.');
  }
}

export function saveCommercialProgress(contentId: string, input: {
  lessonId?: string | null;
  segmentPosition: number;
  completedPercent: number;
  secondsStudied?: number;
  state?: Record<string, unknown>;
}) {
  return commercialApiFetch(`/api/commercial/progress/${contentId}`, {
    method: 'PUT',
    body: JSON.stringify(input),
  }) as Promise<CommercialProgress>;
}
