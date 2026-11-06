# Local footage datasets

Inventory originals before choosing or fitting a model. This sport-agnostic tooling uses only Python's standard library, Linux/POSIX filesystem calls, `findmnt` and `ffprobe`.

1. Follow the [inventory walkthrough and schema](../../docs/DATASETS.md).
2. Inspect [the observed Seagate run](../../docs/experiments/Inventory-20261106.md).
3. Review source/session provenance, freeze a split and validate it before research.

`inventory.py` reads originals and writes private manifests outside their tree. `splits.py` joins related sources, quarantines unknown provenance and rejects split leakage. Neither command trains a model or changes the app.

From the repository root:

```sh
python3 -m unittest discover -s tools/datasets -v
```

`ffmpeg` is needed for the generated audiovisual integration test. The remaining tests use no private footage.
