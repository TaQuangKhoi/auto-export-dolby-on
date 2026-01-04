import os, shutil, subprocess, time, shlex, sys

# Try to locate adb automatically. If not found, print an actionable error.
def find_adb():
    # 1) Use PATH
    adb = shutil.which("adb")
    if adb:
        return adb
    # 2) Use explicit environment variable ADB_PATH
    adb = os.environ.get("ADB_PATH")
    if adb and os.path.exists(adb):
        return adb
    # 3) Try ANDROID_HOME / ANDROID_SDK_ROOT/platform-tools
    android_home = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
    if android_home:
        candidate = os.path.join(android_home, "platform-tools", "adb.exe" if os.name == 'nt' else "adb")
        if os.path.exists(candidate):
            return candidate
    return None

ADB = find_adb()
if not ADB:
    print("Error: 'adb' executable not found.\n" \
          "Install Android Platform-tools and add 'adb' to your PATH, or set the environment variable ADB_PATH to the full adb path,\n" \
          "or set ANDROID_HOME / ANDROID_SDK_ROOT where platform-tools/adb is located.")
    sys.exit(1)


def adb(cmd):
    # Use shlex.split so quoted arguments stay together (e.g. text "hello world")
    args = [ADB] + shlex.split(cmd)
    try:
        subprocess.run(args, check=True)
    except FileNotFoundError:
        # Shouldn't happen because we checked earlier, but handle defensively
        print(f"Executable not found when running: {ADB}")
        raise
    except subprocess.CalledProcessError as e:
        print(f"adb command failed (exit {e.returncode}): {' '.join(e.cmd)}")
        raise

adb("shell input keyevent 3")        # Home
time.sleep(1)
adb("shell input tap 540 2100")      # ví dụ: mở app ở dock
time.sleep(2)
adb('shell input text "hello%sworld"')
adb("shell input keyevent 66")       # Enter
