from pathlib import Path

from fastapi import APIRouter, HTTPException
from fastapi.responses import HTMLResponse

WEB_DIR = Path(__file__).resolve().parent

router = APIRouter()


@router.get("/", response_class=HTMLResponse)
async def index() -> HTMLResponse:
    html_path = WEB_DIR / "index.html"
    if not html_path.exists():
        raise HTTPException(
            status_code=500,
            detail="UI not found. Ensure web/index.html exists.",
        )
    return HTMLResponse(html_path.read_text(encoding="utf-8"))
