import { phrasesArePractical, words } from './quality.mjs';

export const scanIntervalMs = 30 * 60 * 1000;
export const cycleIntervalMs = 24 * 60 * 60 * 1000;
export const maximumPagesPerChannel = 3;

export function refreshSearchBudget(state, now) {
  const day = new Date(now).toISOString().slice(0, 10);
  if (state.searchDay !== day) {
    state.searchDay = day;
    state.searchCount = 0;
    state.prioritySearchCount = 0;
  }
  state.prioritySearchCount ||= 0;
}

export function beginCycle(state, seedCount, now) {
  if (state.pending?.length || state.seedIndex < seedCount) return true;
  if (now < (state.nextCycleAt || 0)) return false;
  state.seedIndex = 0;
  state.pageToken = null;
  state.pagesForSeed = 0;
  state.nextCycleAt = null;
  return true;
}

export function finishSearchPage(state, result, pageLimit = maximumPagesPerChannel) {
  state.pending = result.videoIDs.map((videoID) => ({
    videoID, interest: state.currentInterest,
  }));
  state.pagesForSeed = (state.pagesForSeed || 0) + 1;
  if (result.nextPageToken && state.pagesForSeed < pageLimit) {
    state.pageToken = result.nextPageToken;
  } else {
    state.seedIndex += 1;
    state.pageToken = null;
    state.pagesForSeed = 0;
  }
  delete state.currentInterest;
}

export function markCycleComplete(state, seedCount, now) {
  if (state.seedIndex >= seedCount && !state.pending.length && !state.nextCycleAt) {
    state.nextCycleAt = now + cycleIntervalMs;
  }
}

export function automaticReviewReasons(prepared, metadata, trustedChannelIDs) {
  const reasons = [];
  if (metadata?.shortsFormatPassed !== true) reasons.push('Formato Short não verificado');
  if (prepared.level === 'beginner') reasons.push('Nível iniciante requer revisão');
  if (!['intermediate', 'advanced'].includes(prepared.level)) reasons.push('Nível desconhecido');
  if (metadata?.source !== 'seed') reasons.push('Origem sem revisão de canal');
  if (!trustedChannelIDs.includes(prepared.channelID)) reasons.push('Canal não revisado');
  if (!prepared.interests.includes(metadata?.seededInterest)) reasons.push('Assunto do canal não confirmado');
  if (prepared.phrases.length < 5) reasons.push('Poucos trechos');
  if (prepared.segments.length < 8) reasons.push('Legenda curta');

  const duration = prepared.segments.at(-1)?.end - prepared.segments[0]?.start;
  if (!Number.isFinite(duration) || duration < 20 || duration > 185) reasons.push('Duração suspeita');

  if (prepared.segmentationVersion !== 2) reasons.push('Trechos aguardando nova divisão');
  if (prepared.segmentationReviewRequired || !phrasesArePractical(prepared.phrases, prepared.level) ||
    prepared.phrases.some((phrase) => !Number.isFinite(phrase.start) || !Number.isFinite(phrase.end) ||
      words(phrase.text).length < 4)) {
    reasons.push('Trechos pouco práticos');
  }
  if (prepared.phrases.some((phrase) => phrase.timingEstimated)) {
    reasons.push('Cortes estimados dentro da legenda: conferir áudio');
  }

  if (prepared.segments.some((segment, index) => {
    const duration = segment.end - segment.start;
    const speechRate = words(segment.text).length * 60 / duration;
    const previous = prepared.segments[index - 1];
    return !Number.isFinite(duration) || duration < 0.2 || duration > 12 ||
      speechRate > 400 || (previous && segment.start < previous.end - 0.05);
  })) reasons.push('Tempos da legenda suspeitos');

  return reasons;
}

export function canTrustChannel(manuallyPublished, channelID) {
  return [...new Set(manuallyPublished.filter((item) => item.channelID === channelID)
    .map((item) => item.videoID))].length >= 3;
}
