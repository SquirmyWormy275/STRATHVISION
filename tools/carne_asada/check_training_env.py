"""Optional dependency smoke: synthetic inputs only, no downloads or accuracy claims.

Run after installing requirements-training.txt into a fresh environment.
"""
import argparse
import json
from pathlib import Path
import tempfile
from unittest.mock import patch

import torch
import torchvision
from torchvision.models.detection import fasterrcnn_resnet50_fpn_v2

import axe_faster
import axe_transfer
import barbell_detector


def untrained_faster(**kwargs):
    # Exercise the real research builders without downloading COCO weights.
    kwargs.update(weights=None, weights_backbone=None)
    return fasterrcnn_resnet50_fpn_v2(**kwargs)


def check(device):
    torch.manual_seed(365)
    torch.set_num_threads(2)
    if device == 'cuda' and not torch.cuda.is_available():
        raise RuntimeError('CUDA was requested but is unavailable')
    results = {}
    with tempfile.TemporaryDirectory() as directory:
        parent = Path(directory)
        for name, module in [('axe', axe_faster), ('barbell', barbell_detector), ('ssdlite', axe_transfer)]:
            if name == 'ssdlite':
                model = module.build(False)
            else:
                with patch.object(module, 'fasterrcnn_resnet50_fpn_v2', side_effect=untrained_faster):
                    model = module.build(parent)
                # Same operators and parameter shapes, smaller synthetic spatial workload.
                model.transform.min_size = (128,)
                model.transform.max_size = 128
            model.to(device).train()
            model.backbone.eval()
            images = [torch.rand(3, 128, 128, device=device) for _ in range(2)]
            targets = [{'boxes': torch.tensor([[20., 20., 80., 90.]], device=device),
                        'labels': torch.ones(1, dtype=torch.int64, device=device)} for _ in images]
            losses = model(images, targets)
            loss = sum(losses.values())
            if not torch.isfinite(loss):
                raise ValueError(f'{name}: nonfinite synthetic loss')
            loss.backward()
            gradients = [p.grad for p in model.parameters() if p.grad is not None]
            if not gradients or any(not torch.isfinite(g).all() for g in gradients):
                raise ValueError(f'{name}: missing or nonfinite gradient')
            optimizer = torch.optim.SGD([p for p in model.parameters() if p.requires_grad], lr=.0001)
            optimizer.step()
            model.eval()
            with torch.inference_mode():
                prediction = model(images[:1])[0]
            if prediction['boxes'].shape[1] != 4 or not torch.isfinite(prediction['boxes']).all():
                raise ValueError(f'{name}: invalid predicted boxes')
            weights = parent / f'{name}.pt'
            torch.save(model.state_dict(), weights)
            model.load_state_dict(torch.load(weights, map_location=device, weights_only=True))
            results[name] = {'finite_loss': float(loss.detach()), 'boxes': len(prediction['boxes']),
                             'backward_optimizer_and_weights_roundtrip': True}
            del model, optimizer, images, targets, losses, loss, prediction, gradients
            if device == 'cuda':
                torch.cuda.empty_cache()
    return {'torch': torch.__version__, 'torchvision': torchvision.__version__,
            'device': device, 'synthetic_only': True, 'models': results}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', choices=['cpu', 'cuda'], default='cpu')
    print(json.dumps(check(parser.parse_args().device), indent=2))
