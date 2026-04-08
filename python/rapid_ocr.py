from datetime import datetime
from tkinter.filedialog import askopenfilename
from rapidocr import RapidOCR
from rapidocr.utils import RapidOCROutput

engine = RapidOCR()

fp = askopenfilename(
    title="请选择文件",
    filetypes=[("Image files", "*.jpg;*.jpeg;*.png;*.bmp;*.tif;*.tiff")],
)


class TextResult:
    def __init__(self, box, text):
        self.box = box
        self.text = text
        self.anchor = box[0]


class ApplicationFormResult:
    def __init__(
        self,
        group: str = "",
        project: str = "",
        data_from: str = datetime.now().strftime("%Y-%m-%d"),
        date_to: str = datetime.now().strftime("%Y-%m-%d"),
    ):
        self.group = group
        self.project = project
        self.data_from = data_from
        self.date_to = date_to


result: RapidOCROutput = engine(fp, use_det=True, use_cls=False, use_rec=True)

text_results: list[TextResult] = []
for box, r in zip(result.boxes, result.txts):
    text_results.append(TextResult(box, r))

titles: dict[str, TextResult] = {}

keywords = [
    "广西遥感空间信息",
    "所在部门",
    "出差地点",
    "开始时间",
    "结束时间",
    "申请人",
    "出差事由",
    "部门意见",
]

for text_result in text_results:
    for keyword in keywords:
        if keyword in text_result.text:
            titles[keyword] = text_result
            break

if len(titles) < len(keywords):
    print(text_results)
    raise ValueError("未能识别到所有关键词，请检查图片内容。")

remaining_result = [result for result in text_results if result not in titles.values()]
print("all result:", [r.text for r in remaining_result])

application = ApplicationFormResult()
for r in remaining_result:
    if (
        r.anchor[0] > titles["所在部门"].anchor[0]
        and r.anchor[1] > titles["广西遥感空间信息"].anchor[1]
        and r.anchor[1] < titles["出差地点"].anchor[1]
    ):
        application.group = r.text
        continue

    if (
        r.anchor[0] > titles["开始时间"].anchor[0]
        and r.anchor[0] < titles["结束时间"].anchor[0]
        and r.anchor[1] > titles["所在部门"].anchor[1]
        and r.anchor[1] < titles["申请人"].anchor[1]
    ):
        application.data_from = r.text
        continue

    if (
        r.anchor[0] > titles["结束时间"].anchor[0]
        and r.anchor[1] > titles["所在部门"].anchor[1]
        and r.anchor[1] < titles["申请人"].anchor[1]
    ):
        application.date_to = r.text
        continue

    if (
        r.anchor[0] > titles["出差事由"].anchor[0]
        and r.anchor[1] > titles["申请人"].anchor[1]
        and r.anchor[1] < titles["部门意见"].anchor[1]
    ):
        application.project = (
            r.text if len(r.text) > len(application.project) else application.project
        )
        continue

print(application.__dict__)
