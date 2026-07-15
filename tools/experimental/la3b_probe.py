#!/usr/bin/env python3
"""LocateAnything-3B probe on Apple Silicon (officially CUDA-only; we try MPS).

Runs the model on sample frames with golf prompts, writes boxes to JSON.
Non-commercial research license — benchmark/comparison use only, never ships.
"""
import json, os, re, sys, time

import torch
from PIL import Image

OUT = os.path.expanduser('~/Documents/TrueCarryTraining/labels/la3b_results.json')
ARCHIVE = os.path.expanduser('~/Documents/TrueCarryFramesArchive_20260712/AllFramesArchive')

FRAMES = [
    ('shot_20260712_112412_627', 17),
    ('shot_20260712_112412_627', 19),
    ('shot_20260711_191402_354', 18),
]


def main():
    from transformers import AutoModel, AutoTokenizer, AutoProcessor
    dev = 'mps' if torch.backends.mps.is_available() else 'cpu'
    dtype = torch.float16 if dev == 'mps' else torch.float32
    print(f'loading on {dev} ({dtype})...', flush=True)
    tok = AutoTokenizer.from_pretrained('nvidia/LocateAnything-3B', trust_remote_code=True)
    proc = AutoProcessor.from_pretrained('nvidia/LocateAnything-3B', trust_remote_code=True)
    model = AutoModel.from_pretrained('nvidia/LocateAnything-3B', torch_dtype=dtype,
                                      trust_remote_code=True).to(dev).eval()
    print('model loaded', flush=True)

    results = []
    for shot, fi in FRAMES:
        img = Image.open(os.path.join(ARCHIVE, shot, f'frame_{fi:03d}.png')).convert('RGB')
        for prompt in ('Locate the golf ball.', 'Locate the golf club head.'):
            t0 = time.time()
            messages = [{'role': 'user', 'content': [
                {'type': 'image', 'image': img},
                {'type': 'text', 'text': prompt}]}]
            text = proc.py_apply_chat_template(messages, tokenize=False, add_generation_prompt=True)
            images, _ = proc.process_vision_info(messages)
            inputs = proc(text=[text], images=images, return_tensors='pt').to(dev)
            with torch.no_grad():
                resp = model.generate(
                    pixel_values=inputs['pixel_values'].to(dtype),
                    input_ids=inputs['input_ids'],
                    attention_mask=inputs['attention_mask'],
                    image_grid_hws=inputs.get('image_grid_hws'),
                    tokenizer=tok, max_new_tokens=512, generation_mode='hybrid')
            ans = resp[0] if isinstance(resp, (tuple, list)) else resp
            boxes = [[int(g) for g in m.groups()]
                     for m in re.finditer(r'<box><(\d+)><(\d+)><(\d+)><(\d+)></box>', str(ans))]
            dt = time.time() - t0
            print(f'{shot} f{fi} "{prompt}" → {boxes} ({dt:.1f}s)', flush=True)
            results.append({'shot': shot, 'fi': fi, 'prompt': prompt,
                            'boxes': boxes, 'raw': str(ans)[:300], 'sec': dt})
            json.dump(results, open(OUT, 'w'), indent=1)
    print('done →', OUT)


if __name__ == '__main__':
    try:
        main()
    except Exception as e:
        json.dump({'error': f'{type(e).__name__}: {e}'}, open(OUT, 'w'))
        print('FAILED:', type(e).__name__, e)
        sys.exit(1)
