import { registerPlugin, type PluginListenerHandle } from '@capacitor/core';

export type NativeTranscriptSegment = {
  text: string;
  start: number;
  end: number;
};

export type NativeTranscriptResult = {
  segments: NativeTranscriptSegment[];
  title?: string;
  channel?: string;
  languageCode?: string;
  source?: string;
};

type YouTubeCaptionsPlugin = {
  offlineLibrary(): Promise<{ videos: NativeOfflineVideo[] }>;
  downloadVideo(options: { videoId: string; lesson: NativeSavedLesson }): Promise<NativeOfflineVideo>;
  aiSettings(options?: { apiKey?: string }): Promise<{ configured: boolean }>;
  generateLesson(options: { prompt: string; audioBase64?: string; mimeType?: string }): Promise<{ text: string }>;
  searchVideos(options: { query: string }): Promise<{ videos: { id: string; title: string; channel: string; thumbnail: string; duration: string }[] }>;
  fetchTranscript(options: { videoId: string; language?: string }): Promise<NativeTranscriptResult>;
  mountPlayer(options: { videoId: string; x: number; y: number; width: number; height: number }): Promise<void>;
  updatePlayerFrame(options: { x: number; y: number; width: number; height: number }): Promise<void>;
  destroyPlayer(): Promise<void>;
  playVideo(): Promise<void>;
  pauseVideo(): Promise<void>;
  seekTo(options: { time: number }): Promise<void>;
  getCurrentTime(): Promise<{ value: number }>;
  getPlayerState(): Promise<{ value: number }>;
  addListener(eventName: 'playerReady', listener: () => void): Promise<PluginListenerHandle>;
  addListener(eventName: 'playerState', listener: (event: { state: number }) => void): Promise<PluginListenerHandle>;
  addListener(eventName: 'playerError', listener: (event: { code: number }) => void): Promise<PluginListenerHandle>;
};

export type NativeSavedLesson = {
  phrases: (NativeTranscriptSegment & { translation: string })[];
  title?: string;
  channel?: string;
  aiEnriched?: boolean;
};

export type NativeOfflineVideo = {
  videoId: string;
  path: string;
  lesson: NativeSavedLesson;
};

export const YouTubeCaptions = registerPlugin<YouTubeCaptionsPlugin>('YouTubeCaptions');
