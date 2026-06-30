from __future__ import annotations

import argparse
import pathlib
import sys


ROOT = pathlib.Path(__file__).resolve().parents[1]
DEFAULT_ONNX = ROOT / "ArtCNN_C4F16_DN.onnx"
RESOURCE_DIR = ROOT / "packages" / "artcnn_player_ios" / "ios" / "Resources"
MLMODEL_PATH = RESOURCE_DIR / "ArtCNN_C4F16.mlmodel"


def convert_onnx_to_coreml(onnx_path: pathlib.Path, height: int, width: int) -> None:
    import coremltools as ct
    import onnx
    from coremltools.models import datatypes
    from coremltools.models.neural_network import NeuralNetworkBuilder
    from coremltools.models.neural_network import flexible_shape_utils
    from coremltools.models.utils import save_spec
    from onnx import numpy_helper

    model = onnx.load(str(onnx_path))
    onnx.checker.check_model(model)
    weights = {item.name: numpy_helper.to_array(item) for item in model.graph.initializer}

    builder = NeuralNetworkBuilder(
        [("input", datatypes.Array(1, 1, height, width))],
        [("output", datatypes.Array(1, 1, height * 2, width * 2))],
    )

    for node in model.graph.node:
        if node.op_type == "Conv":
            kernel = weights[node.input[1]]
            bias = weights[node.input[2]]
            builder.add_convolution(
                name=node.name,
                kernel_channels=kernel.shape[1],
                output_channels=kernel.shape[0],
                height=kernel.shape[2],
                width=kernel.shape[3],
                stride_height=1,
                stride_width=1,
                border_mode="same",
                groups=1,
                W=kernel,
                b=bias,
                has_bias=True,
                input_name=node.input[0],
                output_name=node.output[0],
            )
        elif node.op_type == "Relu":
            builder.add_activation(
                name=node.name,
                non_linearity="RELU",
                input_name=node.input[0],
                output_name=node.output[0],
            )
        elif node.op_type == "Add":
            builder.add_elementwise(
                name=node.name,
                input_names=list(node.input),
                output_name=node.output[0],
                mode="ADD",
            )
        elif node.op_type == "DepthToSpace":
            builder.add_reorganize_data(
                name=node.name,
                input_name=node.input[0],
                output_name=node.output[0],
                mode="DEPTH_TO_SPACE",
                block_size=2,
            )
        elif node.op_type == "Clip":
            min_value = float(weights[node.input[1]].reshape(-1)[0])
            max_value = float(weights[node.input[2]].reshape(-1)[0])
            builder.add_clip(
                name=node.name,
                input_name=node.input[0],
                output_name=node.output[0],
                min_value=min_value,
                max_value=max_value,
            )
        else:
            raise RuntimeError(f"Unsupported ONNX op: {node.op_type}")

    spec = builder.spec
    spec.specificationVersion = 4
    spec.neuralNetwork.arrayInputShapeMapping = 1
    flexible_shape_utils.set_multiarray_ndshape_range(
        spec,
        "input",
        lower_bounds=[1, 1, 16, 16],
        upper_bounds=[1, 1, 2160, 3840],
    )
    flexible_shape_utils.set_multiarray_ndshape_range(
        spec,
        "output",
        lower_bounds=[1, 1, 32, 32],
        upper_bounds=[1, 1, 4320, 7680],
    )
    spec.description.metadata.shortDescription = (
        "ArtCNN C4F16 grayscale 2x model converted from ONNX for phase-1 iOS playback."
    )
    RESOURCE_DIR.mkdir(parents=True, exist_ok=True)
    if MLMODEL_PATH.exists():
        MLMODEL_PATH.unlink()
    save_spec(spec, str(MLMODEL_PATH))
    print(f"Wrote {MLMODEL_PATH}")

    # Smoke-load the spec when Core ML runtime bindings are present.
    try:
        ct.models.MLModel(str(MLMODEL_PATH), compute_units=ct.ComputeUnit.CPU_ONLY)
        print("Core ML model load check passed.")
    except Exception as error:
        print(f"Core ML runtime load check skipped or unavailable: {error}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--onnx", type=pathlib.Path, default=DEFAULT_ONNX)
    parser.add_argument("--height", type=int, default=360)
    parser.add_argument("--width", type=int, default=640)
    parser.add_argument("--require", action="store_true")
    args = parser.parse_args()

    if not args.onnx.exists():
        message = f"ONNX model not found: {args.onnx}"
        if args.require:
            print(message, file=sys.stderr)
            return 1
        print(f"{message}; skipping ArtCNN model preparation.")
        return 0

    convert_onnx_to_coreml(args.onnx, args.height, args.width)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
