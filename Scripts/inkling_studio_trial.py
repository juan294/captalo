"""Operate the frozen Studio trial from its retained, owner-scoped evidence directory."""
import argparse
import json
import os
from pathlib import Path
import select
import subprocess
import importlib.metadata
import time
import sys
import zipfile

from inkling_measure import FROZEN, PILOT, require, sha, verify_tokens, write_once

HERE = Path(__file__).resolve().parent
PROFILE = "(version 1)(allow default)(deny network-outbound (with send-signal SIGKILL))"


def scoped_env(root):
    return {"HOME": str(root / "home"), "TMPDIR": str(root / "tmp") + "/", "PATH": "/usr/bin:/bin",
            "HF_HUB_OFFLINE": "1", "TRANSFORMERS_OFFLINE": "1", "HF_HUB_DISABLE_TELEMETRY": "1",
            "TOKENIZERS_PARALLELISM": "false", "PYTHONDONTWRITEBYTECODE": "1"}


def verify_runtime(root, spec, model, preview):
    from mlx_lm.utils import load_tokenizer

    lock = PILOT["load"](root / "runtime-lock.json")
    require(lock["runtime_sha"] == spec["runtime"].split("@")[1], "Incorrect runtime source")
    require(Path(sys.prefix).resolve() == (root / "venv").resolve() and sys.version == lock["python"],
            "Launcher and worker must use the frozen environment")
    require(lock["packages"] == sorted([d.metadata["Name"], d.version] for d in importlib.metadata.distributions()),
            "Installed environment differs from the frozen runtime")
    wheel, = (root / "wheels").glob("mlx_lm-*.whl")
    for path, key in [(root / "venv/bin/python", "executable_sha256"), (wheel, "wheel_sha256"),
                      (root / "runtime.tar.gz", "source_archive_sha256"), (root / "requirements.lock", "dependencies_lock_sha256")]:
        PILOT["check_file"](path, lock[key])
    dist = importlib.metadata.distribution("mlx-lm")
    with zipfile.ZipFile(wheel) as archive:
        for name in archive.namelist():
            if name.startswith("mlx_lm/") and not name.endswith("/"):
                require(dist.locate_file(name).read_bytes() == archive.read(name), f"Installed runtime differs: {name}")
    tokenizer = load_tokenizer(model, {"local_files_only": True}, PILOT["load"](model / "config.json").get("eos_token_id"))
    prepared = {r["id"]: json.loads(r["body"]) for r in PILOT["load"](PILOT["PREPARED"])["requests"]}
    for row in preview["rows"]:
        body = prepared[row["id"]]
        rendered = tokenizer.apply_chat_template(PILOT["messages"](body), tokenize=False, reasoning_effort="none",
                                                 add_generation_prompt=True)
        PILOT["check_render"](body, rendered)
        verify_tokens(tokenizer.encode(rendered, add_special_tokens=False), row)
    return sha((root / "runtime-lock.json").read_bytes())


def execute(root, mode, bundle, frozen_preview, controls_path):
    vpython = root / "venv/bin/python"
    model = root / "model"
    sandbox = ["/usr/bin/sandbox-exec", "-p", PROFILE]
    env = scoped_env(root)
    preview = PILOT["preview"](model, controls_path)
    require(preview == PILOT["load"](frozen_preview) and preview["candidate_sha256"] == FROZEN, "Wrong preview")
    spec = preview["spec"]
    tensor = spec["main_tensor"]
    expected = set(spec["metadata_sha256"]) | {tensor["file"]}
    require({p.relative_to(model).as_posix() for p in model.rglob("*") if p.is_file()} == expected,
            "Restore exactly the pinned original snapshot files")
    require((model / tensor["file"]).stat().st_size == tensor["bytes"], "Wrong tensor size")
    PILOT["check_file"](model / tensor["file"], tensor["sha256"])
    local_check = subprocess.run([*sandbox, vpython, "-I", "-c", "import mlx.core as m; assert m.array(1).item()==1"], env=env)
    deny_check = subprocess.run([*sandbox, vpython, "-I", "-c",
                                 "import socket; socket.create_connection(('127.0.0.1',9),1)"], env=env)
    require(local_check.returncode == 0 and deny_check.returncode == -9, "Sandbox control failed")
    setup = dict(runtime=spec["runtime"], local_control=local_check.returncode, denied_control=deny_check.returncode,
                 tensor_bytes=tensor["bytes"], tensor_sha256=tensor["sha256"], preview_sha256=FROZEN)
    setup["runtime_lock_sha256"] = verify_runtime(root, spec, model, preview)
    out = root / mode

    def launch(case):
        launched = time.monotonic()
        cmd = [*sandbox, vpython, "-I", HERE / "inkling_measure.py", "--model", model, "--out", out,
               "--preview", frozen_preview, "--case", case, "--launch", str(launched)]
        return subprocess.Popen(cmd, env=env)

    if mode == "smoke":
        out.mkdir()
        proc = launch("smoke")
        try:
            require(proc.wait(timeout=360) == 0, "Neutral smoke failed")
        finally:
            if proc.poll() is None:
                proc.kill()
                proc.wait()
        row = PILOT["load"](out / "smoke.1.answer.json")
        require(row["status"] == "eos" and row["first_sentence"] is not None, "Neutral probe has no complete final answer")
        write_once(out / "passed.json", setup)
        return
    require(PILOT["load"](root / "smoke/passed.json") == setup, "Smoke must pass with this setup")
    require(not out.exists(), f"Inspect existing run at {out}; do not regenerate it")
    voice = root / "voice-helper/voice-resident"
    voice_store = root / "voice-store"
    voice_store.mkdir()
    voice_proc = subprocess.Popen([*sandbox, voice, voice_store, bundle, root / "voice-intervals.jsonl"],
                                  stdin=subprocess.PIPE, stdout=subprocess.PIPE, env=env)
    try:
        require(select.select([voice_proc.stdout], [], [], 120)[0], "Voice warm-up timed out")
        voice_info = json.loads(voice_proc.stdout.readline())
        require(voice_info["pid"] == voice_proc.pid and voice_info["pcm"]["sustainedSignal"], "Voice PCM control failed")
        setup.update(voice_ready=voice_info["voice_ready"], voice=voice_info, clock=time.get_clock_info("monotonic").implementation)
        PILOT["reserve_run"](out, setup, spec["runtime"])
        write_once(out / "setup.json", setup)
        with (out / "telemetry.jsonl").open("x", buffering=1) as log:
            def sample(pid):
                def output(args):
                    return subprocess.run(args, capture_output=True, text=True).stdout.strip()
                log.write(json.dumps(dict(clock=time.monotonic(), worker_pid=pid, voice_pid=voice_proc.pid,
                                          rss_kib=output(["/bin/ps","-p",f"{pid},{voice_proc.pid}","-o","pid=,rss="]),
                                          pressure=output(["/usr/bin/memory_pressure","-Q"]),
                                          swap=output(["/usr/sbin/sysctl","-n","vm.swapusage"]))) + "\n")
            sample(os.getpid())
            for row in preview["rows"]:
                case = row["id"]
                proc = launch(case)
                try:
                    deadline = time.monotonic() + 360
                    while proc.poll() is None:
                        require(voice_proc.poll() is None, "Voice helper stopped during inference")
                        require(time.monotonic() < deadline, f"{case}: worker watchdog expired")
                        starts = sorted(out.glob(case + ".*.start.json"))
                        if starts:
                            latest = json.loads(starts[-1].read_bytes())
                            deadline = latest["reserved"] + 300
                        sample(proc.pid)
                        time.sleep(0.5)
                    require(proc.returncode == 0, f"{case}: worker exited {proc.returncode}")
                finally:
                    if proc.poll() is None:
                        proc.kill()
                        proc.wait()
                for repeat in (1, 2, 3):
                    result = PILOT["load"](out / f"{case}.{repeat}.answer.json")
                    require(result["token_ids_sha256"] == row["token_ids_sha256"] and result["repeat"] == repeat,
                            f"{case}.{repeat}: missing or stale answer")
    finally:
        voice_proc.stdin.close()
        try:
            voice_proc.wait(timeout=30)
        except subprocess.TimeoutExpired:
            voice_proc.kill()
            voice_proc.wait()
        tail = voice_proc.stdout.read()
        if tail:
            write_once(root / "voice-summary.json", json.loads(tail))
    require(voice_proc.returncode == 0, "Voice teardown failed")


if __name__ == "__main__":
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("mode", choices=["smoke", "measured"])
    for name in ("root", "bundle", "preview", "controls"):
        cli.add_argument("--" + name, type=Path, required=True)
    args = cli.parse_args()
    execute(args.root.resolve(), args.mode, args.bundle.resolve(), args.preview.resolve(), args.controls.resolve())
