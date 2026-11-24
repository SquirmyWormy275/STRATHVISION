#!/usr/bin/env python3
"""Explicitly install one pinned, optional CPU transcription runtime.

Python standard library only. Running this command downloads source/model;
importing it and using the app never performs these downloads.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tempfile
import urllib.request


VERSION = "1.9.6"
SOURCE_COMMIT = "96ec4d9823e9d0211944172da35f9f29134af990"
SOURCE_URL = "https://github.com/ggml-org/whisper.cpp.git"
MODEL_REVISION = "5359861c739e955e79d9a303bcbc70fb988958b1"
MODEL_SHA256 = "60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe"
MODEL_BYTES = 147951465
MODEL_URL = (
    "https://huggingface.co/ggerganov/whisper.cpp/resolve/"
    f"{MODEL_REVISION}/ggml-base.bin"
)

# Static whisper/ggml libraries; the operating system's C/C++ runtime can remain
# dynamic. No GPU, network model loader, RPC, FFmpeg or downloaded CPU backend.
CMAKE_OPTIONS = {
    "CMAKE_BUILD_TYPE": "Release",
    "BUILD_SHARED_LIBS": "OFF",
    "WHISPER_BUILD_IS_DEV": "OFF",
    "WHISPER_BUILD_TESTS": "OFF",
    "WHISPER_BUILD_EXAMPLES": "ON",
    "WHISPER_BUILD_SERVER": "OFF",
    "WHISPER_CURL": "OFF",
    "WHISPER_COMMON_FFMPEG": "OFF",
    "WHISPER_COREML": "OFF",
    "WHISPER_OPENVINO": "OFF",
    "WHISPER_VITISAI": "OFF",
    "GGML_BACKEND_DL": "OFF",
    "GGML_CPU": "ON",
    "GGML_NATIVE": "OFF",
    "GGML_CPU_KLEIDIAI": "OFF",
    "GGML_OPENMP": "OFF",
    "GGML_OPENMP_FETCH": "OFF",
    "GGML_ACCELERATE": "OFF",
    "GGML_BLAS": "OFF",
    "GGML_RPC": "OFF",
    "GGML_CUDA": "OFF",
    "GGML_HIP": "OFF",
    "GGML_MUSA": "OFF",
    "GGML_METAL": "OFF",
    "GGML_VULKAN": "OFF",
    "GGML_OPENCL": "OFF",
    "GGML_SYCL": "OFF",
    "GGML_WEBGPU": "OFF",
    "GGML_OPENVINO": "OFF",
    "GGML_HEXAGON": "OFF",
}


def sha256(path):
    result = hashlib.sha256()
    with Path(path).open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def verify_file(path, expected_hash, expected_bytes):
    if path.stat().st_size != expected_bytes or sha256(path) != expected_hash:
        raise ValueError(f"Integrity mismatch: {path}. Preserve/remove it manually before retrying.")


def download_model(path):
    if path.exists():
        verify_file(path, MODEL_SHA256, MODEL_BYTES)
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".model-", dir=path.parent)
    temporary = Path(temporary)
    try:
        request = urllib.request.Request(MODEL_URL, headers={"User-Agent": "STRATHVISION-local-transcriber-setup/1"})
        with os.fdopen(fd, "wb") as output, urllib.request.urlopen(request, timeout=120) as response:
            received = 0
            while chunk := response.read(1024 * 1024):
                received += len(chunk)
                if received > MODEL_BYTES:
                    raise ValueError("Model response exceeded the pinned size")
                output.write(chunk)
        verify_file(temporary, MODEL_SHA256, MODEL_BYTES)
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def run(arguments, *, capture=False):
    return subprocess.run(arguments, check=True, text=True, capture_output=capture)


def prepare_source(source):
    if not source.exists():
        run(["git", "init", str(source)])
        run(["git", "-C", str(source), "fetch", "--depth", "1", SOURCE_URL, SOURCE_COMMIT])
        run(["git", "-C", str(source), "checkout", "--detach", "FETCH_HEAD"])
    if not (source / ".git").is_dir():
        raise ValueError(f"Source directory is not the expected Git checkout: {source}")
    commit = run(["git", "-C", str(source), "rev-parse", "HEAD"], capture=True).stdout.strip()
    if commit != SOURCE_COMMIT:
        raise ValueError("Existing source is not the pinned commit; use a fresh destination")
    run(["git", "-C", str(source), "diff", "--exit-code", "HEAD", "--"])


def write_json(path, data):
    fd, temporary = tempfile.mkstemp(prefix=".manifest-", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as output:
            json.dump(data, output, indent=2)
            output.write("\n")
        Path(temporary).replace(path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def install(destination, jobs):
    for command in ("git", "cmake"):
        if not shutil.which(command):
            raise ValueError(f"Install {command} and a C/C++ compiler before running setup")
    destination = destination.expanduser().resolve()
    destination.mkdir(parents=True, exist_ok=True)
    source = destination / "source"
    build = destination / "build"
    prepare_source(source)
    run(["cmake", "-S", str(source), "-B", str(build),
         *[f"-D{key}={value}" for key, value in CMAKE_OPTIONS.items()]])
    run(["cmake", "--build", str(build), "--config", "Release", "--target", "whisper-cli", "--parallel", str(jobs)])
    name = "whisper-cli.exe" if os.name == "nt" else "whisper-cli"
    candidates = [build / "bin" / "Release" / name, build / "bin" / name]
    executable = next((path for path in candidates if path.is_file()), None)
    if executable is None:
        raise ValueError("Build completed without the expected whisper-cli executable")
    version = run([str(executable), "--version"], capture=True).stdout.strip()
    if version != f"whisper.cpp version: {VERSION}":
        raise ValueError(f"Unexpected runtime version: {version}")
    model = destination / "models" / "ggml-base.bin"
    print(f"Downloading/verifying pinned multilingual model ({MODEL_BYTES} bytes)", flush=True)
    download_model(model)
    licenses = destination / "licenses"
    licenses.mkdir(exist_ok=True)
    shutil.copyfile(source / "LICENSE", licenses / "whisper.cpp-MIT.txt")
    shutil.copyfile(Path(__file__).with_name("MODEL-LICENSE.txt"), licenses / "Whisper-model-MIT.txt")
    manifest = {
        "format": "local-transcriber/1",
        "engine": "whisper.cpp",
        "version": VERSION,
        "source_commit": SOURCE_COMMIT,
        "source_url": SOURCE_URL,
        "executable": str(executable),
        "executable_sha256": sha256(executable),
        "model": str(model),
        "model_name": "ggml-base.bin",
        "model_revision": MODEL_REVISION,
        "model_url": MODEL_URL,
        "model_sha256": MODEL_SHA256,
        "model_bytes": MODEL_BYTES,
        "runtime_license": "MIT",
        "model_license": "MIT",
        "platform": platform.system(),
        "architecture": platform.machine(),
        "cmake_options": CMAKE_OPTIONS,
        "sample_audio": str(source / "samples" / "jfk.wav"),
    }
    config = destination / "transcriber.json"
    write_json(config, manifest)
    print(f"Ready. Choose this configuration in STRATHVISION: {config}")
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--destination", type=Path, required=True, help="User-chosen local installation directory")
    parser.add_argument("--jobs", type=int, default=min(4, os.cpu_count() or 1))
    args = parser.parse_args()
    if not 1 <= args.jobs <= 64:
        parser.error("--jobs must be between 1 and 64")
    try:
        install(args.destination, args.jobs)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"Setup failed: {error}\nNo app configuration was selected automatically.\n")


if __name__ == "__main__":
    main()
