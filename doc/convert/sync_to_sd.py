import os
import sys
import glob
import shutil
import argparse

EXPECTED_WIDTH = 640
EXPECTED_HEIGHT = 480
EXPECTED_BPP = 24


def validate_bmp(bmp_file):
    """返回 (是否有效, 原因)，只接受 FPGA 能直接显示的标准 BMP。"""
    try:
        with open(bmp_file, "rb") as handle:
            header = handle.read(54)
        if len(header) < 54 or header[0:2] != b"BM":
            return False, "不是有效 BMP 文件"

        file_size = int.from_bytes(header[2:6], "little")
        pixel_offset = int.from_bytes(header[10:14], "little")
        dib_size = int.from_bytes(header[14:18], "little")
        width = int.from_bytes(header[18:22], "little", signed=True)
        height = int.from_bytes(header[22:26], "little", signed=True)
        planes = int.from_bytes(header[26:28], "little")
        bit_count = int.from_bytes(header[28:30], "little")
        compression = int.from_bytes(header[30:34], "little")
        required_size = pixel_offset + EXPECTED_WIDTH * EXPECTED_HEIGHT * 3

        if dib_size < 40:
            return False, "DIB 信息头过短"
        if (width, height) != (EXPECTED_WIDTH, EXPECTED_HEIGHT):
            return False, f"分辨率为 {width}x{height}，应为 640x480"
        if planes != 1 or bit_count != EXPECTED_BPP or compression != 0:
            return False, "必须为 24 位、非压缩 BMP"
        if file_size < required_size or os.path.getsize(bmp_file) < required_size:
            return False, "文件被截断或像素数据不足"
        return True, ""
    except OSError as exc:
        return False, str(exc)


def collect_valid_images(source_dir, max_count):
    if not os.path.isdir(source_dir):
        print(f"[错误] 源文件夹不存在: {source_dir}")
        return []

    valid_files = []
    for bmp_file in sorted(glob.glob(os.path.join(source_dir, "*.bmp"))):
        valid, reason = validate_bmp(bmp_file)
        if valid:
            valid_files.append(bmp_file)
        else:
            print(f"[跳过] {os.path.basename(bmp_file)}: {reason}")
        if len(valid_files) >= max_count:
            break
    return valid_files

def clean_drive(target_drive):
    """
    删除目标驱动器下的所有文件，模拟格式化/清空操作（不删除隐藏系统文件夹）。
    """
    print(f"\n正在清空 {target_drive} 驱动器中的旧文件...")
    for item in os.listdir(target_drive):
        item_path = os.path.join(target_drive, item)
        # 跳过系统隐藏文件夹如 System Volume Information
        if item.startswith('.'):
            continue
            
        try:
            if os.path.isfile(item_path):
                os.remove(item_path)
            elif os.path.isdir(item_path):
                shutil.rmtree(item_path)
        except Exception as e:
            print(f"  [警告] 无法删除 {item_path}: {e}")
    print("驱动器清空完毕。")

def sync_new_images(files_to_copy, target_drive):
    """
    将已经校验过的 BMP 图片复制到目标驱动器。
    """
    print(f"\n准备将 {len(files_to_copy)} 张图片同步到 {target_drive}...")
    
    success_count = 0
    for i, bmp_file in enumerate(files_to_copy):
        try:
            filename = os.path.basename(bmp_file)
            # 增加序号，便于人工确认复制顺序（FPGA 按根目录项顺序读取）。
            target_name = f"{i:02d}_{filename}"
            target_path = os.path.join(target_drive, target_name)
            
            shutil.copy2(bmp_file, target_path)
            print(f"  [同步成功] {filename} -> {target_name}")
            success_count += 1
        except Exception as e:
            print(f"  [同步失败] {filename}: {e}")
            
    print(f"\n同步完成！成功写入 {success_count} 张新图片。")
    print("你现在可以安全弹出 SD 卡，插入 FPGA 开发板了。")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="FPGA SD卡 FAT32 图片安全同步工具")
    parser.add_argument('drive', help='SD 卡所在的盘符 (例如: E: 或 E:\\)')
    parser.add_argument('-s', '--source', help='存放转换好 BMP 图片的源文件夹 (默认: 当前目录的 output_bmp)', default=None)
    parser.add_argument('-n', '--num', type=int, default=4, help='最多同步的图片数量 (默认: 4)')
    
    args = parser.parse_args()

    if not 1 <= args.num <= 4:
        print("[错误] 同步图片数量必须在 1～4 之间。")
        sys.exit(1)

    # 处理盘符格式，确保以路径分隔符结尾
    target_drive = args.drive
    if not target_drive.endswith(':\\') and not target_drive.endswith(':/'):
        if target_drive.endswith(':'):
            target_drive += '\\'
        else:
            target_drive += ':\\'

    if not os.path.exists(target_drive):
        print(f"[致命错误] 找不到指定的驱动器: {target_drive}")
        print("请检查 SD 卡是否已正确插入电脑并分配了盘符。")
        sys.exit(1)

    # 确定源文件夹
    current_dir = os.path.dirname(os.path.abspath(__file__))
    source_dir = os.path.abspath(args.source) if args.source else os.path.join(current_dir, "output_bmp")
    files_to_copy = collect_valid_images(source_dir, args.num)
    if not files_to_copy:
        print(f"[错误] {source_dir} 中没有符合要求的 BMP，未修改 SD 卡。")
        sys.exit(1)

    print("="*50)
    print(f"目标 SD 卡盘符: {target_drive}")
    print(f"图片源文件夹  : {source_dir}")
    print("="*50)
    
    confirm = input(
        f"警告：即将清空 {target_drive} 中的现有文件。确认盘符无误后输入 YES："
    )
    if confirm != "YES":
        print("操作已取消，SD 卡未被修改。")
        sys.exit(0)
    
    # 步骤 1: 从 FAT 文件系统层面清空旧内容
    clean_drive(target_drive)
    
    # 步骤 2: 复制已通过格式校验的新图片
    sync_new_images(files_to_copy, target_drive)
