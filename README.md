# GLM-OCR Server

`zai-org/GLM-OCR` を使ったローカルOCRサーバーです。  
FastAPI + シンプルなWeb UIで、画像/PDFをページ単位でOCRできます。

![GLM-OCR UI](image.jpg)

## 主な機能

- GLM-OCR推論（`text` / `table` / `formula` / `extract_json`）
- PDF入力（`pypdfium2` でページを画像化してOCR）
- 進捗表示（`事前処理中` -> `i/nページをOCR中`）
- 実行中断（中断API + UIボタン）
- 改行後処理モード（`none` / `paragraph` / `compact`）
- ページ表示切替（ドロップダウン + `ALL`合算表示）
- 表示中結果のコピー（`raw` はコピー対象外）
- モデル/キャッシュはプロジェクト配下に保存

## 動作環境

- Python 3.10+
- Windows または Linux/macOS
- CUDA使用時は対応GPU + ドライバ

## クイックスタート

### Windows

```bat
run.bat
```

### Linux / macOS

```bash
chmod +x run.sh
./run.sh
```

起動後:

- UI: `http://localhost:8000/`
- API Docs: `http://localhost:8000/docs`

## 設定

### `.env` ファイル

プロジェクト直下に `.env` を置くと、`run.sh` / `run.bat` 起動時に読み込みます。  
詳細は [インストールオプション](#インストールオプション) を参照してください。

## モデル保存先

モデルキャッシュはプロジェクト内に保存されます。

- `models/hf_cache` デフォルト
- `models/hf_home`　デフォルト

環境変数 `GLM_MODEL_CACHE` で明示可能です。

## RunPod Pod

Pod 用の Dockerfile は `docker/Dockerfile` に置いています。

### ビルド

ビルドコンテキストはリポジトリルート (`.`) のままにしてください。

```bash
docker build -f docker/Dockerfile --build-arg TORCH_CHANNEL=cu126 -t bellk4/glm-ocr-pod:20260310-1 .
```

### プッシュ

```bash
docker push bellk4/glm-ocr-pod:20260310-1
```

### Pod 推奨環境変数

```env
GLM_MODEL_CACHE=/runpod-volume/hf_cache
HF_HUB_CACHE=/runpod-volume/hf_cache
TRANSFORMERS_CACHE=/runpod-volume/hf_cache
HF_HOME=/runpod-volume/hf_home
HOST=0.0.0.0
PORT=8000
```

### Pod 起動後の利用先

- ブラウザUI: `http://<pod-ip>:8000/`
- API Docs: `http://<pod-ip>:8000/docs`
- 外部アプリ連携: `POST http://<pod-ip>:8000/api/analyze`

### 外部アプリからのリクエスト例

`curl`:

```bash
curl -X POST "http://<pod-ip>:8000/api/analyze" \
  -F "file=@sample.pdf" \
  -F "task=text" \
  -F "device=auto"
```

Python:

```python
import requests

url = "http://<pod-ip>:8000/api/analyze"
with open("sample.pdf", "rb") as f:
    resp = requests.post(
        url,
        files={"file": ("sample.pdf", f, "application/pdf")},
        data={"task": "text", "device": "auto"},
        timeout=600,
    )

resp.raise_for_status()
print(resp.json())
```

## API

### `GET /api/status`

CUDA可否や現在モデル、利用可能モデル一覧、キャッシュディレクトリを返します。

**レスポンス例:**

```json
{
  "cuda_available": false,
  "device_default": "cpu",
  "model": "zai-org/GLM-OCR",
  "model_default": "zai-org/GLM-OCR",
  "models": ["zai-org/GLM-OCR", "zai-org/GLM-OCR-xxx"],
  "model_cache_dir": "O:\\...\\models\\hf_cache"
}
```

---

### `POST /api/analyze`

マルチパートフォームでOCR実行。

#### フォーム入力項目

| パラメータ | 型 | 既定値 | 許容値 | 説明 |
|---|---|---|---|---|
| `file` | file | **必須** | 画像 / PDF | OCR対象ファイル。JPEG・PNG・BMP・TIFF・WebP・PDFに対応 |
| `device` | string | `auto` | `auto` `cuda` `cpu` | 推論デバイス。`auto` はGPUが使えればCUDA、なければCPUを選択 |
| `model_id` | string | `GLM_MODEL_ID` | `GLM_MODEL_IDS` に含まれる値 | 推論に使うモデルID。リクエストごとに切り替え可能 |
| `dpi` | int | `220` | `36` ～ `600` | PDFのスキャン解像度。高いほど精細だが処理が遅くなる |
| `task` | string | `text` | `text` `table` `formula` `extract_json` | OCRタスク種別（後述） |
| `linebreak_mode` | string | `none` | `none` `paragraph` `compact` | 改行の後処理方式（後述） |
| `schema` | string | なし | 任意のJSON文字列 | `task=extract_json` のときのみ必須。出力するJSONスキーマを記述 |
| `instruction` | string | なし | 任意テキスト | モデルへの追加指示。例: 「このPDFは設計図です。寸法と部材名を優先して抽出してください」 |
| `max_new_tokens` | int | `1024` | `1` ～ `32768` | 生成トークンの上限。長い文書では増やす |
| `temperature` | float | `0.0` | `0.0` ～ | サンプリング温度。`0.0` で決定論的（greedy）、正の値でランダム性が増す |
| `use_layout` | bool | `false` | `true` `false` | レイアウト解析モード。ページを領域に分割してから各領域をOCRする |
| `layout_backend` | string | `ppdoclayoutv3` | `ppdoclayoutv3` `none` | レイアウト解析エンジン。`none` は全ページを1領域として扱う |
| `reading_order` | string | `auto` | `auto` `ltr_ttb` `rtl_ttb` `vertical_rl` | 領域の読み取り順序（後述） |
| `region_padding` | int | `12` | `0` ～ `256` | 各領域の切り抜き時に追加する余白（px） |
| `max_regions` | int | `200` | `1` ～ `1000` | 1ページあたりの最大処理領域数 |
| `region_parallelism` | int | `1` | `1` ～ `8` | 同時並列処理する領域数 |
| `request_id` | string | 自動UUID | 任意 | 進捗・中断APIで使うID。省略時はサーバーが自動生成 |

#### `task` の詳細

| 値 | 説明 | 出力形式 |
|---|---|---|
| `text` | 通常の文字認識 | プレーンテキスト |
| `table` | 表の認識 | Markdown テーブル形式 |
| `formula` | 数式の認識 | LaTeX 形式 |
| `extract_json` | `schema` に従ったJSON抽出 | JSON文字列 |

#### `linebreak_mode` の詳細

| 値 | 説明 |
|---|---|
| `none` | モデル出力の改行をそのまま返す |
| `paragraph` | 段落末と判定できない改行を結合し、ソフトワードラップを除去する |
| `compact` | すべての改行を除去して1行にまとめる |

#### `reading_order` の詳細

| 値 | 説明 |
|---|---|
| `auto` | ページ内の領域の配置から自動判定（縦書き・多段など） |
| `ltr_ttb` | 左→右・上→下（欧文横書き） |
| `rtl_ttb` | 右→左・上→下（日本語多段横書きなど） |
| `vertical_rl` | 右→左の列順、列内は上→下（縦書き） |

#### レスポンス例

```json
{
  "request_id": "abc123",
  "device": "cpu",
  "model": "zai-org/GLM-OCR",
  "task": "text",
  "linebreak_mode": "none",
  "use_layout": false,
  "state": "done",
  "page_count": 2,
  "results": [
    {
      "page": 1,
      "text": "認識されたテキスト",
      "raw": "<special_tokens_included_output>",
      "truncated": false
    },
    {
      "page": 2,
      "text": "2ページ目のテキスト",
      "raw": "...",
      "truncated": false
    }
  ]
}
```

`state` は `done` / `canceled` / `error` のいずれか。  
`truncated` が `true` の場合、`max_new_tokens` に達して出力が途中で打ち切られています。

---

### `GET /api/progress/{request_id}`

進捗状態を取得します。

**レスポンス例:**

```json
{
  "request_id": "abc123",
  "state": "ocr",
  "message": "1/3ページのOCR中",
  "current_page": 1,
  "total_pages": 3,
  "current_region": 0,
  "total_regions": 0,
  "updated_at": 1741234567.89
}
```

`state` の遷移: `preprocessing` → `ocr` → `done` / `canceled` / `error`

---

### `POST /api/cancel/{request_id}`

中断要求を送信します。  
生成中はトークン生成ステップ単位で停止判定します。

---

## インストールオプション

### `run.bat` / `run.sh` のフラグ

| フラグ | 説明 |
|---|---|
| _(なし)_ | 初回はインストールを実行し、2回目以降はスキップして即起動 |
| `--update` | インストール済みでも全パッケージを再インストールする |

**例:**

```bat
run.bat --update
```

### `.env` 設定項目

プロジェクト直下に `.env` ファイルを置くと起動時に自動で読み込まれます。

| 変数 | 既定値 | 説明 |
|---|---|---|
| `HOST` | `0.0.0.0` | サーバーのバインドアドレス |
| `PORT` | `8000` | リッスンポート |
| `TORCH_CHANNEL` | `cu126` | PyTorchのインストール元チャネル。`cpu` / `cu118` / `cu121` / `cu126` など |
| `GLM_MODEL_ID` | `zai-org/GLM-OCR` | 使用するモデルのHuggingFace ID。GLM-OCR互換モデルであれば変更可能 |
| `GLM_MODEL_IDS` | `GLM_MODEL_ID` と同値 | UI/APIで選択可能にするモデルID一覧（カンマ区切り） |
| `GLM_DEFAULT_INSTRUCTION` | なし | 追加指示が未指定のときに自動適用する既定指示 |
| `MODEL_CACHE_DIR` | `models/hf_cache` | モデルキャッシュ保存先。`run.bat`/`run.sh` で解決され、`GLM_MODEL_CACHE` に反映 |
| `GLM_MODEL_CACHE` | `models/hf_cache` | アプリ側が参照するモデルキャッシュ保存先 |
| `HF_TOKEN` | なし | HuggingFace認証トークン。レート制限の緩和やプライベートモデルアクセスに使用 |

**`.env` の例:**

```env
HOST=127.0.0.1
PORT=9000
TORCH_CHANNEL=cu126
GLM_MODEL_ID=zai-org/GLM-OCR
GLM_MODEL_IDS=zai-org/GLM-OCR,zai-org/GLM-OCR-xxx
MODEL_CACHE_DIR=/runpod-volume/glm-ocr/hf_cache
HF_HOME=/runpod-volume/glm-ocr/hf_home
HF_TOKEN=hf_xxxxxxxxxxxxxxxx
```

## ライセンス

- このプロジェクト: `LICENSE`（MIT）
- サードパーティ情報: `THIRD_PARTY_NOTICES.md`
