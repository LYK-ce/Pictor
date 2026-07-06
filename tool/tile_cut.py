#!/usr/bin/env python3
"""
tile_cut.py - 将 PNG 图片切分成网格，并保存指定位置的子图

用法:
    python tile_cut.py rownum=2 colnum=2 pos=1,2
    python tile_cut.py input=my_image.png rownum=3 colnum=4 pos=2,3 output=piece.png

    python tile_cut.py input=D:\Section01\Workspace\Pictor\Assets\2D\tilemap_packed.png rownum=14 colnum=19 pos=9,17 output=1.png

参数说明:
    input   : 输入 PNG 文件路径（默认 input.png）
    rownum  : 纵向切分数（必需）
    colnum  : 横向切分数（必需）
    pos     : 要保存的子图位置，格式为 "行,列"（1‑indexed，必需）
    output  : 输出 PNG 文件路径（默认自动生成，如 subimage_r1_c2.png）
"""

import sys
import os
from PIL import Image

def parse_args():
    """解析命令行键值对参数，返回字典。"""
    args = {}
    for arg in sys.argv[1:]:
        if '=' not in arg:
            # 若参数不含等号，则作为输入文件处理（兼容旧用法）
            if 'input' not in args:
                args['input'] = arg
            else:
                print(f"警告：忽略未知参数 '{arg}'")
            continue
        key, value = arg.split('=', 1)
        args[key.lower()] = value
    return args

def validate_and_convert(args):
    """验证必需参数，转换类型，返回处理后的字典。"""
    required = ['rownum', 'colnum', 'pos']
    for r in required:
        if r not in args:
            print(f"错误：缺少必需参数 '{r}'")
            sys.exit(1)

    try:
        rownum = int(args['rownum'])
        colnum = int(args['colnum'])
    except ValueError:
        print("错误：rownum 和 colnum 必须为整数")
        sys.exit(1)

    if rownum <= 0 or colnum <= 0:
        print("错误：rownum 和 colnum 必须为正整数")
        sys.exit(1)

    pos_str = args['pos']
    try:
        row, col = map(int, pos_str.split(','))
    except ValueError:
        print("错误：pos 格式应为 '行,列'，例如 '1,2'")
        sys.exit(1)

    if row < 1 or col < 1 or row > rownum or col > colnum:
        print(f"错误：pos ({row},{col}) 超出切分范围 (1..{rownum}, 1..{colnum})")
        sys.exit(1)

    # 输入输出文件
    input_file = args.get('input', 'input.png')
    if not os.path.isfile(input_file):
        print(f"错误：输入文件 '{input_file}' 不存在")
        sys.exit(1)

    output_file = args.get('output', f'subimage_r{row}_c{col}.png')

    return {
        'input': input_file,
        'output': output_file,
        'rownum': rownum,
        'colnum': colnum,
        'row': row,
        'col': col
    }

def main():
    args_dict = parse_args()
    params = validate_and_convert(args_dict)

    try:
        img = Image.open(params['input'])
    except Exception as e:
        print(f"错误：无法打开图片 '{params['input']}': {e}")
        sys.exit(1)

    # 计算每个子图的尺寸（整数除法，忽略边缘多出的像素）
    width, height = img.size
    tile_w = width // params['colnum']
    tile_h = height // params['rownum']

    # 计算裁剪区域（左上角坐标）
    left = (params['col'] - 1) * tile_w
    upper = (params['row'] - 1) * tile_h
    right = left + tile_w
    lower = upper + tile_h

    # 裁剪并保存
    try:
        cropped = img.crop((left, upper, right, lower))
        cropped.save(params['output'])
        print(f"成功保存子图到 '{params['output']}'")
    except Exception as e:
        print(f"错误：保存图片失败: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()