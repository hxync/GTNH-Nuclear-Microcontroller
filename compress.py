import os
import subprocess
import sys

# 文件路径
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
source_file = os.path.join(BASE_DIR, "nuclear_SourceCode.lua")
for_luamin_file = os.path.join(BASE_DIR, "nuclear_ForLuamin.lua")
final_file = os.path.join(BASE_DIR, "nuclear.lua")

def step1_preprocess():
    """读取源文件，执行文本替换，保存到中间文件"""
    with open(source_file, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # 替换规则（顺序敏感，逐个替换）
    replacements = []
        #("side", "a"),
        #(".wakeTime", ".b"),
        #(".task", ".c"),
        #("check", "d"),
        #("replace", "e"),
        #(".sleep", ".f"),
        #(":sleep", ":f"),
        #(".ready", ".g")
    #]
    
    for old, new in replacements:
        content = content.replace(old, new)
    
    with open(for_luamin_file, 'w', encoding='utf-8') as f:
        f.write(content)
    print("Step 1 完成：已生成预处理文件 nuclear_ForLuamin.lua")

def step2_luamin():
    """调用 luamin 混淆，生成 nuclear.lua"""
    cmd = f'luamin -f "{for_luamin_file}" > "{final_file}"'
    print(f"Step 2 执行命令: {cmd}")
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if result.returncode != 0:
        print("luamin 执行失败:", result.stderr)
        sys.exit(1)
    print("Step 2 完成：luamin 已生成 nuclear.lua")

def step3_postprocess():
    """读取 nuclear.lua，替换关键字，包裹后写回"""
    with open(final_file, 'r', encoding='utf-8') as f:
        obfuscated = f.read()
    
    # 删除末尾的换行符
    obfuscated = obfuscated.rstrip('\n')
    
    # 将 function、return、then、local、end 替换为 &@、@&、$、&、@
    replaced = obfuscated.replace("function", "&@").replace("return", "@&").replace("then ", "$").replace("local ", "&").replace("end", "@")
    
    # 转义替换后文本中的单引号和反斜杠，使其能安全嵌入到单引号字符串中
    safe_replaced = replaced.replace("\\", "\\\\").replace("'", "\\'")
    
    # 按模板生成最终代码
    final_code = f"local t='{safe_replaced}';load(t:gsub(\"&@\",\"function\"):gsub(\"@&\",\"return\"):gsub(\"%$\",\"then \"):gsub(\"&\",\"local \"):gsub(\"@\",\"end\"))()"
    
    with open(final_file, 'w', encoding='utf-8') as f:
        f.write(final_code)
    print("Step 3 完成：已封装最终代码到 nuclear.lua")

def cleanup():
    """删除中间文件"""
    try:
        os.remove(for_luamin_file)
        print("清理完成：已删除 nuclear_ForLuamin.lua")
    except FileNotFoundError:
        pass

if __name__ == "__main__":
    step1_preprocess()
    step2_luamin()
    step3_postprocess()
    cleanup()
    print("全部任务完成！")