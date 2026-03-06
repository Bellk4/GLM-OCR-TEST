import asyncio
import base64
import threading
from pathlib import Path
from typing import Any, Optional

try:
    import runpod  # type: ignore[import-not-found]
except ImportError:  # pragma: no cover
    runpod = None

from app.layout_ppdoclayoutv3 import LayoutBlock, detect_layout_blocks
from app.main import (
    ALLOWED_LAYOUT_BACKENDS,
    ALLOWED_LINEBREAK_MODES,
    ALLOWED_READING_ORDERS,
    ALLOWED_TASKS,
    DEFAULT_DPI,
    DEFAULT_INSTRUCTION,
    DEFAULT_LAYOUT_BACKEND,
    DEFAULT_MAX_NEW_TOKENS,
    DEFAULT_MAX_REGIONS,
    DEFAULT_READING_ORDER,
    DEFAULT_REGION_PADDING,
    DEFAULT_REGION_PARALLELISM,
    DEFAULT_TEMPERATURE,
    DEFAULT_USE_LAYOUT,
    RUNTIME,
    block_prompt_for_task,
    bbox_dict,
    build_layout_preview_base64,
    build_prompt,
    clamp_bbox_with_padding,
    clear_cancel_request,
    combine_block_texts,
    glm_infer,
    normalize_layout_label,
    normalize_model_id,
    normalize_text_output,
    resolve_device,
    resolve_effective_reading_order,
    save_temp_png,
    save_temp_upload,
    sort_layout_blocks,
    load_pages,
)


def _coerce_bool(value: Any, default: bool = False) -> bool:
    if value is None:
        return default
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return bool(value)
    text = str(value).strip().lower()
    if text in {"1", "true", "yes", "on"}:
        return True
    if text in {"0", "false", "no", "off", ""}:
        return False
    return default


def _decode_base64_payload(value: str) -> bytes:
    payload = (value or "").strip()
    if not payload:
        raise ValueError("file_base64 is empty")
    if "," in payload and payload.lower().startswith("data:"):
        payload = payload.split(",", 1)[1]
    try:
        return base64.b64decode(payload, validate=False)
    except Exception as exc:
        raise ValueError(f"invalid base64 payload: {exc}") from exc


def _read_input_file(input_data: dict[str, Any]) -> tuple[bytes, str]:
    if "file_base64" in input_data:
        filename = str(input_data.get("filename") or "upload.pdf")
        return _decode_base64_payload(str(input_data.get("file_base64") or "")), filename

    file_value = input_data.get("file")
    if isinstance(file_value, str):
        filename = str(input_data.get("filename") or "upload.pdf")
        return _decode_base64_payload(file_value), filename

    if isinstance(file_value, dict):
        encoded = str(file_value.get("base64") or file_value.get("data") or "")
        filename = str(file_value.get("filename")
                       or input_data.get("filename") or "upload.pdf")
        return _decode_base64_payload(encoded), filename

    raise ValueError("Missing file input. Use file_base64 or file(base64).")


async def _run_ocr(input_data: dict[str, Any]) -> dict[str, Any]:
    model_id = normalize_model_id(input_data.get("model_id"))
    device = resolve_device(str(input_data.get("device") or "auto"))

    task = str(input_data.get("task") or "text").strip().lower()
    if task not in ALLOWED_TASKS:
        raise ValueError(f"Unsupported task: {task}")

    linebreak_mode = str(input_data.get("linebreak_mode")
                         or "none").strip().lower()
    if linebreak_mode not in ALLOWED_LINEBREAK_MODES:
        raise ValueError(f"Unsupported linebreak_mode: {linebreak_mode}")

    schema_raw = input_data.get("schema")
    schema = None if schema_raw is None else str(schema_raw)

    instruction = str(input_data.get("instruction")
                      or "").strip() or DEFAULT_INSTRUCTION

    layout_backend = str(input_data.get("layout_backend")
                         or DEFAULT_LAYOUT_BACKEND).strip().lower()
    if layout_backend not in ALLOWED_LAYOUT_BACKENDS:
        raise ValueError(f"Unsupported layout_backend: {layout_backend}")

    reading_order = str(input_data.get("reading_order")
                        or DEFAULT_READING_ORDER).strip().lower()
    if reading_order not in ALLOWED_READING_ORDERS:
        raise ValueError(f"Unsupported reading_order: {reading_order}")

    dpi = max(36, min(600, int(input_data.get("dpi") or DEFAULT_DPI)))
    max_new_tokens = max(
        1, min(32768, int(input_data.get("max_new_tokens") or DEFAULT_MAX_NEW_TOKENS)))
    temperature = float(input_data.get("temperature") or DEFAULT_TEMPERATURE)
    use_layout = _coerce_bool(input_data.get("use_layout"), DEFAULT_USE_LAYOUT)
    region_padding = max(
        0, min(256, int(input_data.get("region_padding") or DEFAULT_REGION_PADDING)))
    max_regions = max(
        1, min(1000, int(input_data.get("max_regions") or DEFAULT_MAX_REGIONS)))
    region_parallelism = max(
        1,
        min(8, int(input_data.get("region_parallelism")
            or DEFAULT_REGION_PARALLELISM)),
    )

    prompt = build_prompt(task, schema, instruction)

    await RUNTIME.ensure_loaded(device, model_id)
    processor, model, actual_device = RUNTIME.get()

    file_bytes, filename = _read_input_file(input_data)
    input_path = save_temp_upload(filename, file_bytes)
    try:
        pages = load_pages(Path(input_path), dpi)
    finally:
        Path(input_path).unlink(missing_ok=True)

    results: list[dict[str, Any]] = []
    for index, page in enumerate(pages, start=1):
        if not use_layout:
            page_path = save_temp_png(page)
            try:
                raw_text, clean_text, truncated = await asyncio.to_thread(
                    glm_infer,
                    processor,
                    model,
                    str(page_path),
                    prompt,
                    max_new_tokens,
                    temperature,
                    None,
                )
            finally:
                page_path.unlink(missing_ok=True)

            item: dict[str, Any] = {
                "page": index,
                "text": (
                    normalize_text_output(clean_text, task, linebreak_mode)
                    if task != "extract_json"
                    else clean_text
                ),
                "raw": raw_text,
                "json": None,
                "truncated": bool(truncated),
            }
            if task == "extract_json":
                try:
                    import json

                    item["json"] = json.loads(clean_text)
                except Exception as exc:
                    item["error"] = f"JSON parse failed: {exc}"
            results.append(item)
            continue

        raw_layout_blocks = await asyncio.to_thread(
            detect_layout_blocks,
            page,
            layout_backend,
        )
        padded_blocks = [
            LayoutBlock(
                type=normalize_layout_label(block.type),
                bbox=clamp_bbox_with_padding(block.bbox, page, region_padding),
                score=float(block.score),
            )
            for block in raw_layout_blocks
        ]
        if not padded_blocks:
            width, height = page.size
            padded_blocks = [LayoutBlock(
                type="text", bbox=(0, 0, width, height), score=1.0)]

        effective_order = resolve_effective_reading_order(
            padded_blocks, reading_order)
        ordered_blocks = sort_layout_blocks(
            padded_blocks, effective_order)[:max_regions]
        if not ordered_blocks:
            width, height = page.size
            ordered_blocks = [LayoutBlock(
                type="text", bbox=(0, 0, width, height), score=1.0)]

        block_results: list[Optional[dict[str, Any]]] = [
            None] * len(ordered_blocks)
        region_semaphore = asyncio.Semaphore(region_parallelism)

        async def infer_region(region_index: int, layout_block: LayoutBlock) -> tuple[int, dict[str, Any]]:
            item: dict[str, Any] = {
                "id": f"b{region_index + 1}",
                "type": normalize_layout_label(layout_block.type),
                "bbox": bbox_dict(layout_block.bbox),
                "text": "",
                "raw": "",
                "truncated": False,
            }
            crop = page.crop(layout_block.bbox)
            crop_path = save_temp_png(crop)
            try:
                region_prompt = block_prompt_for_task(
                    task, layout_block.type, schema, instruction)
                async with region_semaphore:
                    raw_text, clean_text, truncated = await asyncio.to_thread(
                        glm_infer,
                        processor,
                        model,
                        str(crop_path),
                        region_prompt,
                        max_new_tokens,
                        temperature,
                        None,
                    )
                item["raw"] = raw_text
                item["text"] = (
                    clean_text
                    if task == "extract_json"
                    else normalize_text_output(clean_text, task, "none")
                )
                item["truncated"] = bool(truncated)
            except Exception as exc:
                item["error"] = str(exc)
            finally:
                crop_path.unlink(missing_ok=True)
            return region_index, item

        jobs = [infer_region(i, b) for i, b in enumerate(ordered_blocks)]
        outputs = await asyncio.gather(*jobs)
        for output_index, block_item in outputs:
            block_results[output_index] = block_item

        page_blocks = [item for item in block_results if item is not None]
        combined_text = combine_block_texts(
            page_blocks,
            linebreak_mode if task != "extract_json" else "none",
        )
        combined_raw = "\n\n".join(
            str(item.get("raw") or "").strip() for item in page_blocks if item
        ).strip()
        page_item: dict[str, Any] = {
            "page": index,
            "text": combined_text,
            "raw": combined_raw,
            "json": None,
            "blocks": page_blocks,
            "reading_order": effective_order,
            "layout_preview_base64": build_layout_preview_base64(page, page_blocks),
        }
        block_errors = [
            f"{block.get('id')}: {block.get('error')}"
            for block in page_blocks
            if block.get("error")
        ]
        if block_errors:
            page_item["error"] = "\n".join(block_errors)
        if task == "extract_json":
            try:
                import json

                page_item["json"] = json.loads(combined_text)
            except Exception as exc:
                page_item["error"] = (
                    f"{page_item.get('error', '')}\nJSON parse failed: {exc}".strip(
                    )
                )
        results.append(page_item)

    clear_cancel_request("serverless")
    return {
        "device": actual_device,
        "model": model_id,
        "task": task,
        "linebreak_mode": linebreak_mode,
        "use_layout": use_layout,
        "layout_backend": layout_backend,
        "reading_order": reading_order,
        "region_padding": region_padding,
        "max_regions": max_regions,
        "region_parallelism": region_parallelism,
        "state": "done",
        "page_count": len(pages),
        "results": results,
    }


def handler(job: dict[str, Any]) -> dict[str, Any]:
    try:
        input_data = dict(job.get("input") or {})

        try:
            asyncio.get_running_loop()
            has_running_loop = True
        except RuntimeError:
            has_running_loop = False

        if not has_running_loop:
            return asyncio.run(_run_ocr(input_data))

        # Run in a dedicated thread when the current thread already has an event loop.
        result_holder: dict[str, dict[str, Any]] = {}
        error_holder: dict[str, Exception] = {}

        def _runner() -> None:
            try:
                result_holder["value"] = asyncio.run(_run_ocr(input_data))
            except Exception as exc:  # pragma: no cover - passthrough
                error_holder["error"] = exc

        thread = threading.Thread(target=_runner, daemon=True)
        thread.start()
        thread.join()

        if "error" in error_holder:
            raise error_holder["error"]
        return result_holder.get("value", {"state": "error", "error": "unknown error"})
    except Exception as exc:
        return {"state": "error", "error": str(exc)}


if __name__ == "__main__":
    if runpod is None:
        raise RuntimeError(
            "runpod package is required for serverless execution. Install with: pip install runpod"
        )
    runpod.serverless.start({"handler": handler})
