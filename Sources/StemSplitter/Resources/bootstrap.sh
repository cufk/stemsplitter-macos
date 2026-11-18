#!/bin/sh
# Skapar en virtuell Python-miljo och installerar Demucs i den.
# Anropas av StemSplitter-appen med: sh bootstrap.sh <venv-katalog>
set -e
trap 'echo "BOOTSTRAP-FEL rad $LINENO kommando ovan (exit $?)"' ERR

VENV_DIR="$1"
if [ -z "$VENV_DIR" ]; then
    echo "anvandning: bootstrap.sh <venv-katalog>" >&2
    exit 2
fi

PYTHON_BIN="${PYTHON_BIN:-$(command -v python3 || echo /usr/bin/python3)}"
echo "Anvander Python: $PYTHON_BIN ($("$PYTHON_BIN" --version 2>&1))"
# --clear: en tidigare halvfardig miljo (t.ex. fran en annan Python-version) byggs om
"$PYTHON_BIN" -m venv --clear "$VENV_DIR"

PIP="$VENV_DIR/bin/pip"
"$PIP" install --upgrade pip setuptools wheel
"$PIP" install "demucs==4.0.1"

# Arkitekturen avgors av Python-tolken (en x86_64-Python kan kora under Rosetta pa Apple Silicon).
ARCH="$("$VENV_DIR/bin/python" -c 'import platform; print(platform.machine())')"
echo "Python-arkitektur: $ARCH"
if [ "$ARCH" = "arm64" ]; then
    # torch >= 2.6 bryter demucs modell-laddning (weights_only default);
    # 2.5.1 har hjul for Python 3.9-3.12 pa Apple Silicon (med MPS-stod).
    "$PIP" install --index-url https://download.pytorch.org/whl/cpu "torch==2.5.1" "torchaudio==2.5.1"
else
    # PyTorch slutade bygga macOS x86_64-hjul efter 2.2.x (Intel-Mac).
    "$PIP" install "torch==2.2.2" "torchaudio==2.2.2" "numpy<2"
fi
# torchaudio behover soundfile/libsndfile for att lasa WAV utan ffmpeg
"$PIP" install soundfile

"$VENV_DIR/bin/python" -c "import demucs, torch; print('demucs', demucs.__version__, '| torch', torch.__version__)"
