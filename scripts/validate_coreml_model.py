from __future__ import annotations

import pathlib
import sys


ROOT = pathlib.Path(__file__).resolve().parents[1]
MODEL_CANDIDATES = [
    ROOT / "packages" / "artcnn_player_ios" / "ios" / "Resources" / "ArtCNN_C4F16.mlmodel",
    ROOT / "packages" / "artcnn_player_ios" / "ios" / "Resources" / "ArtCNN_C4F16.mlmodelc",
]
ONNX_CANDIDATE = ROOT / "ArtCNN_C4F16_DN.onnx"


def main() -> int:
    existing = [path for path in MODEL_CANDIDATES if path.exists()]
    if not existing:
        if ONNX_CANDIDATE.exists():
            try:
                import onnx
            except ImportError:
                print("onnx is required when only the ONNX ArtCNN model is present.", file=sys.stderr)
                return 1
            model = onnx.load(str(ONNX_CANDIDATE))
            onnx.checker.check_model(model)
            print(f"Validated ONNX model: {ONNX_CANDIDATE}")
            return 0
        print("ArtCNN_C4F16 model not found; skipping model validation for this scaffold.")
        return 0

    try:
        import coremltools as ct
    except ImportError:
        print("coremltools is required when an ArtCNN model is present.", file=sys.stderr)
        return 1

    for model_path in existing:
        print(f"Validating {model_path}")
        if model_path.suffix == ".mlmodel":
            model = ct.models.MLModel(str(model_path), compute_units=ct.ComputeUnit.CPU_ONLY)
            spec = model.get_spec()
            if not spec.description.input:
                print("Model has no inputs.", file=sys.stderr)
                return 1
            if not spec.description.output:
                print("Model has no outputs.", file=sys.stderr)
                return 1
            print(f"Inputs: {[item.name for item in spec.description.input]}")
            print(f"Outputs: {[item.name for item in spec.description.output]}")
        else:
            if not model_path.is_dir():
                print(f"{model_path} must be a compiled model directory.", file=sys.stderr)
                return 1
            print("Compiled model directory exists.")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
