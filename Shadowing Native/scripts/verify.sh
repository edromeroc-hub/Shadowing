#!/bin/zsh
# Verificação única do projeto. Rode ao fim de cada tarefa:
#   scripts/verify.sh          tudo (testes do curador, auditorias Swift/JS e build do app)
#   scripts/verify.sh --quick  sem o build do Xcode
# Não usa rede nem credenciais: as auditorias usam respostas simuladas.
set -uo pipefail
NATIVE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/shadowing-verify.XXXXXX")"
cd "$NATIVE_ROOT"

failures=0
step() {
  local name="$1"; shift
  local log="$LOG_DIR/${name// /-}.log"
  if "$@" > "$log" 2>&1; then
    print "PASS  $name"
  else
    print "FAIL  $name  (log: $log)"
    tail -25 "$log" | sed 's/^/      /'
    failures=$((failures + 1))
  fi
}

step "curator npm test" zsh -c 'cd curator && npm test'
step "curadoria-gemini npm test" zsh -c 'cd curadoria-gemini && npm test'
step "recommendation audit" zsh Audits/run-recommendations.zsh
step "segmentation audit" zsh Audits/run-segmentation-layout.zsh
step "playback boundary audit" node Audits/PlaybackBoundaryAudit.js
for runner in Audits/run-*.zsh; do
  case "$runner" in
    Audits/run-recommendations.zsh|Audits/run-segmentation-layout.zsh) ;;
    *) step "$(basename "$runner" .zsh)" zsh "$runner" ;;
  esac
done

if [[ "${1:-}" != "--quick" ]]; then
  step "xcodebuild simulator" xcodebuild -project ShadowingNative.xcodeproj -scheme ShadowingNative \
    -destination 'generic/platform=iOS Simulator' -configuration Debug build CODE_SIGNING_ALLOWED=NO
fi

if (( failures > 0 )); then
  print "\n$failures etapa(s) falharam."
  exit 1
fi
rm -rf "$LOG_DIR"
print "\nTudo passou."
