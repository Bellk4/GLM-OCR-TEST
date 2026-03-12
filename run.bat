@echo off
setlocal

rem -----------------------------------------------------------------------------
rem GLM-OCR ローカルサーバー起動スクリプト (Windows, venv)
rem - このスクリプトと同じ場所の .venv を作成/利用
rem - 初回は実行時依存をインストールし、2回目以降はスキップ
rem - --update を付けると依存関係を強制再インストール
rem - 指定された host/port で FastAPI を起動
rem
rem CLIパラメータ:
rem   --update                      依存関係を強制的に再インストール
rem   --torch-channel=<channel>     PyTorchのインデックスチャネルを指定　（例: cpu, cu118, cu121, cu126）
rem   --help                        ヘルプを表示して終了
rem -----------------------------------------------------------------------------

rem スクリプトのあるディレクトリを取得
set "SCRIPT_DIR=%~dp0"

rem バックスラッシュで終わるパスを正規化する (例: C:\path\to\project\ -> C:\path\to\project)
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

rem 例: O:\source\Python\GLM-OCR-TEST\run.bat -> O:\source\Python\GLM-OCR-TEST
set "VENV_DIR=%SCRIPT_DIR%\.venv"\

rem 依存関係インストールのスタンプファイル
set "STAMP_FILE=%VENV_DIR%\.deps_ok"

rem 既定ではプロジェクトルートの env または .env を探す。
set "ENV_FILE=%SCRIPT_DIR%\.env" 

rem 任意引数: --torch-channel=<cpu|cu118|cu121|cu126...>
set "CLI_TORCH_CHANNEL="
set "CLI_FORCE_UPDATE=0"
set "CLI_SHOW_HELP=0"
for %%I in (%*) do (
    set "ARG=%%~I"
    call :parse_arg
)

rem ヘルプ表示
if "%CLI_SHOW_HELP%"=="1" goto :print_help

if not "%ENV_FILE%"=="" if exist "%ENV_FILE%" (
    echo [+] Loading env from "%ENV_FILE%"
    for /f "usebackq eol=# tokens=1* delims==" %%A in ("%ENV_FILE%") do (
        if not "%%A"=="" if not "%%A"=="." (
            set "%%A=%%B"
        )
    )
)
if "%ENV_FILE%"=="" (
    echo [!] No env file found. Expected "%ENV_FILE_PLAIN%" or "%ENV_FILE_DOT%".
)

rem envで指定されている場合は、モデル/キャッシュディレクトリをそこから解決する。
if "%MODEL_CACHE_DIR%"=="" if not "%GLM_MODEL_CACHE%"=="" set "MODEL_CACHE_DIR=%GLM_MODEL_CACHE%"
if "%MODEL_CACHE_DIR%"=="" set "MODEL_CACHE_DIR=%SCRIPT_DIR%\models\hf_cache"

rem env 内の相対パスをプロジェクトルート基準に正規化する。
if not "%MODEL_CACHE_DIR:~1,1%"==":" if not "%MODEL_CACHE_DIR:~0,2%"=="\\" if not "%MODEL_CACHE_DIR:~0,1%"=="/" set "MODEL_CACHE_DIR=%SCRIPT_DIR%\%MODEL_CACHE_DIR%"

if not exist "%MODEL_CACHE_DIR%" mkdir "%MODEL_CACHE_DIR%"

if "%HF_HOME%"=="" set "HF_HOME=%SCRIPT_DIR%\models\hf_home"
if "%HF_HUB_CACHE%"=="" set "HF_HUB_CACHE=%MODEL_CACHE_DIR%"
if "%TRANSFORMERS_CACHE%"=="" set "TRANSFORMERS_CACHE=%MODEL_CACHE_DIR%"
if "%GLM_MODEL_CACHE%"=="" set "GLM_MODEL_CACHE=%MODEL_CACHE_DIR%"
if not "%CLI_TORCH_CHANNEL%"=="" set "TORCH_CHANNEL=%CLI_TORCH_CHANNEL%"
if "%TORCH_CHANNEL%"=="" set "TORCH_CHANNEL=cu126"
set "TORCH_MARKER_FILE=%VENV_DIR%\.torch_channel"

rem 注意: ここで HF_HUB_OFFLINE を強制しない。
rem 複数モデル切り替え時に別モデルのダウンロードが必要になる可能性がある。

rem 仮想環境がなければ作成する。
if not exist "%VENV_DIR%\Scripts\activate.bat" (
    echo [+] Creating virtual environment at "%VENV_DIR%" ...
    python -m venv "%VENV_DIR%"
    if errorlevel 1 (
        echo [!] Failed to create virtual environment.
        exit /b 1
    )
    goto :install_deps
)

rem --update が指定されていれば再インストールする。
if "%CLI_FORCE_UPDATE%"=="1" goto :install_deps

rem 前回インストール時の TORCH_CHANNEL と異なる場合は再インストールする。
if exist "%TORCH_MARKER_FILE%" (
    set /p INSTALLED_TORCH_CHANNEL=<"%TORCH_MARKER_FILE%"
    if /I not "%INSTALLED_TORCH_CHANNEL%"=="%TORCH_CHANNEL%" goto :install_deps
)

rem スタンプファイルがある場合はインストールをスキップする。
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

rem CPU版は専用のインデックスURLからインストールする必要がある。
rem GPU版はチャネルに応じたURLからインストールする。例: cu118 -> https://download.pytorch.org/whl/cu118
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
@REM python -m pip install git+https://github.com/huggingface/transformers.git
python -m pip install transformers

if errorlevel 1 (
    echo [!] Dependency installation failed.
) else (
    break > "%STAMP_FILE%"
    > "%TORCH_MARKER_FILE%" echo %TORCH_CHANNEL%
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
goto :eof

:parse_arg
if /I "%ARG:~0,16%"=="--torch-channel=" set "CLI_TORCH_CHANNEL=%ARG:~16%"
if /I "%ARG%"=="--update" set "CLI_FORCE_UPDATE=1"
if /I "%ARG%"=="--help" set "CLI_SHOW_HELP=1"
exit /b 0

:print_help
echo 使い方: run.bat [オプション]
echo.
echo オプション:
echo   --update
echo     .venv が準備済みでも依存関係を強制的に再インストールします。
echo.
echo   --torch-channel=^<channel^>
echo     PyTorch wheel のチャネルを指定します。
echo     例: cpu, cu118, cu121, cu126
echo.
echo   --help
echo     このヘルプを表示して終了します。
echo.
echo 主な環境変数:
echo   ENV_FILE          明示的に env ファイルのパスを指定します。未指定時はプロジェクト直下の ^"env^" または ^".env^" を利用します。
echo   MODEL_CACHE_DIR   モデルキャッシュの保存先ディレクトリです。
echo   GLM_MODEL_CACHE   MODEL_CACHE_DIR が空の場合の参照元エイリアスです。
echo   TORCH_CHANNEL     --torch-channel 未指定時に使う既定チャネルです。
echo   HOST              Uvicorn のホストです。既定: 0.0.0.0
echo   PORT              Uvicorn のポートです。既定: 8000
endlocal
exit /b 0
