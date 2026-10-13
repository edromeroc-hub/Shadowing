const threeMinuteShortsDate = Date.parse('2024-10-15T00:00:00Z');

export function secondsFromDuration(value) {
  const match = /^PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?$/.exec(value || '');
  return match ? Number(match[1] || 0) * 3600 + Number(match[2] || 0) * 60 + Number(match[3] || 0) : NaN;
}

export function assessShortsFormat(video) {
  const durationSeconds = secondsFromDuration(video?.contentDetails?.duration);
  const width = Number(video?.player?.embedWidth);
  const height = Number(video?.player?.embedHeight);
  const publishedAt = Date.parse(video?.snippet?.publishedAt || '');
  const evidence = { durationSeconds, width, height, publishedAt: video?.snippet?.publishedAt || null };

  if (!video || video.status?.embeddable === false) return { eligible: false, reason: 'Vídeo indisponível ou não incorporável', evidence };
  if (!Number.isFinite(durationSeconds) || durationSeconds < 1) return { eligible: false, reason: 'Duração desconhecida', evidence };
  if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) {
    return { eligible: false, reason: 'Formato da imagem desconhecido', evidence };
  }
  if (width > height) return { eligible: false, reason: 'Vídeo horizontal, não é Short', evidence };
  if (!Number.isFinite(publishedAt)) return { eligible: false, reason: 'Data de publicação desconhecida', evidence };
  const maximumSeconds = publishedAt >= threeMinuteShortsDate ? 180 : 60;
  if (durationSeconds > maximumSeconds) return { eligible: false, reason: 'Duração incompatível com Shorts', evidence };
  return { eligible: true, reason: null, evidence };
}
