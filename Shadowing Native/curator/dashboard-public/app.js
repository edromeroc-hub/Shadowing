const labels = { beginner: 'Iniciante', intermediate: 'Intermediário', advanced: 'Avançado' };
const state = { status: 'pending', level: '', query: '', page: 1, selectedID: null, token: null, action: null };
const elements = Object.fromEntries([
  'candidate-list', 'detail', 'count-pending', 'count-published', 'count-inspected',
  'count-searches', 'inspected-note', 'last-update', 'result-count', 'page-label',
  'previous-page', 'next-page', 'search', 'level', 'confirm-dialog', 'confirm-title',
  'confirm-description', 'review-check', 'review-check-label', 'confirm-action', 'toast',
].map((id) => [id, document.getElementById(id)]));

function element(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = String(text);
  return node;
}

function stamp(value) {
  if (!value) return 'Data não registrada';
  const date = new Date(value);
  return Number.isNaN(date.valueOf()) ? 'Data não registrada' :
    new Intl.DateTimeFormat('pt-BR', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' }).format(date);
}

function clock(seconds) {
  const safe = Math.max(0, Number(seconds) || 0);
  const minutes = Math.floor(safe / 60);
  return `${minutes}:${(safe - minutes * 60).toFixed(1).padStart(4, '0')}`;
}

function notify(message) {
  elements.toast.textContent = message;
  elements.toast.classList.add('show');
  window.setTimeout(() => elements.toast.classList.remove('show'), 5000);
}

async function api(path, options = {}) {
  const response = await fetch(path, { cache: 'no-store', ...options });
  const data = await response.json();
  if (!response.ok) throw new Error(data.error || 'Não foi possível carregar.');
  return data;
}

function renderStats(data) {
  elements['count-pending'].textContent = data.counts.pending;
  elements['count-published'].textContent = data.counts.published;
  elements['count-inspected'].textContent = data.progress.inspected;
  elements['count-searches'].textContent = data.progress.searchesToday;
  elements['inspected-note'].textContent = `${data.progress.automaticallyRejected} descartados na triagem · ${data.progress.queued} na fila`;
  elements['last-update'].textContent = `Última atividade: ${stamp(data.progress.updatedAt)}`;
  elements['result-count'].textContent = data.total;
  elements['page-label'].textContent = `Página ${data.page} de ${Math.max(1, Math.ceil(data.total / data.pageSize))}`;
  elements['previous-page'].disabled = data.page <= 1;
  elements['next-page'].disabled = data.page * data.pageSize >= data.total;
}

function renderList(data) {
  const nodes = data.items.map((candidate) => {
    const button = element('button', `candidate ${state.selectedID === candidate.videoID ? 'selected' : ''}`);
    button.type = 'button';
    button.addEventListener('click', () => selectCandidate(candidate.videoID));
    const thumbnail = element('img', 'thumbnail');
    thumbnail.src = `https://i.ytimg.com/vi/${candidate.videoID}/mqdefault.jpg`;
    thumbnail.alt = '';
    thumbnail.loading = 'lazy';
    thumbnail.referrerPolicy = 'no-referrer';
    const info = element('span', 'candidate-info');
    info.append(element('span', 'candidate-title', candidate.title), element('span', 'candidate-channel', candidate.channel));
    const meta = element('span', 'candidate-meta');
    if (candidate.status === 'queued') {
      meta.append(element('span', 'level-pill', 'Aguardando legenda'),
        element('span', '', candidate.interests.join(' · ') || 'Tema não informado'));
    } else {
      meta.append(element('span', `level-pill ${candidate.level}`, labels[candidate.level] || candidate.level),
        element('span', '', `${candidate.phraseCount} trechos`));
    }
    info.append(meta);
    button.append(thumbnail, info);
    return button;
  });
  if (!nodes.length) nodes.push(element('p', 'empty-state', state.query || state.level ?
    'Nenhum Short corresponde aos filtros.' : state.status === 'pending' ?
      'Ainda não há candidatos. O curador continua procurando.' : 'Nenhum Short nesta etapa.'));
  elements['candidate-list'].replaceChildren(...nodes);
}

async function loadList() {
  try {
    const params = new URLSearchParams({ status: state.status, level: state.level, query: state.query, page: String(state.page) });
    const data = await api(`/api/candidates?${params}`);
    renderStats(data);
    renderList(data);
    if (!state.selectedID && data.items.length) await selectCandidate(data.items[0].videoID);
  } catch (error) {
    elements['candidate-list'].replaceChildren(element('p', 'empty-state error', error.message));
  }
}

function showVideo(videoID, phrase) {
  const iframe = document.getElementById('video-frame');
  if (!iframe) return;
  const start = phrase ? Math.max(0, Math.floor(phrase.start - 0.25)) : 0;
  const end = phrase ? Math.max(start + 1, Math.ceil(phrase.end + 0.25)) : 0;
  const params = new URLSearchParams({ controls: '1', rel: '0', start: String(start) });
  if (phrase) {
    params.set('end', String(end));
    params.set('autoplay', '1');
  }
  iframe.src = `https://www.youtube-nocookie.com/embed/${videoID}?${params}`;
}

function renderDetail(candidate) {
  const header = element('div', 'detail-heading');
  const headingText = element('div');
  headingText.append(element('p', 'eyebrow', 'CONFERÊNCIA DE ÁUDIO E LEGENDA'), element('h2', '', candidate.title),
    element('p', 'detail-channel', candidate.status === 'queued' ?
      `${candidate.channel} · ${candidate.interests.join(' · ') || 'Tema não informado'}` :
      `${candidate.channel} · ${labels[candidate.level] || candidate.level} · ${stamp(candidate.scannedAt)}`));
  header.append(headingText, element('span', `status-pill ${candidate.status}`, {
    pending: 'Aguardando revisão', published: 'Publicado', rejected: 'Rejeitado', queued: 'Na fila de triagem',
  }[candidate.status]));

  const video = element('div', 'video-wrap');
  const iframe = element('iframe');
  iframe.id = 'video-frame';
  iframe.title = `Prévia de ${candidate.title}`;
  iframe.allow = 'accelerometer; autoplay; encrypted-media; gyroscope; picture-in-picture';
  iframe.allowFullscreen = true;
  iframe.referrerPolicy = 'origin';
  video.append(iframe);
  const link = element('a', 'youtube-link', 'Abrir no YouTube ↗');
  link.href = `https://www.youtube.com/shorts/${candidate.videoID}`;
  link.target = '_blank';
  link.rel = 'noopener noreferrer';
  const videoNote = element('p', 'video-note', 'A prévia do YouTube pode arredondar o início e o fim. Confira o áudio real antes de aprovar.');

  if (candidate.status === 'queued') {
    const notice = element('div', 'issues');
    notice.append(element('strong', '', 'O Mac ainda está processando este Short.'),
      element('p', '', 'A legenda, os trechos e o nível só aparecerão se a triagem for concluída. Ainda não é possível aprová-lo.'));
    elements.detail.replaceChildren(header, video, link, notice);
    showVideo(candidate.videoID);
    return;
  }

  const metrics = element('div', 'detail-metrics');
  metrics.append(element('span', '', `${candidate.phrases.length} trechos`),
    element('span', '', `${candidate.segments.length} linhas da legenda`),
    element('span', '', candidate.interests.join(' · ') || 'Tema não identificado'));
  const issues = element('div', 'issues');
  issues.append(element('strong', '', candidate.status === 'rejected' ? 'Motivo da rejeição' : 'Por que ainda requer revisão?'));
  issues.append(element('p', '', candidate.status === 'rejected' ?
    candidate.rejectionReason || 'Rejeitado manualmente.' : candidate.automationReasons.length ?
      candidate.automationReasons.join(' · ') : 'Candidato elegível para automação após confiança no canal.'));

  const phrasesHeading = element('div', 'phrases-heading');
  phrasesHeading.append(element('h3', '', 'Trechos preparados'), element('span', '', 'Clique para ouvir no vídeo'));
  const phraseList = element('div', 'phrase-list');
  candidate.phrases.forEach((phrase, index) => {
    const button = element('button', 'phrase');
    button.type = 'button';
    button.addEventListener('click', () => {
      document.querySelectorAll('.phrase.active').forEach((item) => item.classList.remove('active'));
      button.classList.add('active');
      showVideo(candidate.videoID, phrase);
      video.scrollIntoView({ behavior: 'smooth', block: 'center' });
    });
    button.append(element('span', 'phrase-number', String(index + 1).padStart(2, '0')),
      element('span', 'phrase-text', phrase.text),
      element('span', 'phrase-time', `${phrase.timingEstimated ? '≈ ' : ''}${clock(phrase.start)}–${clock(phrase.end)}`));
    if (phrase.timingEstimated) button.title = 'Tempo aproximado: corte estimado dentro de um bloco da legenda. Ouça antes de aprovar.';
    phraseList.append(button);
  });

  const actions = element('div', 'review-actions');
  if (candidate.status === 'pending') {
    const reject = element('button', 'secondary-button danger', 'Rejeitar');
    reject.type = 'button';
    reject.addEventListener('click', () => askAction('reject'));
    const approve = element('button', 'primary-button', 'Aprovar e publicar →');
    approve.type = 'button';
    approve.disabled = candidate.segmentationReviewRequired || candidate.segmentationVersion !== 2;
    approve.addEventListener('click', () => askAction('approve'));
    actions.append(reject, approve);
  } else {
    actions.append(element('p', 'reviewed-note', candidate.status === 'published' ?
      'Este Short já está no catálogo compartilhado.' : 'Este Short foi rejeitado manualmente.'));
  }
  elements.detail.replaceChildren(header, video, link, videoNote, metrics, issues, phrasesHeading, phraseList, actions);
  showVideo(candidate.videoID);
}

async function selectCandidate(videoID) {
  state.selectedID = videoID;
  document.querySelectorAll('.candidate').forEach((button) => button.classList.toggle('selected',
    button.querySelector('img')?.src.includes(videoID)));
  elements.detail.replaceChildren(element('p', 'empty-state', 'Abrindo Short…'));
  try {
    renderDetail(await api(`/api/candidates/${videoID}`));
  } catch (error) {
    elements.detail.replaceChildren(element('p', 'empty-state error', error.message));
  }
}

function askAction(action) {
  state.action = action;
  const approving = action === 'approve';
  elements['confirm-title'].textContent = approving ? 'Publicar este Short?' : 'Rejeitar este Short?';
  elements['confirm-description'].textContent = approving ?
    'Ele será enviado ao catálogo compartilhado no Firestore e poderá aparecer no app. A revisão técnica não resolve direitos de uso comercial.' :
    'Ele sairá da fila de revisão e não será publicado. A ação não apaga o vídeo original do YouTube.';
  elements['review-check'].checked = false;
  elements['review-check-label'].hidden = !approving;
  elements['confirm-action'].textContent = approving ? 'Publicar' : 'Rejeitar';
  elements['confirm-dialog'].showModal();
}

async function confirmAction() {
  if (state.action === 'approve' && !elements['review-check'].checked) {
    notify('Confirme que você revisou áudio, legenda, cortes e nível.');
    return;
  }
  elements['confirm-action'].disabled = true;
  try {
    await api(`/api/candidates/${state.selectedID}/${state.action}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Curator-Token': state.token }, body: '{}',
    });
    elements['confirm-dialog'].close();
    notify(state.action === 'approve' ? 'Short publicado no catálogo.' : 'Short retirado da fila.');
    state.selectedID = null;
    await loadList();
  } catch (error) {
    notify(error.message);
  } finally {
    elements['confirm-action'].disabled = false;
  }
}

document.querySelectorAll('[data-status]').forEach((tab) => tab.addEventListener('click', () => {
  state.status = tab.dataset.status;
  state.page = 1;
  state.selectedID = null;
  document.querySelectorAll('[data-status]').forEach((item) => {
    item.classList.toggle('active', item === tab);
    item.setAttribute('aria-selected', String(item === tab));
  });
  elements.detail.replaceChildren(element('p', 'empty-state', 'Selecione um Short.'));
  loadList();
}));
let searchTimer;
elements.search.addEventListener('input', () => {
  window.clearTimeout(searchTimer);
  searchTimer = window.setTimeout(() => { state.query = elements.search.value; state.page = 1; state.selectedID = null; loadList(); }, 300);
});
elements.level.addEventListener('change', () => { state.level = elements.level.value; state.page = 1; state.selectedID = null; loadList(); });
elements['previous-page'].addEventListener('click', () => { state.page -= 1; state.selectedID = null; loadList(); });
elements['next-page'].addEventListener('click', () => { state.page += 1; state.selectedID = null; loadList(); });
document.getElementById('refresh').addEventListener('click', loadList);
document.getElementById('cancel-action').addEventListener('click', () => elements['confirm-dialog'].close());
elements['confirm-action'].addEventListener('click', confirmAction);

api('/api/session').then((session) => { state.token = session.token; return loadList(); }).catch((error) => notify(error.message));
window.setInterval(loadList, 10000);
