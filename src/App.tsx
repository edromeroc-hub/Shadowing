import { useState, useRef, useEffect } from 'react';
import YouTube from 'react-youtube';
import { Mic, SkipBack, SkipForward, Repeat, Link2, Play, Download, Loader2, LogIn, LogOut, ArrowLeft, Search, Youtube, Target, History, Trash2 } from 'lucide-react';
import { auth, storage } from './lib/firebase';
import { signInWithPopup, GoogleAuthProvider, onAuthStateChanged, User, signOut } from 'firebase/auth';
import { ref, uploadBytes, getDownloadURL } from 'firebase/storage';

type Phrase = {
  start: number;
  end: number;
  text: string;
  phonetic: string;
  translation: string;
};

type StudyHistoryItem = {
  videoId: string;
  url: string;
  title: string;
  thumbnail: string;
  phraseIndex: number;
  phraseCount: number;
  lastStudiedAt: number;
};

const STUDY_HISTORY_KEY = 'shadowing.studyHistory.v1';
const MAX_STUDY_HISTORY_ITEMS = 8;

function readStudyHistory(): StudyHistoryItem[] {
  try {
    const raw = localStorage.getItem(STUDY_HISTORY_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

function writeStudyHistory(items: StudyHistoryItem[]) {
  localStorage.setItem(STUDY_HISTORY_KEY, JSON.stringify(items.slice(0, MAX_STUDY_HISTORY_ITEMS)));
}

function formatLastStudiedAt(timestamp: number) {
  const diffMs = Date.now() - timestamp;
  const diffMinutes = Math.max(1, Math.floor(diffMs / 60000));
  if (diffMinutes < 60) return `${diffMinutes} min atrás`;
  const diffHours = Math.floor(diffMinutes / 60);
  if (diffHours < 24) return `${diffHours} h atrás`;
  const diffDays = Math.floor(diffHours / 24);
  return `${diffDays} d atrás`;
}

// Utilities for converting timecode to seconds
function timeToSeconds(timeStr: string) {
  const parts = timeStr.trim().split(':');
  let hours = 0, minutes = 0, secondsAndMs = '0';
  
  if (parts.length === 3) {
      hours = parseInt(parts[0], 10);
      minutes = parseInt(parts[1], 10);
      secondsAndMs = parts[2];
  } else if (parts.length === 2) {
      minutes = parseInt(parts[0], 10);
      secondsAndMs = parts[1];
  }

  const [seconds, ms] = secondsAndMs.split(/[,.]/);
  return (
    hours * 3600 +
    minutes * 60 +
    parseInt(seconds, 10) +
    parseInt(ms || '0', 10) / 1000
  );
}

function parseSrt(srtText: string): { text: string; start: number; end: number }[] {
  // Check if it's a raw copy-paste from YouTube transcript window
  // Format usually: 
  // 0:00
  // hello
  // 0:02
  // world
  // OR
  // 0:00 hello
  // 0:02 world
  
  // If no "-->" is found, try to parse it as raw text
  if (!srtText.includes('-->') && !srtText.includes('WEBVTT')) {
     const lines = srtText.split(/\r?\n/).map(l => l.trim()).filter(l => l.length > 0);
     const items = [];
     let currentStart = -1;
     let currentText = '';

     for (const line of lines) {
       // Match timestamp patterns like 0:00, 10:02, 1:05:22
       const tsMatch = line.match(/^(\d{1,2}(?::\d{2})+)\s*(.*)$/);
       if (tsMatch) {
         if (currentStart >= 0 && currentText.trim()) {
           items.push({
              start: currentStart,
              end: timeToSeconds(tsMatch[1]), // end is approximately start of next
              text: currentText.trim()
           });
         }
         currentStart = timeToSeconds(tsMatch[1]);
         currentText = tsMatch[2]; // If there's text on the same line
       } else {
         currentText += ' ' + line;
       }
     }
     if (currentStart >= 0 && currentText.trim()) {
       items.push({
         start: currentStart,
         end: currentStart + 5,
         text: currentText.trim()
       });
     }
     if (items.length > 0) return items;
  }

  // Fallback to standard SRT/VTT parsing
  const text = srtText.replace(/^WEBVTT.*\r?\n(\r?\n)?/i, '');
  const blocks = text.split(/\r?\n\r?\n/).filter(val => val.trim().length > 0);
  const items = [];
  for (const block of blocks) {
    const lines = block.split(/\r?\n/);
    if (lines.length >= 2) {
      let timeLineIdx = lines[0].includes('-->') ? 0 : 1;
      if (timeLineIdx === 1 && lines.length < 3) continue;

      const timeLine = lines[timeLineIdx];
      const textLines = lines.slice(timeLineIdx + 1).join(' ');
      const match = timeLine.match(/(\d{2}:\d{2}:\d{2}[,.]\d{3}|\d{2}:\d{2}[,.]\d{3}|\d{1,2}:\d{2})\s*-->\s*(\d{2}:\d{2}:\d{2}[,.]\d{3}|\d{2}:\d{2}[,.]\d{3}|\d{1,2}:\d{2})/);
      
      if (match) {
        items.push({
          start: timeToSeconds(match[1]),
          end: timeToSeconds(match[2]),
          text: textLines.replace(/(<([^>]+)>)/ig, ""), // remove HTML tags
        });
      }
    }
  }
  return items;
}

function extractVideoID(url: string) {
  const regExp = /^.*((youtu.be\/)|(v\/)|(\/u\/\w\/)|(embed\/)|(watch\?))\??v?=?([^#&?]*).*/;
  const match = url.match(regExp);
  return (match && match[7].length === 11) ? match[7] : false;
}

type WordFeedback = {
  word: string;
  correct: boolean;
  tip: string;
};

type PronunciationFeedback = {
  score: number;
  words: WordFeedback[];
};

const DISCOVERY_THEMES = ['Viagem e Cultura', 'Tecnologia', 'Negócios/Trabalho', 'Cinema e Séries', 'Notícias e Debates'];
const DISCOVERY_DIFFICULTIES = [
  { id: 'beginner', label: 'Iniciante - Fala mais lenta' },
  { id: 'intermediate', label: 'Intermediário - Ritmo natural' },
  { id: 'advanced', label: 'Avançado - Fala rápida/Nativa' }
];

const MOCK_RECOMMENDATIONS = [
  {
    id: '0kH8pY1mE1M',
    title: 'How to Speak English Fluently like an American',
    channel: 'English with Lucy',
    difficulty: 'Iniciante',
    thumbnail: 'https://img.youtube.com/vi/0kH8pY1mE1M/mqdefault.jpg'
  },
  {
    id: 'dQw4w9WgXcQ',
    title: 'Never Gonna Give You Up (Language Breakdown)',
    channel: 'Music English',
    difficulty: 'Intermediário',
    thumbnail: 'https://img.youtube.com/vi/dQw4w9WgXcQ/mqdefault.jpg'
  },
  {
    id: 'fJ9rUzIMcZQ',
    title: 'Bohemian Rhapsody Singing Practice',
    channel: 'Queen English',
    difficulty: 'Avançado',
    thumbnail: 'https://img.youtube.com/vi/fJ9rUzIMcZQ/mqdefault.jpg'
  }
];

export default function App() {
  const [currentScreen, setCurrentScreen] = useState<'discovery' | 'practice'>('discovery');
  const [selectedTheme, setSelectedTheme] = useState<string>('');
  const [selectedDifficulty, setSelectedDifficulty] = useState<string>('');
  const [isSearching, setIsSearching] = useState(false);
  const [recommendations, setRecommendations] = useState<any[]>([]);
  const [discoveryUrl, setDiscoveryUrl] = useState('');
  const [studyHistory, setStudyHistory] = useState<StudyHistoryItem[]>([]);

  const [url, setUrl] = useState("https://www.youtube.com/watch?v=0kH8pY1mE1M");
  const [videoId, setVideoId] = useState("0kH8pY1mE1M");
  const [activePhraseIndex, setActivePhraseIndex] = useState(0);
  const [isLoopActive, setIsLoopActive] = useState(true);
  const [isRecording, setIsRecording] = useState(false);
  const [playerReady, setPlayerReady] = useState(false);
  const [hasStartedPlaying, setHasStartedPlaying] = useState(false);
  
  const [phrases, setPhrases] = useState<Phrase[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const [user, setUser] = useState<User | null>(null);
  const [recordingUrl, setRecordingUrl] = useState<string | null>(null);
  const [feedback, setFeedback] = useState<PronunciationFeedback | null>(null);
  const [isAnalyzing, setIsAnalyzing] = useState(false);

  const mediaRecorderRef = useRef<MediaRecorder | null>(null);
  const audioChunksRef = useRef<Blob[]>([]);
  const pendingPhraseIndexRef = useRef(0);

  // `any` used for simplicity as react-youtube player object type can be complex
  const playerRef = useRef<any>(null);

  const activePhrase = phrases[activePhraseIndex] || null;

  const saveStudyProgress = (item: StudyHistoryItem) => {
    setStudyHistory((current) => {
      const next = [
        item,
        ...current.filter((historyItem) => historyItem.videoId !== item.videoId),
      ].slice(0, MAX_STUDY_HISTORY_ITEMS);
      writeStudyHistory(next);
      return next;
    });
  };

  const startPractice = (id: string, fullUrl: string, phraseIndex = 0, title?: string) => {
    pendingPhraseIndexRef.current = phraseIndex;
    setVideoId(id);
    setUrl(fullUrl);
    setPhrases([]);
    setFeedback(null);
    setRecordingUrl(null);
    setError(null);
    setActivePhraseIndex(phraseIndex);
    saveStudyProgress({
      videoId: id,
      url: fullUrl,
      title: title || `YouTube ${id}`,
      thumbnail: `https://img.youtube.com/vi/${id}/mqdefault.jpg`,
      phraseIndex,
      phraseCount: 0,
      lastStudiedAt: Date.now(),
    });
    setCurrentScreen('practice');
  };

  const removeFromHistory = (id: string) => {
    setStudyHistory((current) => {
      const next = current.filter((item) => item.videoId !== id);
      writeStudyHistory(next);
      return next;
    });
  };

  const handleFindVideos = async () => {
    if (!selectedTheme || !selectedDifficulty) {
      alert('Selecione um tema e uma dificuldade.');
      return;
    }
    setIsSearching(true);
    setRecommendations([]);
    try {
      const res = await fetch("/api/recommendVideos", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ theme: selectedTheme, difficulty: selectedDifficulty }),
      });
      if (!res.ok) {
        throw new Error("Failed to search videos");
      }
      const data = await res.json();
      setRecommendations(data);
    } catch (err) {
      console.error("Error searching videos:", err);
      alert("Houve um erro ao buscar os vídeos. Tente novamente.");
    } finally {
      setIsSearching(false);
    }
  };

  const handleDirectLink = () => {
    const id = extractVideoID(discoveryUrl);
    if (id) {
       startPractice(id, discoveryUrl);
    } else {
       alert("Link inválido ou não suportado do YouTube. Certifique-se de que é um link real de vídeo.");
    }
  };

  useEffect(() => {
    setStudyHistory(readStudyHistory());
  }, []);

  useEffect(() => {
    if (currentScreen === 'practice' && videoId && phrases.length === 0 && !isLoading && !error) {
      loadTranscript();
    }
  }, [currentScreen, videoId, phrases.length, isLoading, error]);

  const loadTranscript = async () => {
    if (!videoId) return;
    setIsLoading(true);
    setError(null);
    setPhrases([]);
    setActivePhraseIndex(pendingPhraseIndexRef.current);
    setRecordingUrl(null);

    try {
      const res = await fetch("/api/getEnrichedTranscript", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ videoId }),
      });

      if (!res.ok) {
        const errData = await res.json();
        throw new Error(errData.error || "Failed to load transcript");
      }

      const data = await res.json();
      setPhrases(data);
      setActivePhraseIndex(Math.min(pendingPhraseIndexRef.current, Math.max(data.length - 1, 0)));
    } catch (err: any) {
      setError(err.message);
    } finally {
      setIsLoading(false);
    }
  };

  const onPlayerReady = (event: any) => {
    playerRef.current = event.target;
    setPlayerReady(true);
    // Start at the active phrase but DO NOT autoplay to avoid browser policy errors
    if (activePhrase) {
      try {
        event.target.seekTo(activePhrase.start, true);
      } catch (e) {
        console.warn("Could not seek initially:", e);
      }
    }
  };

  const onPlayerError = (event: any) => {
    console.error("YouTube Player Error:", event.data);
  };

  // The interval for polling playback time
  useEffect(() => {
    if (!playerReady || !playerRef.current || phrases.length === 0) return;
    
    // Polling interval to check if video crossed the 'end' threshold
    const interval = setInterval(async () => {
      try {
        const player = playerRef.current;
        if (player && typeof player.getCurrentTime === 'function') {
          const currentTime = await player.getCurrentTime();
          const targetEnd = phrases[activePhraseIndex].end;
          
          if (currentTime >= targetEnd) {
            if (isLoopActive) {
              player.seekTo(phrases[activePhraseIndex].start, true);
            } else {
              player.pauseVideo();
            }
          }
        }
      } catch (err) {
        // Ignore iframe communication errors that can happen temporarily
      }
    }, 100);
    
    return () => clearInterval(interval);
  }, [activePhraseIndex, isLoopActive, playerReady, phrases]);

  // Jump strictly to active phrase whenever the phrase changes
  useEffect(() => {
    if (playerReady && playerRef.current && phrases.length > 0) {
      const player = playerRef.current;
      player.seekTo(phrases[activePhraseIndex].start, true);
      if (hasStartedPlaying) {
        player.playVideo();
      }
    }
  }, [activePhraseIndex, playerReady, hasStartedPlaying, phrases]);

  const handleNext = () => {
    if (phrases.length === 0) return;
    setHasStartedPlaying(true);
    setRecordingUrl(null);
    setFeedback(null);
    setActivePhraseIndex((prev) => (prev < phrases.length - 1 ? prev + 1 : prev));
  };

  useEffect(() => {
    if (currentScreen !== 'practice' || !videoId || phrases.length === 0) return;

    const existing = studyHistory.find((item) => item.videoId === videoId);
    saveStudyProgress({
      videoId,
      url,
      title: existing?.title || `YouTube ${videoId}`,
      thumbnail: existing?.thumbnail || `https://img.youtube.com/vi/${videoId}/mqdefault.jpg`,
      phraseIndex: activePhraseIndex,
      phraseCount: phrases.length,
      lastStudiedAt: Date.now(),
    });
  }, [currentScreen, videoId, url, activePhraseIndex, phrases.length]);

  const handlePrev = () => {
    if (phrases.length === 0) return;
    setHasStartedPlaying(true);
    setRecordingUrl(null);
    setFeedback(null);
    setActivePhraseIndex((prev) => (prev > 0 ? prev - 1 : prev));
  };

  useEffect(() => {
    const unsub = onAuthStateChanged(auth, (usr) => {
      setUser(usr);
    });
    return () => unsub();
  }, []);

  const handleLogin = async () => {
    const provider = new GoogleAuthProvider();
    try {
      await signInWithPopup(auth, provider);
    } catch (err) {
      console.error(err);
    }
  };

  const handleLogout = async () => {
    await signOut(auth);
  };

  const analyzePronunciationFeedback = async (audioUrl: string, phraseText: string) => {
    setIsAnalyzing(true);
    try {
      const res = await fetch("/api/analyzePronunciation", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ audioUrl, phrase: phraseText }),
      });
      if (!res.ok) throw new Error("Failed to analyze");
      const data = await res.json();
      setFeedback(data);
    } catch (err) {
      console.error("Analysis error:", err);
      // Optional: alert an error or set an error state
    } finally {
      setIsAnalyzing(false);
    }
  };

  const toggleRecording = async () => {
    if (!user) {
      alert("Por favor, faça login para gravar");
      return handleLogin();
    }

    if (isRecording) {
      // STOP recording
      if (mediaRecorderRef.current && mediaRecorderRef.current.state !== 'inactive') {
        mediaRecorderRef.current.stop();
      }
      setIsRecording(false);
    } else {
      // START recording
      try {
        setRecordingUrl(null);
        setFeedback(null);
        if (playerRef.current) {
          playerRef.current.pauseVideo();
        }
        
        const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
        // Use a widely supported mimeType
        const mimeType = MediaRecorder.isTypeSupported('audio/webm') 
            ? 'audio/webm' 
            : (MediaRecorder.isTypeSupported('audio/mp4') ? 'audio/mp4' : '');
            
        const recorder = new MediaRecorder(stream, mimeType ? { mimeType } : undefined);
        audioChunksRef.current = [];

        recorder.ondataavailable = (e) => {
          if (e.data.size > 0) {
            audioChunksRef.current.push(e.data);
          }
        };

        recorder.onstop = async () => {
          const ext = mimeType.includes('mp4') ? 'mp4' : 'webm';
          const audioBlob = new Blob(audioChunksRef.current, { type: mimeType || 'audio/webm' });
          // Stop all tracks
          stream.getTracks().forEach(track => track.stop());
          
          // Upload to Firebase Storage
          try {
            const fileName = `user_recordings/${user.uid}/${videoId}/${activePhraseIndex}.${ext}`;
            const fileRef = ref(storage, fileName);
            await uploadBytes(fileRef, audioBlob);
            const downloadUrl = await getDownloadURL(fileRef);
            setRecordingUrl(downloadUrl);
            console.log("Audio uploaded to:", downloadUrl);
            
            if (activePhrase) {
              analyzePronunciationFeedback(downloadUrl, activePhrase.text);
            }
          } catch(err) {
            console.error("Error uploading audio:", err);
            alert("Erro ao fazer upload do aúdio.");
          }
        };

        mediaRecorderRef.current = recorder;
        recorder.start();
        setIsRecording(true);

      } catch (err) {
        console.error("Error accessing microphone:", err);
        alert("Erro ao acessar microfone. Verifique as permissões do navegador.");
      }
    }
  };

  const toggleGlobalPlay = () => {
    if (playerRef.current && phrases.length > 0) {
      try {
        const state = playerRef.current.getPlayerState();
        if (state === 1) {
          playerRef.current.pauseVideo();
        } else {
          setHasStartedPlaying(true);
          playerRef.current.playVideo();
        }
      } catch (e) {
        console.error("Play toggle error", e);
      }
    }
  };

  if (currentScreen === 'discovery') {
    return (
      <div className="bg-atmosphere flex flex-col min-h-screen text-white w-full selection:bg-blue-500/30">
        {/* Superior Nav */}
        <header className="w-full flex justify-between items-center px-6 py-6 md:px-12 relative z-10">
          <div className="flex items-center gap-2">
            <div className="w-8 h-8 rounded-full bg-gradient-to-tr from-blue-600 to-purple-600 flex items-center justify-center shadow-lg shadow-blue-500/20" />
            <span className="font-bold text-xl tracking-tight text-white/90">ShadowingAI</span>
          </div>
          {user ? (
            <button onClick={handleLogout} className="glass-input px-5 py-2.5 rounded-full flex items-center text-gray-300 hover:text-white transition-colors text-sm font-medium">
              <LogOut size={16} className="mr-2 opacity-70"/> {user.email}
            </button>
          ) : (
            <button onClick={handleLogin} className="px-6 py-2.5 rounded-full flex items-center bg-white/10 hover:bg-white/20 border border-white/10 text-white transition-colors text-sm font-medium">
              <LogIn size={16} className="mr-2 opacity-70"/> Entrar
            </button>
          )}
        </header>

        <main className="flex-1 flex flex-col items-center px-4 w-full max-w-4xl mx-auto pb-24 relative z-10 mt-6 md:mt-16">
          
          <div className="text-center mb-8 md:mb-16 space-y-3 md:space-y-4">
            <h1 className="font-serif text-3xl md:text-6xl lg:text-7xl font-semibold leading-tight tracking-tight text-white drop-shadow-2xl">
              O que vamos <br className="md:hidden" />
              <span className="text-transparent bg-clip-text bg-gradient-to-r from-blue-400 via-indigo-400 to-purple-400">praticar hoje?</span>
            </h1>
            <p className="text-gray-400 text-base md:text-xl max-w-2xl mx-auto font-light tracking-wide px-4">
              Mergulhe no ritmo natural do inglês com vídeos autênticos.
            </p>
          </div>

          {studyHistory.length > 0 && (
            <section className="w-full mb-8 md:mb-10">
              <div className="flex items-center justify-between mb-4 px-1">
                <div className="flex items-center gap-2">
                  <History className="text-blue-300" size={18} />
                  <h2 className="text-sm md:text-base font-semibold text-gray-100">Continuar estudando</h2>
                </div>
                <span className="text-xs text-gray-500">{studyHistory.length} vídeos</span>
              </div>

              <div className="flex overflow-x-auto gap-4 pb-2 hide-scrollbar snap-x">
                {studyHistory.map((item) => {
                  const progress = item.phraseCount > 0
                    ? Math.min(100, Math.round(((item.phraseIndex + 1) / item.phraseCount) * 100))
                    : 0;

                  return (
                    <div
                      key={item.videoId}
                      className="min-w-[260px] md:min-w-[300px] snap-start bg-black/35 border border-white/10 rounded-2xl overflow-hidden group hover:border-blue-400/30 transition-colors"
                    >
                      <button
                        onClick={() => startPractice(item.videoId, item.url, item.phraseIndex, item.title)}
                        className="w-full text-left"
                      >
                        <div className="flex gap-3 p-3">
                          <div className="w-24 aspect-video rounded-xl overflow-hidden bg-gray-900 shrink-0">
                            <img src={item.thumbnail} alt={item.title} className="w-full h-full object-cover opacity-90 group-hover:opacity-100 transition-opacity" />
                          </div>
                          <div className="min-w-0 flex-1">
                            <h3 className="text-sm font-medium text-gray-100 line-clamp-2 leading-snug">{item.title}</h3>
                            <p className="text-xs text-gray-500 mt-1">
                              Frase {item.phraseCount > 0 ? item.phraseIndex + 1 : 1}{item.phraseCount > 0 ? ` de ${item.phraseCount}` : ''}
                            </p>
                            <p className="text-xs text-gray-500 mt-1">{formatLastStudiedAt(item.lastStudiedAt)}</p>
                          </div>
                        </div>
                        <div className="h-1.5 bg-white/5">
                          <div className="h-full bg-blue-400 transition-all" style={{ width: `${progress}%` }} />
                        </div>
                      </button>
                      <div className="px-3 py-2 border-t border-white/5 flex justify-between items-center">
                        <span className="text-[11px] text-gray-500 uppercase tracking-wider">{progress}% concluído</span>
                        <button
                          onClick={() => removeFromHistory(item.videoId)}
                          className="p-1.5 rounded-lg text-gray-500 hover:text-red-300 hover:bg-red-500/10 transition-colors"
                          title="Remover do histórico"
                        >
                          <Trash2 size={14} />
                        </button>
                      </div>
                    </div>
                  );
                })}
              </div>
            </section>
          )}

          <div className="w-full grid grid-cols-1 md:grid-cols-2 gap-6 md:gap-8 mb-12 md:mb-16">
            {/* SEÇÃO A - IA CURATION */}
            <div className="md:col-span-2 glass-input rounded-[2rem] p-6 md:p-10 shadow-2xl relative overflow-hidden group">
              <div className="absolute top-0 right-0 w-96 h-96 bg-blue-500/10 rounded-full blur-3xl -mr-20 -mt-20 pointer-events-none" />
              
              <div className="relative z-10">
                <div className="flex items-center gap-3 mb-8 md:mb-10">
                  <div className="w-10 h-10 md:w-12 md:h-12 rounded-2xl bg-gradient-to-br from-blue-500/20 to-purple-500/20 flex items-center justify-center border border-white/10 shrink-0">
                    <Target className="text-blue-400 w-5 h-5 md:w-6 md:h-6" />
                  </div>
                  <div>
                    <h2 className="text-xl md:text-2xl font-semibold tracking-tight leading-tight">Curadoria Inteligente</h2>
                    <p className="text-xs md:text-sm text-gray-400">Vídeos curtos baseados no seu nível</p>
                  </div>
                </div>

                <div className="space-y-6 md:space-y-8">
                  <div>
                    <div className="flex items-center justify-between mb-3 md:mb-4">
                      <h3 className="text-gray-300 font-medium text-xs md:text-sm">Tema de interesse</h3>
                    </div>
                    <div className="flex overflow-x-auto pb-2 -mb-2 gap-2 md:gap-3 hide-scrollbar snap-x">
                      {DISCOVERY_THEMES.map(theme => (
                        <button 
                          key={theme}
                          onClick={() => setSelectedTheme(theme)}
                          className={`whitespace-nowrap snap-start px-4 md:px-5 py-2.5 md:py-3 rounded-xl text-[13px] md:text-sm font-medium transition-all duration-300 ${
                            selectedTheme === theme 
                            ? 'bg-gradient-to-br from-blue-600 to-indigo-600 text-white shadow-lg shadow-blue-500/25 border border-white/10' 
                            : 'bg-white/5 text-gray-300 hover:bg-white/10 hover:text-white border border-white/5'
                          }`}
                        >
                          {theme}
                        </button>
                      ))}
                    </div>
                  </div>

                  <div>
                    <h3 className="text-gray-300 font-medium text-xs md:text-sm mb-3 md:mb-4">Nível de fluência</h3>
                    <div className="flex overflow-x-auto pb-2 -mb-2 gap-3 hide-scrollbar snap-x md:grid md:grid-cols-3">
                      {DISCOVERY_DIFFICULTIES.map(diff => (
                        <button 
                          key={diff.id}
                          onClick={() => setSelectedDifficulty(diff.id)}
                          className={`min-w-[160px] snap-start p-3 md:p-4 rounded-xl text-left border transition-all duration-300 ${
                            selectedDifficulty === diff.id 
                            ? 'bg-white/10 border-blue-400/50 shadow-inner' 
                            : 'bg-black/20 border-white/5 hover:bg-white/5 hover:border-white/20'
                          }`}
                        >
                          <div className={`font-semibold text-sm mb-1 ${selectedDifficulty === diff.id ? 'text-blue-300' : 'text-gray-200'}`}>
                            {diff.id === 'beginner' ? 'Iniciante' : diff.id === 'intermediate' ? 'Intermediário' : 'Avançado'}
                          </div>
                          <div className="text-xs text-gray-500 uppercase tracking-widest">
                            {diff.id === 'beginner' ? 'Fala mais lenta' : diff.id === 'intermediate' ? 'Ritmo natural' : 'Fala nativa'}
                          </div>
                        </button>
                      ))}
                    </div>
                  </div>
                </div>

                <button 
                  onClick={handleFindVideos}
                  disabled={!selectedTheme || !selectedDifficulty || isSearching}
                  className="w-full mt-8 md:mt-10 py-4 md:py-5 rounded-2xl bg-white text-black hover:bg-gray-100 font-bold text-base md:text-lg flex items-center justify-center gap-2 md:gap-3 transition-all duration-300 disabled:opacity-50 disabled:bg-white/20 disabled:text-white/50 active:scale-[0.98] shadow-xl shadow-white/10"
                >
                  {isSearching ? <Loader2 className="animate-spin text-gray-400 w-5 h-5 md:w-6 md:h-6" /> : <Search className="w-5 h-5 md:w-6 md:h-6" />}
                  {isSearching ? 'Buscando vídeos...' : 'Gerar Recomendações'}
                </button>

                {/* Resultados Curados */}
                {recommendations.length > 0 && (
                  <div className="mt-10 md:mt-12 animate-fade-in">
                    <h3 className="text-lg md:text-xl font-semibold mb-4 md:mb-6 flex items-center gap-2">
                       Aproveite estas sugestões <span className="text-xl md:text-2xl">✨</span>
                    </h3>
                    <div className="flex overflow-x-auto pb-4 -mb-4 gap-4 hide-scrollbar snap-x md:grid md:grid-cols-3 md:gap-5">
                      {recommendations.map(video => (
                        <div 
                          key={video.id} 
                          onClick={() => startPractice(video.id, `https://youtube.com/watch?v=${video.id}`, 0, video.title)}
                          className="min-w-[240px] md:min-w-0 snap-center shrink-0 group bg-black/40 border border-white/10 rounded-2xl overflow-hidden cursor-pointer transition-all duration-500 hover:-translate-y-2 hover:shadow-2xl hover:shadow-blue-500/20 hover:border-white/20"
                        >
                          <div className="aspect-video relative overflow-hidden bg-gray-900">
                            <img src={video.thumbnail} alt={video.title} className="w-full h-full object-cover transition-transform duration-700 group-hover:scale-110 opacity-90 group-hover:opacity-100" />
                            <div className="absolute inset-0 bg-gradient-to-t from-black/90 via-black/20 to-transparent opacity-80 group-hover:opacity-60 transition-opacity" />
                            <div className="absolute bottom-3 left-3 px-2.5 py-1 bg-white/10 backdrop-blur-md border border-white/20 text-[10px] font-bold uppercase tracking-wider rounded-md text-white">
                              {video.difficulty}
                            </div>
                          </div>
                          <div className="p-5">
                            <h4 className="font-medium text-sm leading-snug line-clamp-2 mb-2 text-gray-100 group-hover:text-blue-300 transition-colors">{video.title}</h4>
                            <p className="text-xs text-gray-500 font-medium">
                              {video.channel}
                            </p>
                          </div>
                        </div>
                      ))}
                    </div>
                  </div>
                )}
              </div>
            </div>

            {/* SEÇÃO B - COLA DIRETA */}
            <div className="md:col-span-2 relative">
               <div className="absolute inset-0 flex items-center justify-center pointer-events-none">
                 <div className="h-px w-full bg-gradient-to-r from-transparent via-white/10 to-transparent"></div>
                 <span className="absolute px-4 bg-atmosphere text-xs text-gray-500 uppercase tracking-widest font-semibold">ou</span>
               </div>
            </div>

            <div className="md:col-span-2 glass-input rounded-[2rem] p-6 md:p-8 shadow-xl">
               <div className="flex flex-col md:flex-row items-stretch md:items-center justify-between gap-4 md:gap-6">
                 <div>
                   <h2 className="text-lg md:text-xl font-medium mb-1 flex items-center gap-2">
                     <Youtube className="text-red-500 shrink-0" size={20} />
                     Já sabe o que praticar?
                   </h2>
                   <p className="text-xs md:text-sm text-gray-400">Cole o link do YouTube</p>
                 </div>
                 <div className="flex flex-col md:flex-row w-full md:w-auto relative group flex-1 max-w-xl gap-2">
                    <div className="relative w-full">
                      <div className="absolute inset-y-0 left-4 flex items-center pointer-events-none text-gray-500 group-focus-within:text-blue-400 transition-colors">
                        <Link2 size={18} />
                      </div>
                      <input
                        type="text"
                        className="w-full bg-black/40 hover:bg-black/60 focus:bg-black/60 border border-white/10 rounded-xl py-3 md:py-4 pl-12 pr-4 md:pr-24 text-sm text-gray-200 placeholder-gray-500 transition-all focus:outline-none focus:ring-1 focus:ring-blue-500/50"
                        placeholder="https://youtube.com/watch?v=..."
                        value={discoveryUrl}
                        onChange={(e) => setDiscoveryUrl(e.target.value)}
                        onKeyDown={(e) => e.key === 'Enter' && handleDirectLink()}
                      />
                      <button 
                        onClick={handleDirectLink}
                        disabled={!discoveryUrl}
                        className="hidden md:flex absolute right-2 top-2 bottom-2 px-4 rounded-xl bg-white/10 hover:bg-white/20 text-white font-medium transition-all disabled:opacity-0 text-sm items-center gap-2"
                      >
                        Abrir
                      </button>
                    </div>
                    <button 
                        onClick={handleDirectLink}
                        disabled={!discoveryUrl}
                        className="md:hidden w-full py-3 rounded-xl bg-white/10 border border-white/10 text-white transition-all disabled:opacity-50 text-[13px] font-medium"
                      >
                        Acessar Link
                    </button>
                 </div>
               </div>
            </div>

          </div>
        </main>
      </div>
    );
  }

  return (
    <div className="bg-atmosphere flex flex-col min-h-screen">
      
      {/* TOP BAR: Practice Header */}
      <header className="p-4 md:p-6 flex flex-row items-center justify-between w-full relative z-10">
        <button 
           onClick={() => setCurrentScreen('discovery')}
           className="glass-input px-4 md:px-5 py-2 md:py-2.5 rounded-full flex items-center justify-center text-gray-300 hover:text-white hover:bg-white/10 transition-colors text-sm md:text-base font-medium"
        >
          <ArrowLeft size={18} className="mr-2" /> Voltar para a Descoberta
        </button>

        {user ? (
          <button 
            onClick={handleLogout}
            className="glass-input p-2 md:px-4 md:py-2.5 rounded-full flex items-center justify-center text-gray-400 hover:text-white hover:bg-white/10 transition-colors shrink-0 text-sm"
            title={`Sair (${user.email})`}
          >
            <LogOut size={18} className="md:w-5 md:h-5 md:mr-2" />
            <span className="hidden md:inline">Sair</span>
          </button>
        ) : (
          <button 
            onClick={handleLogin}
            className="glass-input p-2 md:px-4 md:py-2.5 rounded-full flex items-center justify-center text-blue-400 hover:text-blue-300 hover:bg-white/10 transition-colors whitespace-nowrap shrink-0 text-sm"
            title="Fazer Login"
          >
            <LogIn size={18} className="md:w-5 md:h-5 md:mr-2" /> <span className="hidden md:inline font-medium">Login</span>
          </button>
        )}
      </header>

      <main className="flex-1 flex flex-col items-center justify-start w-full px-4 pt-2 pb-24 z-10">
        
        {/* YOUTUBE PLAYER CONTAINER */}
        <div className="w-full max-w-3xl aspect-video rounded-2xl overflow-hidden glass-input shadow-2xl relative ring-1 ring-white/10 group">
          <YouTube 
            videoId={videoId} 
            opts={{
              height: '100%',
              width: '100%',
              playerVars: {
                autoplay: 0,
                controls: 1, // show yt controls to ensure playability
                disablekb: 0,
                modestbranding: 1,
                rel: 0,
                origin: typeof window !== 'undefined' ? window.location.origin : undefined,
              },
            }}
            onReady={onPlayerReady}
            onError={onPlayerError}
            onPlay={() => setHasStartedPlaying(true)}
            className="absolute inset-0 w-full h-full"
          />
          {!hasStartedPlaying && phrases.length > 0 && (
            <div className="absolute inset-0 bg-black/40 flex items-center justify-center transition-opacity hover:bg-black/50 pointer-events-none">
              <div className="w-16 h-16 rounded-full bg-red-600 flex items-center justify-center text-white shadow-lg">
                <Play size={32} className="ml-1" />
              </div>
            </div>
          )}
        </div>

        {/* PHRASE STACK OR LOADING/ERROR STATES */}
        <div className="mt-6 md:mt-16 text-center max-w-3xl px-4 md:px-6 flex flex-col items-center justify-center space-y-4 md:space-y-6">
          {isLoading && (
            <div className="text-gray-400 flex flex-col items-center gap-4">
              <Loader2 size={32} className="animate-spin" />
              <p>Carregando legendas...</p>
            </div>
          )}
          
          {!isLoading && error && (
            <div className="text-red-400 bg-red-950/30 px-6 py-6 md:py-8 rounded-xl border border-red-900/50 flex flex-col items-center gap-6">
              <p className="text-center font-medium md:text-lg">{error}</p>
              
              <div className="flex flex-col sm:flex-row gap-3 w-full sm:w-auto">
                <button 
                  onClick={() => setCurrentScreen('discovery')}
                  className="px-6 py-3 bg-red-900/50 hover:bg-red-800/50 rounded-xl text-white font-medium transition-colors w-full sm:w-auto"
                >
                  Voltar e escolher outro
                </button>
                <button 
                  onClick={loadTranscript}
                  className="px-6 py-3 bg-white/10 hover:bg-white/20 rounded-xl text-white font-medium transition-colors w-full sm:w-auto"
                >
                  Tentar de novo
                </button>
              </div>

              <div className="w-full mt-4 flex flex-col items-center pt-6 border-t border-red-900/40">
                 <p className="text-sm text-gray-300 mb-4 text-center">
                    YouTube bloqueou o acesso automático à legenda.<br />
                    Para resolver isso, você pode <strong>enviar o arquivo</strong> (.srt/.vtt) <strong>OU colar o texto</strong> da transcrição diretamente do YouTube:
                 </p>
                 
                 <div className="w-full max-w-xl flex flex-col gap-4">
                   <textarea
                     className="w-full h-32 bg-black/40 border border-white/10 rounded-xl p-4 text-sm text-gray-200 placeholder-gray-500 focus:outline-none focus:ring-2 focus:ring-blue-500/50 resize-y"
                     placeholder="Exemplo de como copiar e colar do YouTube:&#10;0:00&#10;Olá pessoal...&#10;0:02&#10;Bem-vindos ao vídeo..."
                     onChange={async (e) => {
                        const text = e.target.value;
                        if (text.length > 20 && text.match(/\d+:\d+/)) {
                           // Try to parse it!
                           setIsLoading(true);
                           setError(null);
                           try {
                              const transcriptData = parseSrt(text).slice(0, 50);
                              if (transcriptData.length === 0) throw new Error("Texto colado não tem formato de tempo válido.");
                              
                              const res = await fetch("/api/enrichManualTranscript", {
                                method: "POST",
                                headers: { "Content-Type": "application/json" },
                                body: JSON.stringify({ transcriptData }),
                              });
                              
                              if (!res.ok) {
                                const errData = await res.json();
                                throw new Error(errData.error || "Failed to process manual transcript");
                              }
                              
                              const data = await res.json();
                              setPhrases(data);
                           } catch (err: any) {
                              setError(`Erro no texto: ${err.message}`);
                           } finally {
                              setIsLoading(false);
                           }
                        }
                     }}
                   />
                   
                   <div className="flex items-center gap-4 my-2">
                     <div className="h-px bg-white/10 flex-1"></div>
                     <span className="text-xs text-gray-500 uppercase font-semibold">Ou</span>
                     <div className="h-px bg-white/10 flex-1"></div>
                   </div>

                   <label className="cursor-pointer px-6 py-3 bg-blue-600 hover:bg-blue-500 rounded-xl text-white font-medium transition-colors w-full text-center">
                      Upload Arquivo .srt / .vtt
                      <input 
                        type="file" 
                        accept=".srt,.vtt" 
                        className="hidden" 
                        onChange={async (e) => {
                           const file = e.target.files?.[0];
                           if (file) {
                              setIsLoading(true);
                              setError(null);
                              try {
                                 const text = await file.text();
                                 const transcriptData = parseSrt(text).slice(0, 50); // Take first 50 lines just to not overwhelm
                                 if (transcriptData.length === 0) throw new Error("Não foi possível ler as legendas no arquivo.");
                                 
                                 const res = await fetch("/api/enrichManualTranscript", {
                                   method: "POST",
                                   headers: { "Content-Type": "application/json" },
                                   body: JSON.stringify({ transcriptData }),
                                 });
                                 
                                 if (!res.ok) {
                                   const errData = await res.json();
                                   throw new Error(errData.error || "Failed to process manual transcript");
                                 }
                                 
                                 const data = await res.json();
                                 setPhrases(data);
                              } catch (err: any) {
                                 setError(`Erro no arquivo: ${err.message}`);
                              } finally {
                                 setIsLoading(false);
                              }
                           }
                        }}
                      />
                   </label>
                 </div>
              </div>
            </div>
          )}
          
          {!isLoading && !error && phrases.length === 0 && (
            <div className="text-gray-500 italic">
              Preparando vídeo...
            </div>
          )}

          {!isLoading && activePhrase && (
            <>
              {/* Original Phrase */}
              <div className="font-serif text-2xl md:text-5xl lg:text-5xl font-semibold leading-tight tracking-tight text-white drop-shadow-md flex flex-wrap justify-center gap-x-1.5 gap-y-2 md:gap-x-3 md:gap-y-4">
                {!feedback && !isAnalyzing ? (
                  activePhrase.text.split(/\s+/).map((word, idx) => (
                    <span key={idx} className="px-1 md:px-2 py-0.5 md:py-1 rounded-lg transition-all">{word}</span>
                  ))
                ) : isAnalyzing ? (
                  activePhrase.text.split(/\s+/).map((word, idx) => (
                    <span key={idx} className="animate-pulse bg-white/10 rounded-lg px-2 md:px-3 py-0.5 md:py-1 text-white">
                      {word}
                    </span>
                  ))
                ) : (
                  feedback?.words.map((w, idx) => (
                    <div key={idx} className="relative group flex items-center justify-center">
                      <span className={`px-2 py-0.5 md:px-3 md:py-1 rounded-lg border-2 transition-all duration-300 ${w.correct ? 'cursor-default' : 'cursor-pointer'} ${
                        w.correct 
                          ? 'border-green-500 bg-green-50 text-green-700' 
                          : 'border-red-500 bg-red-50 text-red-700'
                      }`}>
                        {w.word}
                      </span>
                      {!w.correct && w.tip && (
                        <div className="absolute opacity-0 group-hover:opacity-100 transition-all duration-200 bottom-full mb-3 bg-gray-900 border border-gray-700 text-white text-xs md:text-sm rounded-lg p-3 w-48 md:w-64 z-50 shadow-xl pointer-events-none transform -translate-x-1/2 left-1/2">
                           <div className="absolute -bottom-2 left-1/2 transform -translate-x-1/2 w-0 h-0 border-l-8 border-r-8 border-t-8 border-transparent border-t-gray-900"></div>
                           {w.tip}
                        </div>
                      )}
                    </div>
                  ))
                )}
              </div>
              
              {/* Score Display (if feedback exists) */}
              {feedback && (
                 <div className="mt-4 flex items-center gap-2">
                   <div className="text-sm uppercase tracking-widest text-gray-400">Score de Pronúncia:</div>
                   <div className={`font-mono text-xl font-bold ${feedback.score >= 80 ? 'text-green-400' : feedback.score >= 50 ? 'text-yellow-400' : 'text-red-400'}`}>
                     {feedback.score}%
                   </div>
                 </div>
              )}
              
              {/* Phonetic Transcription */}
              {activePhrase.phonetic && (
                <p className="font-mono text-base md:text-xl italic text-blue-300 opacity-80 tracking-wide font-light">
                  {activePhrase.phonetic}
                </p>
              )}
              
              {/* Translation */}
              {activePhrase.translation && (
                <p className="text-gray-400 uppercase tracking-[0.2em] text-xs md:text-sm font-semibold mt-4">
                  {activePhrase.translation}
                </p>
              )}

              {/* Status or Recording URL */}
              {recordingUrl && (
                <div className="mt-8 animate-fade-in flex flex-col items-center">
                  <span className="text-green-400 text-sm mb-2 opacity-80">Gravação finalizada! Pronto para análise.</span>
                  <audio src={recordingUrl} controls className="h-10 opacity-70 hover:opacity-100 transition-opacity" />
                </div>
              )}
            </>
          )}
        </div>
      </main>

      {/* BOTTOM CONTROLS */}
      <footer className="fixed bottom-0 left-0 w-full pb-6 md:pb-10 pt-6 bg-gradient-to-t from-black/95 md:from-black/80 to-transparent flex justify-center items-center gap-3 sm:gap-6 md:gap-8 z-20 px-2 sm:px-4">
        
        <button 
          onClick={() => setIsLoopActive(!isLoopActive)}
          className={`p-2 md:p-3 rounded-full transition-all duration-300 ${
            isLoopActive ? 'text-blue-400 bg-blue-400/10' : 'text-gray-500 hover:text-gray-300'
          }`}
          title="Loop da Frase"
        >
          <Repeat size={20} className="md:w-6 md:h-6" />
        </button>

        <button 
          onClick={handlePrev}
          disabled={activePhraseIndex === 0 || phrases.length === 0}
          className="p-2 md:p-4 rounded-full text-white hover:bg-white/10 disabled:opacity-30 disabled:hover:bg-transparent transition-all"
        >
          <SkipBack size={24} className="md:w-7 md:h-7" />
        </button>

        <button 
          onClick={toggleRecording}
          disabled={phrases.length === 0}
          className={`w-16 h-16 md:w-24 md:h-24 shrink-0 rounded-full flex items-center justify-center text-white transition-all duration-300 disabled:opacity-50 disabled:grayscale ${
            isRecording 
              ? 'bg-red-500 mic-pulse scale-105' 
              : 'bg-white/10 hover:bg-white/20 border border-white/20'
          }`}
        >
          <Mic size={28} className={`md:w-10 md:h-10 ${isRecording ? 'opacity-100' : 'opacity-80'}`} />
        </button>

        <button 
          onClick={handleNext}
          disabled={phrases.length === 0 || activePhraseIndex === phrases.length - 1}
          className="p-2 md:p-4 rounded-full text-white hover:bg-white/10 disabled:opacity-30 disabled:hover:bg-transparent transition-all"
        >
          <SkipForward size={24} className="md:w-7 md:h-7" />
        </button>

        <button 
          onClick={toggleGlobalPlay}
          disabled={phrases.length === 0}
          className="p-2 md:p-3 rounded-full text-gray-300 hover:text-white hover:bg-white/10 disabled:opacity-50 transition-all"
          title="Play/Pause Video"
        >
          <Play size={20} className="md:w-6 md:h-6" />
        </button>
      </footer>
    </div>
  );
}
