"""按大小切割 PDF 文件"""

import sys
from pathlib import Path

import fitz
from tqdm import tqdm

# PyMuPDF 1.26+ can emit noisy MuPDF messages for some PDFs even when the
# operation succeeds. Keep them off by default so batch runs stay readable.
if hasattr(fitz.TOOLS, "mupdf_display_errors"):
    fitz.TOOLS.mupdf_display_errors(False)
if hasattr(fitz.TOOLS, "mupdf_display_warnings"):
    fitz.TOOLS.mupdf_display_warnings(False)

# 50MB
MAX_SIZE = 50 * 1024 * 1024


def format_size(n: int) -> str:
    size = float(n)
    for unit in ("B", "KB", "MB"):
        if size < 1024:
            return f"{size:.1f} {unit}"
        size /= 1024
    return f"{size:.1f} GB"


def split_by_size(pdf_path: str, max_size: int = MAX_SIZE):
    """按指定大小切割 PDF，每块不超过 max_size 字节

    以"实际导出后的 PDF 文件大小"为准，贪心分组：在不超限的前提下
    尽可能塞入连续页。
    单页超限时独立成块。
    """
    doc = fitz.open(pdf_path)
    stem = Path(pdf_path).stem
    total_pages = len(doc)

    chunk = []  # 当前块的页码列表 (0-based)
    part = 1

    for i in tqdm(range(total_pages), desc="扫描页面", unit="页"):
        candidate = chunk + [i]
        candidate_size = _measure_chunk_size(doc, candidate)

        if candidate_size <= max_size:
            chunk = candidate
            continue

        if chunk:
            _save_chunk(doc, pdf_path, stem, chunk, part)
            part += 1

        # 当前页单独成块，或作为新块起点
        single_size = _measure_chunk_size(doc, [i])

        if single_size > max_size:
            _save_chunk(doc, pdf_path, stem, [i], part)
            part += 1
            chunk = []
        else:
            chunk = [i]

    # 输出最后一个块
    if chunk:
        _save_chunk(doc, pdf_path, stem, chunk, part)

    doc.close()


def _measure_chunk_size(doc: fitz.Document, pages: list[int]) -> int:
    """返回选定页导出后的实际 PDF 字节数。"""
    out = fitz.open()
    out.insert_pdf(doc, from_page=pages[0], to_page=pages[-1])
    data = out.tobytes()
    out.close()
    return len(data)


def _save_chunk(
    doc: fitz.Document, src_path: str, stem: str, pages: list[int], part: int
):
    """将指定页码写入新的 PDF 文件"""
    out_dir = Path(src_path).parent
    out_path = out_dir / f"{stem}_part{part}.pdf"

    out = fitz.open()
    out.insert_pdf(doc, from_page=pages[0], to_page=pages[-1])

    out.save(str(out_path))
    size = out_path.stat().st_size
    out.close()

    page_range = (
        f"第 {pages[0] + 1}-{pages[-1] + 1} 页"
        if len(pages) > 1
        else f"第 {pages[0] + 1} 页"
    )
    tqdm.write(f"  {out_path.name} ({page_range}, {format_size(size)})")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("用法: python pdf_spliter.py <pdf文件路径>")
        sys.exit(1)

    path = sys.argv[1]
    print(f"切割 {path}，每块上限 {MAX_SIZE / 1024 / 1024:.0f} MB")
    split_by_size(path, MAX_SIZE)
