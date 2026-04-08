from pathlib import Path
from tkinter.filedialog import askopenfilename

from openpyxl import load_workbook

fp = askopenfilename(
    title="Open Excel File",
    defaultextension=".xlsx",
    filetypes=[("Excel files", "*.xlsx"), ("All files", "*.*")],
    initialdir=Path.cwd(),
)

assert fp, "未选择文件名，操作已取消"

wb = load_workbook(fp)
sheet = wb.active

assert sheet, "未找到工作表，操作已取消"

sheet["E4"] = "项目二组"
sheet["F5"] = "张三、李斯、王五"
sheet["F6"] = "吃饭睡觉打豆豆"

output_fp = Path(fp).parent / f"{Path(fp).stem}_output.xlsx"
wb.save(output_fp)
