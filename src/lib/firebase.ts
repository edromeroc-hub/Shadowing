import { getApp, getApps, initializeApp } from 'firebase/app';
import {
  browserLocalPersistence,
  createUserWithEmailAndPassword,
  getAuth,
  onAuthStateChanged,
  setPersistence,
  signInWithEmailAndPassword,
  signOut,
  updateProfile,
  type User,
} from 'firebase/auth';

const firebaseConfig = {
  apiKey: String(import.meta.env.VITE_FIREBASE_API_KEY || '').trim(),
  authDomain: String(import.meta.env.VITE_FIREBASE_AUTH_DOMAIN || '').trim(),
  projectId: String(import.meta.env.VITE_FIREBASE_PROJECT_ID || '').trim(),
  storageBucket: String(import.meta.env.VITE_FIREBASE_STORAGE_BUCKET || '').trim(),
  messagingSenderId: String(import.meta.env.VITE_FIREBASE_MESSAGING_SENDER_ID || '').trim(),
  appId: String(import.meta.env.VITE_FIREBASE_APP_ID || '').trim(),
};

export const commercialCloudMode = __COMMERCIAL_CATALOG_MODE__;
export const firebaseConfigured = Boolean(
  firebaseConfig.apiKey
  && firebaseConfig.authDomain
  && firebaseConfig.projectId
  && firebaseConfig.appId,
);

export const firebaseApp = firebaseConfigured
  ? (getApps().length ? getApp() : initializeApp(firebaseConfig))
  : null;
export const firebaseAuth = firebaseApp ? getAuth(firebaseApp) : null;

if (firebaseAuth) {
  void setPersistence(firebaseAuth, browserLocalPersistence).catch((error) => {
    console.warn('[firebase] não foi possível ativar persistência local', error);
  });
}

export type AppUser = {
  id: string;
  name: string;
  email: string;
};

export function mapFirebaseUser(user: User): AppUser {
  return {
    id: user.uid,
    name: user.displayName || user.email?.split('@')[0] || 'Aluno',
    email: user.email || '',
  };
}

export function observeFirebaseAuth(callback: (user: User | null) => void) {
  if (!firebaseAuth) return () => undefined;
  return onAuthStateChanged(firebaseAuth, callback);
}

export async function createFirebaseAccount(email: string, password: string, displayName: string) {
  if (!firebaseAuth) throw new Error('O Firebase Auth ainda não foi configurado.');
  const credential = await createUserWithEmailAndPassword(firebaseAuth, email, password);
  await updateProfile(credential.user, { displayName });
  return credential.user;
}

export async function signInFirebase(email: string, password: string) {
  if (!firebaseAuth) throw new Error('O Firebase Auth ainda não foi configurado.');
  return (await signInWithEmailAndPassword(firebaseAuth, email, password)).user;
}

export async function signOutFirebase() {
  if (firebaseAuth) await signOut(firebaseAuth);
}

type AuthResult = {
  data: { user: User | null; session: { user: User } | null };
  error: Error | null;
};

const compatibilityAuth = firebaseAuth ? {
  async getSession() {
    await firebaseAuth.authStateReady();
    const user = firebaseAuth.currentUser;
    return { data: { session: user ? { user } : null }, error: null };
  },
  onAuthStateChange(callback: (event: string, session: { user: User } | null) => void) {
    const unsubscribe = onAuthStateChanged(firebaseAuth, (user) => {
      callback(user ? 'SIGNED_IN' : 'SIGNED_OUT', user ? { user } : null);
    });
    return { data: { subscription: { unsubscribe } } };
  },
  async signUp(input: { email: string; password: string; options?: { data?: { display_name?: string; country_code?: string } } }): Promise<AuthResult> {
    try {
      const user = await createFirebaseAccount(
        input.email,
        input.password,
        input.options?.data?.display_name || input.email.split('@')[0] || 'Aluno',
      );
      return { data: { user, session: { user } }, error: null };
    } catch (error) {
      return { data: { user: null, session: null }, error: error as Error };
    }
  },
  async signInWithPassword(input: { email: string; password: string }): Promise<AuthResult> {
    try {
      const user = await signInFirebase(input.email, input.password);
      return { data: { user, session: { user } }, error: null };
    } catch (error) {
      return { data: { user: null, session: null }, error: error as Error };
    }
  },
  signOut: signOutFirebase,
} : null;

export const firebaseAuthConfigured = firebaseConfigured;
export const mapLegacyAuthUser = mapFirebaseUser;

export const commercialAuth = compatibilityAuth ? { auth: compatibilityAuth } : null;
export const commercialAuthConfigured = firebaseConfigured;
