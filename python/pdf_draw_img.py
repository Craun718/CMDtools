import os
import tempfile
from reportlab.pdfgen import canvas
from reportlab.lib.pagesizes import A4
from PIL import Image


def create_a4_pdf_with_canvas(filename):
    """使用canvas创建A4大小的PDF文件"""
    # A4的尺寸为(210mm, 297mm)，ReportLab默认单位是点(1点=1/72英寸)
    c = canvas.Canvas(filename, pagesize=A4)

    # 获取A4尺寸的宽度和高度
    a4width, a4height = A4
    print(f"A4尺寸: {a4width}点 x {a4height}点")

    img = "1.png"  # 假设图片文件名为1.png
    pil_img = Image.open(img)
    img_width, img_height = pil_img.size
    print(f"图片尺寸: {img_width}pt x {img_height}pt")

    new_width = int(a4width * 0.8)
    new_height = int((new_width / img_width) * img_height)

    new_height = int((new_width / img_width) * img_height)
    # pil_img = pil_img.resize((new_width, new_height), Image.Resampling.LANCZOS)

    temp_file = None
    try:
        # 创建临时文件
        with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as temp_file:
            # 保存图像到临时文件
            pil_img.save(temp_file, format="PNG")
            temp_file_path = temp_file.name

        # 使用临时文件路径绘制图像
        c.drawImage(
            temp_file_path, 50, a4height - 250, width=new_width, height=new_height
        )

    finally:
        # 确保临时文件被删除
        if temp_file and os.path.exists(temp_file_path):
            os.unlink(temp_file_path)

    # 完成第一页
    c.showPage()

    # 添加第二页内容
    # c.setFont("Helvetica-Bold", 14)
    # c.drawString(50, a4height - 60, "第二页内容")
    temp_file = None
    try:
        # 创建临时文件
        with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as temp_file:
            # 保存图像到临时文件
            pil_img.save(temp_file, format="PNG")
            temp_file_path = temp_file.name

        # 使用临时文件路径绘制图像
        c.drawImage(
            temp_file_path, 50, a4height - 250, width=new_width, height=new_height
        )

    finally:
        # 确保临时文件被删除
        if temp_file and os.path.exists(temp_file_path):
            os.unlink(temp_file_path)

    c.setFont("Helvetica", 12)
    c.drawString(50, a4height - 90, "这是文档的第二页，同样保持A4尺寸。")

    # 保存PDF文件
    c.save()


if __name__ == "__main__":
    # 创建两个示例PDF，都为A4尺寸
    create_a4_pdf_with_canvas("a4_example_img.pdf")
    print("A4尺寸的PDF文件已生成")
