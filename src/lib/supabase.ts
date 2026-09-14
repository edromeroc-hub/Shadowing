import { createClient, type User } from '@supabase/supabase-js';

const supabaseUrl = String(import.meta.env.VITE_SUPABASE_URL || '').trim();
const supabasePublishableKey = String(import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY || '').trim();

export const commercialCloudMode = __COMMERCIAL_CATALOG_MODE__;
export const supabaseConfigured = Boolean(supabaseUrl && supabasePublishableKey);

export const supabase = supabaseConfigured
  ? createClient(supabaseUrl, supabasePublishableKey, {
      auth: {
        autoRefreshToken: true,
        detectSessionInUrl: true,
        persistSession: true,
      },
    })
  : null;

export type AppUser = {
  id: string;
  name: string;
  email: string;
};

export function mapSupabaseUser(user: User): AppUser {
  const email = user.email || '';
  const displayName = typeof user.user_metadata?.display_name === 'string'
    ? user.user_metadata.display_name.trim()
    : '';
  return {
    id: user.id,
    name: displayName || email.split('@')[0] || 'Aluno',
    email,
  };
}
