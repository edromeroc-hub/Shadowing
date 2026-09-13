import type { CapacitorConfig } from '@capacitor/cli';

const developmentServerUrl = process.env.CAPACITOR_SERVER_URL?.trim();

const config: CapacitorConfig = {
  appId: 'com.edromero.shadowing',
  appName: 'ShadowingAI',
  webDir: 'dist',
  server: developmentServerUrl
    ? {
        url: developmentServerUrl,
        cleartext: developmentServerUrl.startsWith('http://'),
      }
    : undefined,
  ios: {
    backgroundColor: '#050505',
    contentInset: 'automatic',
  },
};

export default config;
