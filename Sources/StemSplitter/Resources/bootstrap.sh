#!/bin/sh
# Skapar en virtuell Python-miljo och installerar Demucs (CPU) i den.
# Anropas av StemSplitter-appen med: sh bootstrap.sh <venv-katalog>
set -e
trap 'echo "BOOTSTRAP-FEL rad $LINENO (exit $?)"' ERR

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
"$PIP" install --index-url https://download.pytorch.org/whl/cpu torch
"$PIP" install demucs

"$VENV_DIR/bin/demucs" --version
