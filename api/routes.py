from fastapi import APIRouter, File, Form, UploadFile

from app.main import (
    analyze,
    cancel,
    progress,
    status,
)

router = APIRouter(prefix="/api")


@router.get("/status")
async def status_route():
    return await status()


@router.get("/progress/{request_id}")
async def progress_route(request_id: str):
    return await progress(request_id)


@router.post("/cancel/{request_id}")
async def cancel_route(request_id: str):
    return await cancel(request_id)


@router.post("/analyze")
async def analyze_route(
    file: UploadFile = File(...),
    device: str = Form("auto"),
    model_id: str | None = Form(None),
    dpi: int = Form(220),
    task: str = Form("text"),
    linebreak_mode: str = Form("none"),
    schema: str | None = Form(None),
    instruction: str | None = Form(None),
    max_new_tokens: int = Form(1024),
    temperature: float = Form(0.0),
    use_layout: bool = Form(False),
    layout_backend: str = Form("ppdoclayoutv3"),
    reading_order: str = Form("auto"),
    region_padding: int = Form(12),
    max_regions: int = Form(200),
    region_parallelism: int = Form(1),
    request_id: str | None = Form(None),
):
    return await analyze(
        file=file,
        device=device,
        model_id=model_id,
        dpi=dpi,
        task=task,
        linebreak_mode=linebreak_mode,
        schema=schema,
        instruction=instruction,
        max_new_tokens=max_new_tokens,
        temperature=temperature,
        use_layout=use_layout,
        layout_backend=layout_backend,
        reading_order=reading_order,
        region_padding=region_padding,
        max_regions=max_regions,
        region_parallelism=region_parallelism,
        request_id=request_id,
    )
