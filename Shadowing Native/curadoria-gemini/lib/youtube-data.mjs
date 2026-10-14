// YouTube Data API v3 com a chave que o Mac já usa. Custo de cota: search = 100, os demais = 1.
const videoID = /^[A-Za-z0-9_-]{11}$/;

async function request(key, pathname, parameters, fetchImpl = fetch) {
  const url = new URL(`https://www.googleapis.com/youtube/v3/${pathname}`);
  for (const [name, value] of Object.entries(parameters)) if (value != null) url.searchParams.set(name, String(value));
  url.searchParams.set('key', key);
  const response = await fetchImpl(url, { signal: AbortSignal.timeout(20000) });
  if (!response.ok) {
    const error = new Error(`YouTube ${pathname}: HTTP ${response.status}${response.status === 403 ? ' (cota ou chave)' : ''}`);
    error.status = response.status;
    throw error;
  }
  return response.json();
}

export function secondsFromDuration(value) {
  const match = /^PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?$/.exec(value || '');
  return match ? Number(match[1] || 0) * 3600 + Number(match[2] || 0) * 60 + Number(match[3] || 0) : NaN;
}

// Mesma regra de curator/shorts-format.mjs: vertical e dentro da duração de Shorts da época.
export function shortsCheck(item) {
  const seconds = secondsFromDuration(item?.contentDetails?.duration);
  const width = Number(item?.player?.embedWidth);
  const height = Number(item?.player?.embedHeight);
  const published = Date.parse(item?.snippet?.publishedAt || '');
  const limit = published >= Date.parse('2024-10-15T00:00:00Z') ? 180 : 60;
  if (item?.status?.embeddable === false) return { ok: false, reason: 'não incorporável', seconds };
  if (!Number.isFinite(width) || !Number.isFinite(height)) return { ok: false, reason: 'formato desconhecido', seconds };
  if (width > height) return { ok: false, reason: 'horizontal (não é Short)', seconds };
  if (!(seconds > 0 && seconds <= limit)) return { ok: false, reason: `duração ${seconds}s fora do limite`, seconds };
  return { ok: true, reason: null, seconds };
}

export async function videoInfo(key, ids, fetchImpl) {
  const valid = [...new Set(ids)].filter((id) => videoID.test(id));
  const result = [];
  for (let offset = 0; offset < valid.length; offset += 50) {
    const response = await request(key, 'videos', {
      part: 'snippet,contentDetails,status,player,statistics',
      id: valid.slice(offset, offset + 50).join(','), maxWidth: 720, maxHeight: 720,
    }, fetchImpl);
    for (const item of response.items || []) {
      result.push({
        videoID: item.id,
        title: item.snippet.title,
        channel: item.snippet.channelTitle,
        channelID: item.snippet.channelId,
        publishedAt: item.snippet.publishedAt,
        categoryId: item.snippet.categoryId,
        audioLanguage: item.snippet.defaultAudioLanguage || item.snippet.defaultLanguage || null,
        views: Number(item.statistics?.viewCount || 0),
        short: shortsCheck(item),
      });
    }
  }
  return result;
}

export async function searchShorts(key, query, { days = 180, order = 'viewCount' } = {}, fetchImpl) {
  const response = await request(key, 'search', {
    part: 'snippet', type: 'video', q: query, videoDuration: 'short', videoEmbeddable: 'true',
    regionCode: 'US', relevanceLanguage: 'en', safeSearch: 'strict', order, maxResults: 25,
    publishedAfter: new Date(Date.now() - days * 86400000).toISOString(),
  }, fetchImpl);
  return (response.items || []).map((item) => item.id?.videoId).filter((id) => videoID.test(id || ''));
}

// Playlist só de Shorts do canal ("UUSH" + id sem "UC"): atalho não oficial do YouTube, 1 unidade de cota.
export async function channelShorts(key, channelID, fetchImpl) {
  if (!/^UC[A-Za-z0-9_-]{22}$/.test(channelID)) throw new Error(`ID de canal inválido: ${channelID}`);
  for (const prefix of ['UUSH', 'UU']) {
    try {
      const items = [];
      let pageToken = '';
      while (items.length < 100) {
        const parameters = { part: 'contentDetails', playlistId: prefix + channelID.slice(2), maxResults: 50 };
        if (pageToken) parameters.pageToken = pageToken;
        const response = await request(key, 'playlistItems', parameters, fetchImpl);
        for (const item of response.items || []) {
          const id = item.contentDetails?.videoId;
          if (videoID.test(id || '')) items.push(id);
        }
        pageToken = response.nextPageToken;
        if (!pageToken) break;
      }
      return items;
    } catch (error) {
      if (error.status !== 404 || prefix === 'UU') throw error;
    }
  }
  return [];
}

export async function findChannel(key, handleOrQuery, fetchImpl) {
  const handle = handleOrQuery.startsWith('@') ? handleOrQuery : null;
  if (handle) {
    const response = await request(key, 'channels', { part: 'snippet', forHandle: handle }, fetchImpl);
    return (response.items || []).map((item) => ({ channelID: item.id, title: item.snippet.title, country: item.snippet.country || null }));
  }
  const response = await request(key, 'search', { part: 'snippet', type: 'channel', q: handleOrQuery, maxResults: 5 }, fetchImpl);
  return (response.items || []).map((item) => ({ channelID: item.id.channelId, title: item.snippet.title, country: null }));
}
