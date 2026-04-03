import os
os.environ["HF_HUB_OFFLINE"] = "0"

import torch
import open_clip
from PIL import Image
import numpy as np
from pillow_heif import register_heif_opener

register_heif_opener()

device = "cuda" if torch.cuda.is_available() else "cpu"

model, preprocess, tokenizer = open_clip.create_model_and_transforms(
    "ViT-B-32",
    pretrained="openai"
)

tokenizer = open_clip.get_tokenizer("ViT-B-32")

model = model.to(device)
model.eval()

def generate_image_embedding(image_path):

    image = preprocess(Image.open(image_path)).unsqueeze(0).to(device)

    with torch.no_grad():
        embedding = model.encode_image(image)

    embedding = embedding / embedding.norm(dim=-1, keepdim=True)

    return embedding.squeeze().cpu().numpy()

def generate_text_embedding_clip(text):

    tokens = tokenizer([text]).to(device)

    with torch.no_grad():
        embedding = model.encode_text(tokens)

    embedding = embedding / embedding.norm(dim=-1, keepdim=True)

    return embedding.squeeze().cpu().numpy()