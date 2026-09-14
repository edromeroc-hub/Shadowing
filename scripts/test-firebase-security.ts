import 'dotenv/config';
import { randomBytes } from 'node:crypto';
import { initializeApp } from 'firebase/app';
import { createUserWithEmailAndPassword, deleteUser, getAuth, signOut } from 'firebase/auth';
import { doc, getDoc, getFirestore, setDoc } from 'firebase/firestore';

function required(name: string) {
  const value = String(process.env[name] || '').trim();
  if (!value) throw new Error(`Variável ausente: ${name}`);
  return value;
}

function isPermissionDenied(error: unknown) {
  const code = String((error as { code?: string })?.code || '');
  return code.includes('permission-denied');
}

async function expectPermissionDenied(action: () => Promise<unknown>, label: string) {
  try {
    await action();
  } catch (error) {
    if (isPermissionDenied(error)) return;
    throw error;
  }
  throw new Error(`${label}: a operação deveria ter sido negada pelas Security Rules.`);
}

async function main() {
  const app = initializeApp({
    apiKey: required('VITE_FIREBASE_API_KEY'),
    authDomain: required('VITE_FIREBASE_AUTH_DOMAIN'),
    projectId: required('VITE_FIREBASE_PROJECT_ID'),
    storageBucket: required('VITE_FIREBASE_STORAGE_BUCKET'),
    messagingSenderId: required('VITE_FIREBASE_MESSAGING_SENDER_ID'),
    appId: required('VITE_FIREBASE_APP_ID'),
  }, `security-test-${Date.now()}`);
  const auth = getAuth(app);
  const db = getFirestore(app);

  await expectPermissionDenied(
    () => getDoc(doc(db, 'contentItems', 'probe')),
    'Leitura anônima',
  );

  const suffix = `${Date.now()}-${randomBytes(4).toString('hex')}`;
  const credential = await createUserWithEmailAndPassword(
    auth,
    `codex-security-${suffix}@example.com`,
    `T3st-${randomBytes(10).toString('base64url')}!`,
  );
  try {
    await expectPermissionDenied(
      () => setDoc(doc(db, 'profiles', credential.user.uid), { role: 'admin' }),
      'Escalação de privilégio',
    );
    await expectPermissionDenied(
      () => getDoc(doc(db, 'contentItems', 'probe')),
      'Leitura autenticada direta',
    );
  } finally {
    await deleteUser(credential.user).catch(async () => signOut(auth));
  }

  console.log('Firebase Auth ativo; ataques diretos ao Firestore foram negados e a conta temporária foi removida.');
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
