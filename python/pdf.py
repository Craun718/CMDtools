from reportlab.pdfgen import canvas
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import getSampleStyleSheet
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer


def create_a4_pdf_with_canvas(filename):
    """使用canvas创建A4大小的PDF文件"""
    # A4的尺寸为(210mm, 297mm)，ReportLab默认单位是点(1点=1/72英寸)
    c = canvas.Canvas(filename, pagesize=A4)

    # 获取A4尺寸的宽度和高度
    width, height = A4

    # 添加标题
    c.setFont("Helvetica-Bold", 16)
    c.drawCentredString(width / 2, height - 40, "A4尺寸PDF文档示例")

    # 添加正文
    c.setFont("Helvetica", 12)
    text = "这是一个使用ReportLab创建的A4尺寸(210mm × 297mm)PDF文档。"
    c.drawString(50, height - 80, text)

    text = f"A4宽度: {width:.2f}点，A4高度: {height:.2f}点"
    c.drawString(50, height - 100, text)

    # 绘制一个矩形作为页面边界参考
    c.setStrokeColorRGB(0.8, 0.8, 0.8)  # 浅灰色
    c.rect(30, 30, width - 60, height - 60, stroke=1, fill=0)

    # 完成第一页
    c.showPage()

    # 添加第二页内容
    c.setFont("Helvetica-Bold", 14)
    c.drawString(50, height - 60, "第二页内容")

    c.setFont("Helvetica", 12)
    c.drawString(50, height - 90, "这是文档的第二页，同样保持A4尺寸。")

    # 保存PDF文件
    c.save()


def create_a4_pdf_with_platypus(filename):
    """使用platypus创建A4大小的PDF文件（更高级的方式）"""
    # 创建文档模板，默认A4尺寸
    doc = SimpleDocTemplate(
        filename,
        pagesize=A4,
        leftMargin=50,
        rightMargin=50,
        topMargin=50,
        bottomMargin=50,
    )

    # 获取样式表
    styles = getSampleStyleSheet()

    # 创建内容列表
    elements = []

    # 添加标题
    title = Paragraph("使用Platypus创建的A4文档", styles["Title"])
    elements.append(title)
    elements.append(Spacer(1, 20))

    # 添加正文
    p1 = Paragraph(
        "这是一个使用ReportLab的Platypus模块创建的A4尺寸PDF文档。", styles["Normal"]
    )
    elements.append(p1)

    p2 = Paragraph(
        "Platypus提供了更高层次的抽象，使文档创建更加简单，特别是对于多页文档和复杂布局。",
        styles["Normal"],
    )
    elements.append(p2)

    # 构建文档
    doc.build(elements)


if __name__ == "__main__":
    # 创建两个示例PDF，都为A4尺寸
    create_a4_pdf_with_canvas("a4_example_canvas.pdf")
    create_a4_pdf_with_platypus("a4_example_platypus.pdf")
    print("A4尺寸的PDF文件已生成")
