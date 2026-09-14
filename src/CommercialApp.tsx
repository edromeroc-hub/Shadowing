import { useEffect, useMemo, useRef, useState, type FormEvent } from 'react';
import {
  ArrowLeft,
  Check,
  Eye,
  EyeOff,
  FileText,
  History,
  Info,
  Loader2,
  LogIn,
  LogOut,
  Mic,
  Pause,
  Play,
  Repeat,
  Search,
  SkipBack,
  SkipForward,
  SlidersHorizontal,
  Trash2,
  UserPlus,
  X,
} from 'lucide-react';
import {
  commercialAuthorizedFetch,
  deleteCommercialAccount,
  loadCommercialCatalog,
  loadCommercialContent,
  loadCommercialMedia,
  loadCommercialProgress,
  saveCommercialProgress,
  type CommercialContent,
  type CommercialProgress,
  type CommercialSegment,
} from './lib/commercialApi';
import {
  createFirebaseAccount,
  firebaseAuth,
  firebaseAuthConfigured,
  mapFirebaseUser,
  observeFirebaseAuth,
  signInFirebase,
  signOutFirebase,
  type AppUser,
} from './lib/firebase';

const THEMES = ['Viagem e Cultura', 'Tecnologia', 'Negócios/Trabalho', 'Cinema e Séries', 'Notícias e Debates'];
const DIFFICULTIES = [
  { id: 'beginner', label: 'Iniciante', detail: 'Fala mais lenta' },
  { id: 'intermediate', label: 'Intermediário', detail: 'Ritmo natural' },
  { id: 'advanced', label: 'Avançado', detail: 'Fala nativa' },
] as const;
const TIMING_KEY = 'shadowing.commercialTiming.v1';
const TIMING_STEP_MS = 100;
const MAX_TIMING_MS = 800;

type PronunciationFeedback = {
  score: number;
  words: Array<{ word: string; correct: boolean; tip: string }>;
};

type DictationFeedback = {
  score: number;
  missingWords: string[];
  message: string;
};

type LegalView = 'privacy' | 'terms' | 'credits';

function readTimingOffsets() {
  try {
    const parsed = JSON.parse(localStorage.getItem(TIMING_KEY) || '{}');
    return parsed && typeof parsed === 'object' ? parsed as Record<string, number> : {};
  } catch {
    return {};
  }
}

function formatRelativeDate(value: string) {
  const elapsedMinutes = Math.max(1, Math.floor((Date.now() - new Date(value).getTime()) / 60_000));
  if (elapsedMinutes < 60) return `${elapsedMinutes} min atrás`;
  const hours = Math.floor(elapsedMinutes / 60);
  if (hours < 24) return `${hours} h atrás`;
  return `${Math.floor(hours / 24)} d atrás`;
}

function tokenize(value: string) {
  return (value.toLowerCase().match(/[a-z0-9]+(?:['’][a-z0-9]+)*/g) || [])
    .map((word) => word.replaceAll('’', "'"));
}

function wordDistance(expected: string[], received: string[]) {
  const matrix = Array.from({ length: expected.length + 1 }, () => Array(received.length + 1).fill(0));
  for (let row = 0; row <= expected.length; row += 1) matrix[row][0] = row;
  for (let column = 0; column <= received.length; column += 1) matrix[0][column] = column;
  for (let row = 1; row <= expected.length; row += 1) {
    for (let column = 1; column <= received.length; column += 1) {
      matrix[row][column] = Math.min(
        matrix[row - 1][column] + 1,
        matrix[row][column - 1] + 1,
        matrix[row - 1][column - 1] + (expected[row - 1] === received[column - 1] ? 0 : 1),
      );
    }
  }
  return matrix[expected.length][received.length];
}

function evaluateDictation(expectedText: string, answer: string): DictationFeedback {
  const expected = tokenize(expectedText);
  const received = tokenize(answer);
  const score = Math.max(0, Math.round((1 - wordDistance(expected, received) / Math.max(expected.length, received.length, 1)) * 100));
  const available = [...received];
  const missingWords = expected.filter((word) => {
    const index = available.indexOf(word);
    if (index < 0) return true;
    available.splice(index, 1);
    return false;
  });
  const message = score >= 90
    ? 'Excelente! Você identificou praticamente toda a frase.'
    : score >= 70
      ? 'Muito bom! Você entendeu a maior parte da frase.'
      : score >= 50
        ? 'Bom começo. Ouça novamente e procure as palavras que faltaram.'
        : 'Ouça mais uma vez com atenção ao ritmo e às palavras conectadas.';
  return { score, missingWords, message };
}

function blobToBase64(blob: Blob) {
  return new Promise<string>((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result).split(',')[1] || '');
    reader.onerror = () => reject(new Error('Não foi possível ler a gravação.'));
    reader.readAsDataURL(blob);
  });
}

export default function CommercialApp() {
  const [user, setUser] = useState<AppUser | null>(null);
  const [authReady, setAuthReady] = useState(false);
  const [authOpen, setAuthOpen] = useState(false);
  const [authMode, setAuthMode] = useState<'login' | 'signup'>('login');
  const [authName, setAuthName] = useState('');
  const [authEmail, setAuthEmail] = useState('');
  const [authPassword, setAuthPassword] = useState('');
  const [authError, setAuthError] = useState('');
  const [authMessage, setAuthMessage] = useState('');
  const [authSubmitting, setAuthSubmitting] = useState(false);
  const [screen, setScreen] = useState<'catalog' | 'practice'>('catalog');
  const [catalog, setCatalog] = useState<CommercialContent[]>([]);
  const [progress, setProgress] = useState<CommercialProgress[]>([]);
  const [catalogLoading, setCatalogLoading] = useState(false);
  const [catalogError, setCatalogError] = useState('');
  const [selectedTheme, setSelectedTheme] = useState('');
  const [selectedDifficulty, setSelectedDifficulty] = useState('');
  const [showRecommendations, setShowRecommendations] = useState(false);
  const [currentContent, setCurrentContent] = useState<CommercialContent | null>(null);
  const [mediaUrl, setMediaUrl] = useState('');
  const [activeIndex, setActiveIndex] = useState(0);
  const [openingContent, setOpeningContent] = useState(false);
  const [playerError, setPlayerError] = useState('');
  const [isPlaying, setIsPlaying] = useState(false);
  const [loopActive, setLoopActive] = useState(true);
  const [loopWaiting, setLoopWaiting] = useState(false);
  const [timingOpen, setTimingOpen] = useState(false);
  const [timingOffsets, setTimingOffsets] = useState<Record<string, number>>(readTimingOffsets);
  const [dictationMode, setDictationMode] = useState(false);
  const [dictationAnswer, setDictationAnswer] = useState('');
  const [dictationFeedback, setDictationFeedback] = useState<DictationFeedback | null>(null);
  const [recording, setRecording] = useState(false);
  const [recordingUrl, setRecordingUrl] = useState('');
  const [pronunciationFeedback, setPronunciationFeedback] = useState<PronunciationFeedback | null>(null);
  const [analyzing, setAnalyzing] = useState(false);
  const [legalView, setLegalView] = useState<LegalView | null>(null);

  const videoRef = useRef<HTMLVideoElement | null>(null);
  const loopTimerRef = useRef<number | null>(null);
  const automaticPauseRef = useRef(false);
  const mediaRecorderRef = useRef<MediaRecorder | null>(null);
  const audioChunksRef = useRef<Blob[]>([]);
  const studyStartedAtRef = useRef(Date.now());
  const initialStudySecondsRef = useRef(0);

  const segments = currentContent?.lesson?.segments || [];
  const activeSegment = segments[activeIndex] || null;
  const activeTimingKey = activeSegment ? `${currentContent?.id}:${activeSegment.id}` : '';
  const timingOffsetMs = activeTimingKey ? timingOffsets[activeTimingKey] || 0 : 0;
  const adjustedWindow = activeSegment
    ? {
        start: Math.max(0, activeSegment.start + timingOffsetMs / 1000),
        end: Math.max(activeSegment.start + 0.35, activeSegment.end + timingOffsetMs / 1000),
      }
    : null;

  const progressByContent = useMemo(
    () => new Map(progress.map((item) => [item.content_id, item])),
    [progress],
  );
  const history = useMemo(
    () => progress
      .map((item) => ({ progress: item, content: catalog.find((candidate) => candidate.id === item.content_id) }))
      .filter((item): item is { progress: CommercialProgress; content: CommercialContent } => Boolean(item.content))
      .slice(0, 8),
    [catalog, progress],
  );
  const recommendations = useMemo(() => catalog.filter((content) => (
    (!selectedTheme || content.theme === selectedTheme)
    && (!selectedDifficulty || content.difficulty === selectedDifficulty)
  )), [catalog, selectedDifficulty, selectedTheme]);

  const cancelLoopPause = () => {
    if (loopTimerRef.current !== null) window.clearTimeout(loopTimerRef.current);
    loopTimerRef.current = null;
    automaticPauseRef.current = false;
    setLoopWaiting(false);
  };

  useEffect(() => {
    if (!firebaseAuth) {
      setAuthReady(true);
      return;
    }
    let disposed = false;
    const readinessTimeout = window.setTimeout(() => {
      if (!disposed) {
        setUser(firebaseAuth.currentUser ? mapFirebaseUser(firebaseAuth.currentUser) : null);
        setAuthReady(true);
      }
    }, 2500);
    void firebaseAuth.authStateReady().then(() => {
      if (!disposed) {
        window.clearTimeout(readinessTimeout);
        setUser(firebaseAuth.currentUser ? mapFirebaseUser(firebaseAuth.currentUser) : null);
        setAuthReady(true);
      }
    });
    const unsubscribe = observeFirebaseAuth((nextUser) => {
      if (!disposed) {
        window.clearTimeout(readinessTimeout);
        setUser(nextUser ? mapFirebaseUser(nextUser) : null);
        setAuthReady(true);
      }
    });
    return () => {
      disposed = true;
      window.clearTimeout(readinessTimeout);
      unsubscribe();
    };
  }, []);

  useEffect(() => {
    if (!user) {
      setCatalog([]);
      setProgress([]);
      return;
    }
    setCatalogLoading(true);
    setCatalogError('');
    void Promise.all([loadCommercialCatalog(), loadCommercialProgress()])
      .then(([nextCatalog, nextProgress]) => {
        setCatalog(nextCatalog);
        setProgress(nextProgress);
      })
      .catch((error) => setCatalogError(error.message || 'Não foi possível carregar a biblioteca.'))
      .finally(() => setCatalogLoading(false));
  }, [user?.id]);

  useEffect(() => {
    localStorage.setItem(TIMING_KEY, JSON.stringify(timingOffsets));
  }, [timingOffsets]);

  useEffect(() => {
    setDictationAnswer('');
    setDictationFeedback(null);
    setPronunciationFeedback(null);
    setRecordingUrl('');
    cancelLoopPause();
    const video = videoRef.current;
    if (!video || !adjustedWindow) return;
    video.currentTime = adjustedWindow.start;
    if (isPlaying) void video.play();
  }, [activeIndex, currentContent?.id, timingOffsetMs]);

  useEffect(() => {
    if (!isPlaying || !adjustedWindow || !videoRef.current) return;
    const interval = window.setInterval(() => {
      const video = videoRef.current;
      if (!video || automaticPauseRef.current || video.currentTime < adjustedWindow.end) return;
      if (!loopActive) {
        video.pause();
        setIsPlaying(false);
        return;
      }
      automaticPauseRef.current = true;
      setLoopWaiting(true);
      video.pause();
      const pauseMs = Math.max(400, Math.round((adjustedWindow.end - adjustedWindow.start) * 1000));
      loopTimerRef.current = window.setTimeout(() => {
        loopTimerRef.current = null;
        automaticPauseRef.current = false;
        setLoopWaiting(false);
        if (!videoRef.current) return;
        videoRef.current.currentTime = adjustedWindow.start;
        void videoRef.current.play();
      }, pauseMs);
    }, 70);
    return () => window.clearInterval(interval);
  }, [adjustedWindow?.start, adjustedWindow?.end, isPlaying, loopActive]);

  useEffect(() => () => {
    cancelLoopPause();
    if (recordingUrl) URL.revokeObjectURL(recordingUrl);
  }, [recordingUrl]);

  useEffect(() => {
    if (!user || !currentContent?.lesson || !activeSegment) return;
    const timeout = window.setTimeout(() => {
      const completedPercent = Math.round(((activeIndex + 1) / segments.length) * 100);
      const secondsStudied = initialStudySecondsRef.current
        + Math.max(0, Math.round((Date.now() - studyStartedAtRef.current) / 1000));
      void saveCommercialProgress(currentContent.id, {
        lessonId: currentContent.lesson?.id,
        segmentPosition: activeIndex,
        completedPercent,
        secondsStudied,
        state: { contentSlug: currentContent.slug },
      }).then((saved) => {
        setProgress((items) => [saved, ...items.filter((item) => item.content_id !== saved.content_id)]);
      }).catch(console.error);
    }, 600);
    return () => window.clearTimeout(timeout);
  }, [activeIndex, currentContent?.id, user?.id]);

  const openAuth = (mode: 'login' | 'signup') => {
    setAuthMode(mode);
    setAuthError('');
    setAuthMessage('');
    setAuthOpen(true);
  };

  const submitAuth = async (event: FormEvent) => {
    event.preventDefault();
    if (!firebaseAuth) return;
    const email = authEmail.trim().toLowerCase();
    const password = authPassword.trim();
    const displayName = authName.trim() || email.split('@')[0] || 'Aluno';
    if (!email || password.length < 6) {
      setAuthError('Informe um e-mail e uma senha com pelo menos 6 caracteres.');
      return;
    }
    setAuthSubmitting(true);
    setAuthError('');
    setAuthMessage('');
    try {
      if (authMode === 'signup') {
        await createFirebaseAccount(email, password, displayName);
      } else {
        await signInFirebase(email, password);
      }
      setAuthOpen(false);
      setAuthPassword('');
    } catch (error: any) {
      setAuthError(error.message || 'Não foi possível entrar.');
    } finally {
      setAuthSubmitting(false);
    }
  };

  const logout = async () => {
    await signOutFirebase();
    setScreen('catalog');
    setCurrentContent(null);
    setMediaUrl('');
  };

  const deleteAccount = async () => {
    if (!window.confirm('Excluir permanentemente sua conta e todo o progresso? Esta ação não pode ser desfeita.')) return;
    try {
      await deleteCommercialAccount();
      await signOutFirebase();
      setScreen('catalog');
    } catch (error: any) {
      alert(error.message || 'Não foi possível excluir sua conta.');
    }
  };

  const openContent = async (summary: CommercialContent) => {
    setOpeningContent(true);
    setCatalogError('');
    try {
      const [detail, media] = await Promise.all([
        loadCommercialContent(summary.slug),
        loadCommercialMedia(summary.slug),
      ]);
      if (!detail.lesson?.segments?.length) throw new Error('Esta aula ainda não possui frases publicadas.');
      const savedProgress = progressByContent.get(detail.id);
      setCurrentContent(detail);
      setMediaUrl(media.url);
      setActiveIndex(Math.min(savedProgress?.segment_position || 0, detail.lesson.segments.length - 1));
      setPlayerError('');
      setIsPlaying(false);
      studyStartedAtRef.current = Date.now();
      initialStudySecondsRef.current = savedProgress?.seconds_studied || 0;
      setScreen('practice');
    } catch (error: any) {
      setCatalogError(error.message || 'Não foi possível abrir esta aula.');
    } finally {
      setOpeningContent(false);
    }
  };

  const togglePlayback = async () => {
    const video = videoRef.current;
    if (!video || !adjustedWindow) return;
    if (loopWaiting) {
      cancelLoopPause();
      setIsPlaying(false);
      return;
    }
    if (!video.paused) {
      video.pause();
      setIsPlaying(false);
      return;
    }
    if (video.currentTime < adjustedWindow.start || video.currentTime >= adjustedWindow.end) {
      video.currentTime = adjustedWindow.start;
    }
    await video.play();
    setIsPlaying(true);
  };

  const changeSegment = (nextIndex: number) => {
    if (!segments.length) return;
    setActiveIndex(Math.max(0, Math.min(nextIndex, segments.length - 1)));
  };

  const updateTiming = (delta: number) => {
    if (!activeTimingKey) return;
    setTimingOffsets((offsets) => ({
      ...offsets,
      [activeTimingKey]: Math.max(-MAX_TIMING_MS, Math.min(MAX_TIMING_MS, (offsets[activeTimingKey] || 0) + delta)),
    }));
  };

  const analyzeRecording = async (blob: Blob) => {
    if (!activeSegment) return;
    setAnalyzing(true);
    try {
      const response = await commercialAuthorizedFetch('/api/analyzePronunciation', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          audioBase64: await blobToBase64(blob),
          mimeType: blob.type.split(';')[0] || 'audio/webm',
          phrase: activeSegment.text,
        }),
      });
      const payload = await response.json();
      if (!response.ok) throw new Error(payload.error || 'Não foi possível avaliar sua pronúncia.');
      setPronunciationFeedback(payload);
    } catch (error: any) {
      alert(error.message || 'Não foi possível avaliar sua pronúncia.');
    } finally {
      setAnalyzing(false);
    }
  };

  const toggleRecording = async () => {
    if (recording && mediaRecorderRef.current) {
      mediaRecorderRef.current.stop();
      setRecording(false);
      return;
    }
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      const preferredMime = ['audio/webm;codecs=opus', 'audio/mp4', 'audio/webm']
        .find((mime) => MediaRecorder.isTypeSupported(mime));
      const recorder = new MediaRecorder(stream, preferredMime ? { mimeType: preferredMime } : undefined);
      audioChunksRef.current = [];
      recorder.ondataavailable = (event) => {
        if (event.data.size > 0) audioChunksRef.current.push(event.data);
      };
      recorder.onstop = () => {
        stream.getTracks().forEach((track) => track.stop());
        const blob = new Blob(audioChunksRef.current, { type: recorder.mimeType || 'audio/webm' });
        if (recordingUrl) URL.revokeObjectURL(recordingUrl);
        setRecordingUrl(URL.createObjectURL(blob));
        void analyzeRecording(blob);
      };
      mediaRecorderRef.current = recorder;
      recorder.start();
      setPronunciationFeedback(null);
      setRecording(true);
    } catch {
      alert('Autorize o acesso ao microfone para gravar sua prática.');
    }
  };

  const authModal = authOpen ? (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/75 px-4 backdrop-blur-sm">
      <form onSubmit={submitAuth} className="glass-input w-full max-w-md rounded-3xl p-7 shadow-2xl">
        <div className="mb-6 flex items-start justify-between gap-4">
          <div>
            <h2 className="text-2xl font-semibold">{authMode === 'login' ? 'Entrar' : 'Criar conta'}</h2>
            <p className="mt-1 text-sm text-gray-400">Seu progresso e o uso da IA ficam protegidos pela sua conta.</p>
          </div>
          <button type="button" onClick={() => setAuthOpen(false)} className="h-9 w-9 rounded-full bg-white/10 text-xl text-gray-300">×</button>
        </div>
        {authMode === 'signup' && (
          <label className="mb-4 block text-xs uppercase tracking-wider text-gray-400">
            Nome
            <input value={authName} onChange={(event) => setAuthName(event.target.value)} className="mt-2 w-full rounded-xl border border-white/10 bg-black/40 px-4 py-3 text-base normal-case tracking-normal text-white outline-none focus:border-blue-400" />
          </label>
        )}
        <label className="mb-4 block text-xs uppercase tracking-wider text-gray-400">
          E-mail
          <input type="email" value={authEmail} onChange={(event) => setAuthEmail(event.target.value)} className="mt-2 w-full rounded-xl border border-white/10 bg-black/40 px-4 py-3 text-base normal-case tracking-normal text-white outline-none focus:border-blue-400" />
        </label>
        <label className="mb-4 block text-xs uppercase tracking-wider text-gray-400">
          Senha
          <input type="password" value={authPassword} onChange={(event) => setAuthPassword(event.target.value)} className="mt-2 w-full rounded-xl border border-white/10 bg-black/40 px-4 py-3 text-base normal-case tracking-normal text-white outline-none focus:border-blue-400" />
        </label>
        {authError && <p className="mb-4 rounded-xl border border-red-500/30 bg-red-950/30 p-3 text-sm text-red-200">{authError}</p>}
        {authMessage && <p className="mb-4 rounded-xl border border-emerald-500/30 bg-emerald-950/30 p-3 text-sm text-emerald-200">{authMessage}</p>}
        <button disabled={authSubmitting} className="flex w-full items-center justify-center gap-2 rounded-xl bg-white py-3.5 font-bold text-black disabled:opacity-50">
          {authSubmitting ? <Loader2 className="animate-spin" size={18} /> : authMode === 'login' ? <LogIn size={18} /> : <UserPlus size={18} />}
          {authSubmitting ? 'Aguarde...' : authMode === 'login' ? 'Entrar' : 'Criar conta'}
        </button>
        <button type="button" onClick={() => { setAuthMode(authMode === 'login' ? 'signup' : 'login'); setAuthError(''); setAuthMessage(''); }} className="mt-4 w-full text-sm text-blue-300">
          {authMode === 'login' ? 'Ainda não tenho conta — criar agora' : 'Já tenho conta — entrar'}
        </button>
      </form>
    </div>
  ) : null;

  const legalModal = legalView ? (
    <div className="fixed inset-0 z-[60] flex items-center justify-center bg-black/80 px-4 py-8 backdrop-blur-sm">
      <section className="glass-input max-h-full w-full max-w-2xl overflow-y-auto rounded-3xl p-6 shadow-2xl md:p-8">
        <div className="mb-6 flex items-start justify-between gap-4">
          <div>
            <p className="text-xs font-semibold uppercase tracking-[0.18em] text-blue-300">ShadowingAI</p>
            <h2 className="mt-1 font-serif text-3xl font-semibold">
              {legalView === 'privacy' ? 'Privacidade' : legalView === 'terms' ? 'Termos de uso' : 'Créditos e licença'}
            </h2>
          </div>
          <button type="button" onClick={() => setLegalView(null)} className="rounded-full bg-white/10 p-2 text-gray-300" aria-label="Fechar"><X size={20} /></button>
        </div>

        {legalView === 'privacy' && (
          <div className="space-y-4 text-sm leading-6 text-gray-300">
            <p>Usamos sua conta para autenticação, sincronização do progresso, preferências de estudo e controle de acesso aos recursos do aplicativo.</p>
            <p>Ao solicitar avaliação de pronúncia, sua gravação é enviada de forma autenticada ao nosso servidor e ao provedor de IA para gerar o resultado. O ShadowingAI não adiciona essa gravação à biblioteca permanente do usuário.</p>
            <p>Os arquivos das aulas ficam em armazenamento privado e são liberados por endereços temporários. Não vendemos seus dados pessoais.</p>
            <p>Você pode excluir sua conta e o progresso pelo botão de lixeira no perfil. Uma política pública completa, com contato e prazos de retenção, deverá ser publicada antes do lançamento comercial.</p>
          </div>
        )}

        {legalView === 'terms' && (
          <div className="space-y-4 text-sm leading-6 text-gray-300">
            <p>O aplicativo oferece material educacional para prática de inglês. A conta é pessoal e não pode ser compartilhada para contornar limites ou controles de acesso.</p>
            <p>Vídeos, áudios, legendas e traduções da biblioteca só podem ser usados dentro das permissões exibidas em cada aula. É proibido copiar, redistribuir ou explorar comercialmente os arquivos.</p>
            <p>Resultados de IA são auxiliares e podem conter imprecisões. O catálogo pode mudar quando uma licença expirar, for retirada ou ficar indisponível em determinado território.</p>
            <p>Estes termos internos ainda deverão passar por revisão jurídica e receber uma URL pública antes da distribuição comercial.</p>
          </div>
        )}

        {legalView === 'credits' && (
          <div className="space-y-4 text-sm leading-6 text-gray-300">
            {currentContent?.rights ? (
              <>
                <div><span className="block text-xs uppercase tracking-wider text-gray-500">Conteúdo</span><strong className="text-white">{currentContent.title}</strong></div>
                <div><span className="block text-xs uppercase tracking-wider text-gray-500">Criador</span><strong className="text-white">{currentContent.creator}</strong></div>
                <div><span className="block text-xs uppercase tracking-wider text-gray-500">Titular dos direitos</span><strong className="text-white">{currentContent.rights.rightsHolder}</strong></div>
                <div><span className="block text-xs uppercase tracking-wider text-gray-500">Base de uso</span><strong className="text-white">{currentContent.rights.licenseName || currentContent.rights.basis}</strong></div>
                {currentContent.rights.attributionText && <p className="rounded-2xl bg-white/5 p-4">{currentContent.rights.attributionText}</p>}
                <div className="flex flex-wrap gap-3">
                  {currentContent.rights.licenseUrl && <a href={currentContent.rights.licenseUrl} target="_blank" rel="noreferrer" className="rounded-xl bg-white/10 px-4 py-2 text-blue-300">Ver licença</a>}
                  <a href={currentContent.rights.sourceUrl} target="_blank" rel="noreferrer" className="rounded-xl bg-white/10 px-4 py-2 text-blue-300">Ver fonte</a>
                </div>
              </>
            ) : <p>Abra uma aula para consultar seus créditos e sua licença.</p>}
          </div>
        )}
      </section>
    </div>
  ) : null;

  if (!authReady) {
    return <div className="bg-atmosphere flex min-h-screen items-center justify-center"><Loader2 className="animate-spin text-blue-300" size={36} /></div>;
  }

  if (!firebaseAuthConfigured) {
    return (
      <div className="bg-atmosphere flex min-h-screen items-center justify-center px-6 text-white">
        <div className="glass-input max-w-xl rounded-3xl p-8 text-center">
          <h1 className="font-serif text-4xl font-semibold">Backend comercial não configurado</h1>
          <p className="mt-4 text-gray-400">Configure as variáveis públicas `VITE_FIREBASE_*` e `VITE_API_URL` antes de gerar o aplicativo.</p>
        </div>
      </div>
    );
  }

  if (screen === 'practice' && currentContent && activeSegment) {
    return (
      <div className="bg-atmosphere flex min-h-screen flex-col text-white">
        <header className="flex items-center justify-between gap-3 p-4 md:p-6">
          <button onClick={() => { cancelLoopPause(); videoRef.current?.pause(); setScreen('catalog'); }} className="glass-input flex items-center rounded-full px-4 py-2.5 text-sm text-gray-200">
            <ArrowLeft size={18} className="mr-2" /> Biblioteca
          </button>
          <div className="flex min-w-0 items-center gap-2 text-right">
            <div className="min-w-0"><p className="max-w-[42vw] truncate text-sm font-semibold">{currentContent.title}</p><p className="text-xs text-gray-500">Frase {activeIndex + 1} de {segments.length}</p></div>
            <button onClick={() => setLegalView('credits')} className="glass-input rounded-full p-2 text-blue-300" title="Créditos e licença"><Info size={18} /></button>
          </div>
        </header>

        <main className="practice-shell flex-1 px-4 pb-28 pt-2">
          <div className="practice-player glass-input relative aspect-video w-full max-w-3xl overflow-hidden rounded-2xl bg-black shadow-2xl">
            <video
              ref={videoRef}
              src={mediaUrl}
              poster={currentContent.artworkUrl || undefined}
              playsInline
              controls
              preload="metadata"
              className="absolute inset-0 h-full w-full object-contain"
              onLoadedMetadata={() => { if (adjustedWindow && videoRef.current) videoRef.current.currentTime = adjustedWindow.start; }}
              onPlay={() => setIsPlaying(true)}
              onPause={() => { if (!automaticPauseRef.current) setIsPlaying(false); }}
              onError={() => setPlayerError('Não foi possível carregar a mídia privada desta aula.')}
            />
            {!isPlaying && !loopWaiting && !playerError && (
              <button onClick={togglePlayback} className="absolute left-1/2 top-1/2 flex h-16 w-16 -translate-x-1/2 -translate-y-1/2 items-center justify-center rounded-full bg-red-600 shadow-2xl">
                <Play size={32} className="ml-1" />
              </button>
            )}
            {loopWaiting && <div className="pointer-events-none absolute inset-0 flex items-center justify-center bg-black/45"><span className="rounded-full border border-blue-300/30 bg-blue-950/90 px-5 py-2 text-sm font-semibold">Sua vez · repita a frase</span></div>}
            {playerError && <div className="absolute inset-0 flex items-center justify-center bg-black/90 px-6 text-center text-red-200">{playerError}</div>}
          </div>

          <div className="practice-content mx-auto mt-6 flex max-w-3xl flex-col items-center justify-center space-y-5 px-4 text-center md:mt-12">
            {dictationMode ? (
              <div className="w-full max-w-2xl">
                <p className="mb-4 text-sm uppercase tracking-[0.18em] text-blue-300">Treino de ouvido</p>
                <textarea value={dictationAnswer} onChange={(event) => setDictationAnswer(event.target.value)} placeholder="Escreva em inglês o que você ouviu..." className="glass-input h-32 w-full resize-none rounded-2xl p-4 text-left text-lg text-white outline-none focus:border-blue-400" />
                <button onClick={() => setDictationFeedback(evaluateDictation(activeSegment.text, dictationAnswer))} disabled={!dictationAnswer.trim()} className="mt-3 inline-flex items-center gap-2 rounded-xl bg-white px-5 py-3 font-semibold text-black disabled:opacity-40"><Check size={18} /> Conferir resposta</button>
              </div>
            ) : (
              <>
                <p className="practice-phrase font-serif text-3xl font-semibold leading-tight md:text-5xl">{activeSegment.text}</p>
                {activeSegment.translation && <p className="practice-translation text-xs font-semibold uppercase tracking-[0.18em] text-gray-400 md:text-sm">{activeSegment.translation}</p>}
              </>
            )}

            {dictationFeedback && (
              <div className="glass-input w-full max-w-2xl rounded-2xl p-5 text-left">
                <div className="flex items-center justify-between"><span className="text-sm text-gray-400">Compreensão auditiva</span><strong className="text-2xl text-blue-300">{dictationFeedback.score}%</strong></div>
                <p className="mt-2 text-sm">{dictationFeedback.message}</p>
                {dictationFeedback.missingWords.length > 0 && <p className="mt-2 text-sm text-yellow-200">Revise: {dictationFeedback.missingWords.join(', ')}</p>}
              </div>
            )}

            {analyzing && <p className="flex items-center gap-2 text-sm text-blue-200"><Loader2 className="animate-spin" size={17} /> Avaliando sua pronúncia...</p>}
            {recordingUrl && <audio src={recordingUrl} controls className="h-10" />}
            {pronunciationFeedback && (
              <div className="glass-input w-full max-w-2xl rounded-2xl p-5 text-left">
                <div className="flex items-center justify-between"><span className="text-sm text-gray-400">Pronúncia</span><strong className="text-2xl text-emerald-300">{pronunciationFeedback.score}%</strong></div>
                <div className="mt-3 flex flex-wrap gap-2">{pronunciationFeedback.words.map((word, index) => <span key={`${word.word}-${index}`} title={word.tip} className={`rounded-lg border px-2 py-1 text-sm ${word.correct ? 'border-emerald-500/30 bg-emerald-500/10 text-emerald-200' : 'border-red-500/30 bg-red-500/10 text-red-200'}`}>{word.word}</span>)}</div>
              </div>
            )}
          </div>
        </main>

        <footer className="practice-controls fixed bottom-0 left-0 z-20 flex w-full items-center justify-center gap-3 bg-gradient-to-t from-black via-black/90 to-transparent px-3 pb-6 pt-8 md:gap-7">
          <button onClick={() => setLoopActive(!loopActive)} className={`rounded-full p-3 ${loopActive ? 'bg-blue-400/10 text-blue-300' : 'text-gray-500'}`} title="Repetir frase"><Repeat size={21} /></button>
          <button onClick={() => changeSegment(activeIndex - 1)} disabled={activeIndex === 0} className="rounded-full p-3 disabled:opacity-30"><SkipBack size={25} /></button>
          <button onClick={toggleRecording} className={`flex h-16 w-16 items-center justify-center rounded-full border border-white/20 md:h-20 md:w-20 ${recording ? 'mic-pulse bg-red-500' : 'bg-white/10'}`}><Mic size={30} /></button>
          <button onClick={() => changeSegment(activeIndex + 1)} disabled={activeIndex >= segments.length - 1} className="rounded-full p-3 disabled:opacity-30"><SkipForward size={25} /></button>
          <button onClick={togglePlayback} className="rounded-full p-3 text-gray-200">{isPlaying || loopWaiting ? <Pause size={22} /> : <Play size={22} />}</button>
          <button onClick={() => { setDictationMode(!dictationMode); setDictationAnswer(''); setDictationFeedback(null); }} className={`rounded-full p-3 ${dictationMode ? 'bg-blue-400/10 text-blue-300' : 'text-gray-400'}`}>{dictationMode ? <EyeOff size={22} /> : <Eye size={22} />}</button>
          <div className="relative">
            {timingOpen && (
              <div className="absolute bottom-full right-0 mb-4 w-56 rounded-2xl border border-white/10 bg-gray-950/95 p-3 shadow-2xl">
                <div className="mb-2 flex items-center justify-between text-xs text-gray-400"><span>Ajuste fino</span><button onClick={() => activeTimingKey && setTimingOffsets((items) => ({ ...items, [activeTimingKey]: 0 }))} className="text-blue-300">{timingOffsetMs > 0 ? '+' : ''}{timingOffsetMs} ms</button></div>
                <div className="grid grid-cols-2 gap-2"><button onClick={() => updateTiming(-TIMING_STEP_MS)} className="rounded-xl bg-white/10 p-2">-100 ms</button><button onClick={() => updateTiming(TIMING_STEP_MS)} className="rounded-xl bg-white/10 p-2">+100 ms</button></div>
              </div>
            )}
            <button onClick={() => setTimingOpen(!timingOpen)} className={`rounded-full p-3 ${timingOpen || timingOffsetMs ? 'bg-blue-400/10 text-blue-300' : 'text-gray-400'}`}><SlidersHorizontal size={22} /></button>
          </div>
        </footer>
        {legalModal}
      </div>
    );
  }

  return (
    <div className="bg-atmosphere min-h-screen text-white">
      <header className="flex items-center justify-between px-6 py-6 md:px-12">
        <div className="flex items-center gap-2"><div className="h-8 w-8 rounded-full bg-gradient-to-tr from-blue-600 to-purple-600" /><span className="text-xl font-bold">ShadowingAI</span></div>
        {user ? (
          <div className="flex items-center gap-2">
            <button onClick={logout} className="glass-input flex items-center rounded-full px-4 py-2.5 text-sm"><LogOut size={16} className="mr-2" /> {user.name}</button>
            <button onClick={deleteAccount} className="glass-input rounded-full p-2.5 text-gray-500 hover:text-red-300" title="Excluir conta"><Trash2 size={17} /></button>
          </div>
        ) : <button onClick={() => openAuth('login')} className="rounded-full border border-white/10 bg-white/10 px-5 py-2.5 text-sm"><LogIn size={16} className="mr-2 inline" /> Entrar</button>}
      </header>

      <main className="discovery-shell mx-auto flex w-full max-w-6xl flex-col items-center px-4 pb-24 pt-6 md:pt-14">
        <div className="mb-10 text-center md:mb-14">
          <h1 className="font-serif text-4xl font-semibold leading-tight md:text-7xl">Inglês real, no ritmo <span className="bg-gradient-to-r from-blue-400 to-purple-400 bg-clip-text text-transparent">certo para você.</span></h1>
          <p className="mx-auto mt-4 max-w-2xl text-gray-400 md:text-xl">Aulas licenciadas, frases revisadas e prática de shadowing em qualquer dispositivo.</p>
        </div>

        {!user ? (
          <section className="glass-input w-full max-w-2xl rounded-3xl p-8 text-center md:p-12">
            <h2 className="text-2xl font-semibold">Entre para abrir sua biblioteca</h2>
            <p className="mx-auto mt-3 max-w-lg text-gray-400">O login protege seu histórico, limita o uso da IA e sincroniza seu progresso.</p>
            <div className="mt-7 flex flex-col justify-center gap-3 sm:flex-row"><button onClick={() => openAuth('login')} className="rounded-xl bg-white px-6 py-3 font-bold text-black">Entrar</button><button onClick={() => openAuth('signup')} className="rounded-xl border border-white/15 bg-white/5 px-6 py-3 font-semibold">Criar conta</button></div>
          </section>
        ) : (
          <div className="w-full space-y-8">
            {catalogError && <p className="rounded-2xl border border-red-500/30 bg-red-950/30 p-4 text-center text-red-200">{catalogError}</p>}
            {history.length > 0 && (
              <section>
                <h2 className="mb-4 flex items-center gap-2 font-semibold"><History size={18} className="text-blue-300" /> Continuar estudando</h2>
                <div className="grid gap-4 md:grid-cols-3">{history.map(({ content, progress: item }) => (
                  <button key={content.id} onClick={() => openContent(content)} className="glass-input overflow-hidden rounded-2xl text-left">
                    <div className="flex gap-3 p-3"><div className="aspect-video w-28 overflow-hidden rounded-xl bg-white/5">{content.artworkUrl && <img src={content.artworkUrl} alt="" className="h-full w-full object-cover" />}</div><div className="min-w-0 flex-1"><h3 className="line-clamp-2 text-sm font-semibold">{content.title}</h3><p className="mt-1 truncate text-xs text-blue-300">{content.creator}</p><p className="mt-2 text-xs text-gray-500">Frase {item.segment_position + 1} · {formatRelativeDate(item.last_studied_at)}</p></div></div>
                    <div className="h-1.5 bg-white/5"><div className="h-full bg-blue-400" style={{ width: `${item.completed_percent}%` }} /></div>
                  </button>
                ))}</div>
              </section>
            )}

            <section className="glass-input rounded-3xl p-6 md:p-10">
              <div className="mb-7 flex items-center gap-3"><div className="flex h-11 w-11 items-center justify-center rounded-2xl bg-blue-500/15"><Search className="text-blue-300" /></div><div><h2 className="text-2xl font-semibold">Escolha sua próxima aula</h2><p className="text-sm text-gray-400">Filtre a biblioteca por assunto e ritmo.</p></div></div>
              <p className="mb-3 text-sm text-gray-300">Tema de interesse</p>
              <div className="hide-scrollbar flex gap-2 overflow-x-auto pb-2">{THEMES.map((theme) => <button key={theme} onClick={() => setSelectedTheme(selectedTheme === theme ? '' : theme)} className={`whitespace-nowrap rounded-xl border px-4 py-3 text-sm ${selectedTheme === theme ? 'border-blue-400/50 bg-blue-500/20 text-blue-100' : 'border-white/10 bg-white/5 text-gray-300'}`}>{theme}</button>)}</div>
              <p className="mb-3 mt-5 text-sm text-gray-300">Nível</p>
              <div className="grid gap-3 md:grid-cols-3">{DIFFICULTIES.map((difficulty) => <button key={difficulty.id} onClick={() => setSelectedDifficulty(selectedDifficulty === difficulty.id ? '' : difficulty.id)} className={`rounded-xl border p-4 text-left ${selectedDifficulty === difficulty.id ? 'border-blue-400/50 bg-blue-500/15' : 'border-white/10 bg-black/20'}`}><strong className="text-sm">{difficulty.label}</strong><span className="mt-1 block text-xs uppercase tracking-wider text-gray-500">{difficulty.detail}</span></button>)}</div>
              <button onClick={() => setShowRecommendations(true)} disabled={catalogLoading} className="mt-7 flex w-full items-center justify-center gap-2 rounded-2xl bg-white py-4 font-bold text-black disabled:opacity-50">{catalogLoading ? <Loader2 className="animate-spin" /> : <Search size={20} />} Mostrar aulas</button>
            </section>

            {(showRecommendations || (!selectedTheme && !selectedDifficulty)) && (
              <section>
                <h2 className="mb-4 text-xl font-semibold">Biblioteca</h2>
                {openingContent && <p className="mb-4 flex items-center gap-2 text-blue-200"><Loader2 className="animate-spin" size={18} /> Abrindo aula...</p>}
                {!catalogLoading && recommendations.length === 0 ? <p className="glass-input rounded-2xl p-6 text-center text-gray-400">A biblioteca piloto está sendo preparada. Publique o primeiro conteúdo aprovado para ele aparecer aqui.</p> : (
                  <div className="grid gap-5 sm:grid-cols-2 lg:grid-cols-3">{recommendations.map((content) => (
                    <button key={content.id} onClick={() => openContent(content)} disabled={openingContent} className="glass-input group overflow-hidden rounded-2xl text-left transition hover:-translate-y-1 hover:border-blue-400/30 disabled:opacity-50">
                      <div className="aspect-video bg-white/5">{content.artworkUrl && <img src={content.artworkUrl} alt={content.title} className="h-full w-full object-cover transition duration-500 group-hover:scale-105" />}</div>
                      <div className="p-5"><span className="text-[10px] font-bold uppercase tracking-wider text-blue-300">{content.difficulty} · {content.theme}</span><h3 className="mt-2 line-clamp-2 font-semibold">{content.title}</h3><p className="mt-2 text-sm text-gray-500">{content.creator}</p><p className="mt-3 line-clamp-2 text-xs text-gray-400">{content.description}</p></div>
                    </button>
                  ))}</div>
                )}
              </section>
            )}
          </div>
        )}
      </main>
      <footer className="flex flex-wrap items-center justify-center gap-5 px-6 pb-10 text-xs text-gray-500">
        <button onClick={() => setLegalView('privacy')} className="inline-flex items-center gap-1.5 hover:text-blue-300"><FileText size={14} /> Privacidade</button>
        <button onClick={() => setLegalView('terms')} className="hover:text-blue-300">Termos de uso</button>
      </footer>
      {authModal}
      {legalModal}
    </div>
  );
}
