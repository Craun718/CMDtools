import pdfplumber
import os

from tkinter.filedialog import askopenfilename

def convert_pdf_to_image_v2(pdf_path, image_path):
    with pdfplumber.open(pdf_path) as pdf:
        for i, page in enumerate(pdf.pages):
            image = page.to_image(resolution=150)
            image_path_full = os.path.join(image_path, f'{i + 1}.png')
            image.save(image_path_full)

# 使用示例
pdf_path = askopenfilename(
    title="请选择PDF文件",
    filetypes=[("PDF files", "*.pdf")],
    
)
image_path = '.'
convert_pdf_to_image_v2(pdf_path, image_path)