import React, { type ErrorInfo, type ReactNode } from 'react';

type AppErrorBoundaryState = {
  hasError: boolean;
  message: string;
};

export default class AppErrorBoundary extends React.Component<{ children: ReactNode }, AppErrorBoundaryState> {
  declare props: Readonly<{ children: ReactNode }>;
  state: AppErrorBoundaryState = { hasError: false, message: '' };

  static getDerivedStateFromError(error: Error): AppErrorBoundaryState {
    return { hasError: true, message: error.message || 'Erro inesperado na interface.' };
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    console.error('[app:error-boundary]', error, info.componentStack);
  }

  render() {
    if (!this.state.hasError) return this.props.children;

    return (
      <main className="min-h-screen bg-[#050505] text-white flex items-center justify-center px-6">
        <section className="w-full max-w-md rounded-3xl border border-white/10 bg-white/5 p-8 text-center shadow-2xl">
          <h1 className="text-2xl font-semibold">O app encontrou um erro</h1>
          <p className="mt-3 text-sm text-gray-400">
            Seu download continua salvo. Recarregue somente a interface para voltar.
          </p>
          <p className="mt-4 rounded-xl bg-black/30 p-3 text-xs text-red-300">{this.state.message}</p>
          <button
            type="button"
            onClick={() => window.location.reload()}
            className="mt-6 w-full rounded-xl bg-white px-5 py-3 font-semibold text-black hover:bg-gray-100"
          >
            Recarregar o app
          </button>
        </section>
      </main>
    );
  }
}
