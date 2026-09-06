import subprocess
import sys
import os
import shutil
import time
import webbrowser


def find_node():
    """查找 node.exe 路径"""
    paths = [
        r"C:\Program Files\nodejs\node.exe",
        r"C:\Program Files (x86)\nodejs\node.exe",
    ]
    for p in paths:
        if os.path.exists(p):
            return p
    result = subprocess.run(['where', 'node'], capture_output=True, text=True)
    if result.returncode == 0 and result.stdout.strip():
        return result.stdout.strip().split('\n')[0]
    return None


def find_npm(node_dir):
    """查找 npm.cmd 完整路径（Windows 下 npm 是批处理文件，subprocess 需 .cmd 才能 CreateProcess）"""
    # node.exe 同目录下必定有 npm.cmd（官方安装包自带）
    cmd = os.path.join(node_dir, "npm.cmd")
    if os.path.exists(cmd):
        return cmd
    # 兜底：让 Python 按 PATHEXT 规则搜索
    which = shutil.which("npm")
    if which and os.path.exists(which):
        return which
    which_cmd = shutil.which("npm.cmd")
    if which_cmd:
        return which_cmd
    return None


def main():
    print("=" * 50)
    print("  校园积分管理平台 - 一键启动")
    print("=" * 50)

    node_path = find_node()
    if not node_path:
        print("\n❌ 未找到 Node.js，请先安装 Node.js 20+")
        input("按回车键退出...")
        sys.exit(1)

    node_dir = os.path.dirname(node_path)
    npm_cmd = find_npm(node_dir)
    if not npm_cmd:
        print("\n❌ 未找到 npm.cmd，请检查 Node.js 安装是否完整")
        print(f"   预期位置: {node_dir}\\npm.cmd")
        input("按回车键退出...")
        sys.exit(1)

    print(f"   Node: {node_path}")
    print(f"   Npm : {npm_cmd}")

    frontend_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "frontend")

    # 设置 PATH
    env = os.environ.copy()
    env["PATH"] = node_dir + ";" + env["PATH"]

    # 检查依赖
    print("\n📦 检查依赖...")
    if not os.path.exists(os.path.join(frontend_dir, "node_modules")):
        print("首次运行，安装依赖（可能需要几分钟）...")
        subprocess.run([npm_cmd, "install"], cwd=frontend_dir, env=env, check=True)

    # 清除旧的 mock 缓存
    print("🧹 清除旧的 mock 缓存...")
    # 前端启动后在浏览器里处理

    # 启动开发服务器
    print("\n🚀 启动开发服务器...")
    print("   启动后将自动打开浏览器")
    print("   按 Ctrl+C 可停止服务\n")

    proc = subprocess.Popen(
        [npm_cmd, "run", "dev", "--", "--host", "0.0.0.0", "--port", "5173"],
        cwd=frontend_dir,
        env=env,
    )

    # 等几秒让 vite 启动
    time.sleep(4)

    # 打开浏览器
    try:
        webbrowser.open("http://localhost:5173/")
        print("✅ 已打开浏览器 http://localhost:5173/")
    except Exception:
        print("⚠️  请手动打开 http://localhost:5173/")

    print("\n按 Ctrl+C 停止服务...\n")
    try:
        proc.wait()
    except KeyboardInterrupt:
        proc.terminate()
        print("\n👋 服务已停止")


if __name__ == "__main__":
    main()
