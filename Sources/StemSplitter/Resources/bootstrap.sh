#!/bin/sh
# Skapar en virtuell Python-miljo och installerar Demucs (CPU) i den.
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
"$PYTHON_BIN" -m venv "$VENV_DIR"

PIP="$VENV_DIR/bin/pip"
"$PIP" install --upgrade pip setuptools wheel
# CPU-only torch håller nedladdningen betydligt mindre.
# torch 2.5.1 ar senaste versionen med cp39-wheel for macOS (CLT:s python3 ar 3.9).
"$PIP" install --index-url https://download.pytorch.org/whl/cpu "torch==2.5.1"
"$PIP" install "demucs==4.0.1"

"$VENV_DIR/bin/demucs" --version
