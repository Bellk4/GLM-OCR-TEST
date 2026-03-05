@echo off
setlocal

rem -----------------------------------------------------------------------------
rem GLM-OCR local server launcher (Windows, venv)
rem - Creates/uses .venv next to this script
rem - Installs runtime deps on first run, skips on subsequent runs
rem - Pass --update to force reinstall of all dependencies
rem - Starts FastAPI on configured host/port
rem -----------------------------------------------------------------------------

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "VENV_DIR=%SCRIPT_DIR%\.venv"
set "STAMP_FILE=%VENV_DIR%\.deps_ok"
set "ENV_FILE=%SCRIPT_DIR%\.env"

if exist "%ENV_FILE%" (
    echo [+] Loading .env from "%ENV_FILE%"
    for /f "usebackq eol=# tokens=1* delims==" %%A in ("%ENV_FILE%") do (
        if not "%%A"=="" if not "%%A"=="." (
            set "%%A=%%B"
        )
    )
)

rem Resolve model/cache directory from .env when provided.
if "%MODEL_CACHE_DIR%"=="" if not "%GLM_MODEL_CACHE%"=="" set "MODEL_CACHE_DIR=%GLM_MODEL_CACHE%"
if "%MODEL_CACHE_DIR%"=="" set "MODEL_CACHE_DIR=%SCRIPT_DIR%\models\hf_cache"

rem Make relative paths in .env behave consistently from project root.
if not "%MODEL_CACHE_DIR:~1,1%"==":" if not "%MODEL_CACHE_DIR:~0,2%"=="\\" if not "%MODEL_CACHE_DIR:~0,1%"=="/" set "MODEL_CACHE_DIR=%SCRIPT_DIR%\%MODEL_CACHE_DIR%"

if not exist "%MODEL_CACHE_DIR%" mkdir "%MODEL_CACHE_DIR%"

if "%HF_HOME%"=="" set "HF_HOME=%SCRIPT_DIR%\models\hf_home"
if "%HF_HUB_CACHE%"=="" set "HF_HUB_CACHE=%MODEL_CACHE_DIR%"
if "%TRANSFORMERS_CACHE%"=="" set "TRANSFORMERS_CACHE=%MODEL_CACHE_DIR%"
if "%GLM_MODEL_CACHE%"=="" set "GLM_MODEL_CACHE=%MODEL_CACHE_DIR%"
if "%TORCH_CHANNEL%"=="" set "TORCH_CHANNEL=cu126"

rem Note: Do not force HF_HUB_OFFLINE here.
rem Multiple model switching may require downloading a different model.

rem Create venv if missing
if not exist "%VENV_DIR%\Scripts\activate.bat" (
    echo [+] Creating virtual environment at "%VENV_DIR%" ...
    python -m venv "%VENV_DIR%"
    if errorlevel 1 (
        echo [!] Failed to create virtual environment.
        exit /b 1
    )
    goto :install_deps
)

rem --update flag: reinstall
if /I "%~1"=="--update" goto :install_deps

rem Skip install if stamp file exists
if exist "%STAMP_FILE%" goto :activate
goto :install_deps

:install_deps
call "%VENV_DIR%\Scripts\activate.bat"
if errorlevel 1 (
    echo [!] Failed to activate virtual environment.
    exit /b 1
)

echo [+] Installing/ensuring dependencies...
python -m pip install --upgrade pip

echo [+] Installing PyTorch (%TORCH_CHANNEL%)...
if /I "%TORCH_CHANNEL%"=="cpu" (
    python -m pip install --upgrade --index-url https://download.pytorch.org/whl/cpu torch torchvision
) else (
    python -m pip install --upgrade --index-url https://download.pytorch.org/whl/%TORCH_CHANNEL% torch torchvision
)
python -c "import torch; print('[torch]', torch.__version__, 'cuda=', torch.version.cuda, 'available=', torch.cuda.is_available())"

echo [+] Installing FastAPI and image/PDF dependencies...
python -m pip install fastapi uvicorn python-multipart pillow pypdfium2 accelerate

echo [+] Installing optional layout dependencies (PaddleOCR)...
python -m pip install --upgrade paddlepaddle
if errorlevel 1 echo [!] paddlepaddle install failed. Layout OCR will use fallback mode.
python -m pip install --upgrade paddleocr
if errorlevel 1 echo [!] paddleocr install failed. Layout OCR will use fallback mode.

echo [+] Installing transformers (development build)...
python -m pip install git+https://github.com/huggingface/transformers.git
if errorlevel 1 (
    echo [!] Dependency installation failed.
) else (
    break > "%STAMP_FILE%"
    echo [+] Dependencies installed successfully.
)
goto :start_server

:activate
call "%VENV_DIR%\Scripts\activate.bat"
if errorlevel 1 (
    echo [!] Failed to activate virtual environment.
    exit /b 1
)
echo [+] Dependencies already installed. Use --update to reinstall.

:start_server
if "%HOST%"=="" set "HOST=0.0.0.0"
if "%PORT%"=="" set "PORT=8000"

echo [+] Starting server at http://%HOST%:%PORT%
uvicorn app.main:app --host "%HOST%" --port "%PORT%"

endlocal
