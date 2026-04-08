import zstandard as zstd
import os

def compress_with_max_level(input_file, output_file):
    """
    使用zstd库以最高压缩级别压缩文件
    
    参数:
        input_file: 要压缩的输入文件路径
        output_file: 压缩后的输出文件路径
    """
    # 检查输入文件是否存在
    if not os.path.exists(input_file):
        raise FileNotFoundError(f"输入文件不存在: {input_file}")
    
    # 设置最高压缩级别（通常范围是1-22，22为最高）
    cctx = zstd.ZstdCompressor(level=22)
    
    # 读取输入文件并压缩写入输出文件
    with open(input_file, 'rb') as f_in, \
         open(output_file, 'wb') as f_out:
        # 使用压缩器压缩数据并写入输出流
        compressor = cctx.stream_writer(f_out)
        try:
            # 分块读取以处理大文件
            n = 4
            while True:

                chunk = f_in.read(n *1024 * 1024)  # n * 1MB块
                if not chunk:
                    break
                compressor.write(chunk)
        finally:
            compressor.flush()

if __name__ == "__main__":
    input_filename = "MonsterSiren.Uwp.exe.11196.dmp"
    output_filename = "MonsterSiren.Uwp.exe.11196.dmp.zst"
    
    try:
        compress_with_max_level(input_filename, output_filename)
        print(f"文件已成功压缩至 {output_filename}")
        print(f"原始大小: {os.path.getsize(input_filename)} 字节")
        print(f"压缩后大小: {os.path.getsize(output_filename)} 字节")
    except Exception as e:
        print(f"压缩失败: {str(e)}")
