import subprocess
import sys
import os
import shutil
import time
import webbrowser


def find_node():
    """
    查找本机 node.exe 的绝对路径。

    先按 Node.js 官方安装包的默认安装位置逐个探测，探测不到再退回
    `where node` 让系统按 PATH 查找。

    @return: node.exe 的绝对路径字符串；未安装 Node.js 时返回 None
    """
    node_candidate_paths = [
        r"C:\Program Files\nodejs\node.exe",
        r"C:\Program Files (x86)\nodejs\node.exe",
    ]
    for candidate_path in node_candidate_paths:
        if os.path.exists(candidate_path):
            return candidate_path

    # `where node` 可能命中多行（PATH 里装了多份 Node），只取第一行
    where_result = subprocess.run(['where', 'node'], capture_output=True, text=True)
    if where_result.returncode == 0 and where_result.stdout.strip():
        return where_result.stdout.strip().split('\n')[0]
    return None


def find_npm(node_dir):
    """
    查找 npm 启动器的完整路径。

    坑：Windows 下 npm 是批处理文件 npm.cmd，subprocess 走 CreateProcess，
    传裸名 "npm" 会直接找不到可执行文件，必须给出 .cmd 的完整路径。

    @param node_dir: node.exe 所在目录（str）
    @return: npm.cmd 的完整路径；找不到时返回 None
    """
    # node.exe 同目录下必定有 npm.cmd（官方安装包自带）
    npm_cmd_path = os.path.join(node_dir, "npm.cmd")
    if os.path.exists(npm_cmd_path):
        return npm_cmd_path

    # 兜底：让 Python 按 PATHEXT 规则搜索
    npm_from_path = shutil.which("npm")
    if npm_from_path and os.path.exists(npm_from_path):
        return npm_from_path

    npm_cmd_from_path = shutil.which("npm.cmd")
    if npm_cmd_from_path:
        return npm_cmd_from_path
    return None


def main():
    """
    一键启动入口：检查 Node/npm -> 首次补齐依赖 -> 拉起 Vite 开发服务器 -> 打开浏览器。

    @return: 无返回值；Node 或 npm 缺失时打印提示后以退出码 1 结束进程
    """
    print("=" * 50)
    print("  智慧校园管理平台 - 一键启动")
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

    # 启动开发服务器
    print("\n🚀 启动开发服务器...")
    print("   启动后将自动打开浏览器")
    print("   按 Ctrl+C 可停止服务\n")

    dev_server_proc = subprocess.Popen(
        [npm_cmd, "run", "dev", "--", "--host", "0.0.0.0", "--port", "5173"],
        cwd=frontend_dir,
        env=env,
    )

    # 等几秒让 vite 启动
    time.sleep(4)

    # 打开浏览器：系统没有可用浏览器时 webbrowser 抛 webbrowser.Error，
    # 浏览器进程启动失败时抛 OSError，两种情况都只降级为提示，不影响 vite 继续跑
    try:
        webbrowser.open("http://localhost:5173/")
        print("✅ 已打开浏览器 http://localhost:5173/")
    except (webbrowser.Error, OSError):
        print("⚠️  请手动打开 http://localhost:5173/")

    print("\n按 Ctrl+C 停止服务...\n")
    try:
        dev_server_proc.wait()
    except KeyboardInterrupt:
        dev_server_proc.terminate()
        print("\n👋 服务已停止")


if __name__ == "__main__":
    main()