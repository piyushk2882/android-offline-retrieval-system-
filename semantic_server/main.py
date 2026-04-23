from fastapi import FastAPI, UploadFile, File
from typing import List
import shutil
import os
import uuid
import torch
from models.clip_model import generate_image_embedding, generate_text_embedding_clip
from models.text_model import generate_text_embedding
from sentence_transformers import SentenceTransformer
from processors.pdf_reader import extract_pdf_text
from processors.doc_reader import extract_doc_text
from processors.ppt_reader import extract_ppt_text

from fastapi import UploadFile
import tempfile
import os

from utils.document_extractor import (
    extract_text_from_pdf,
    extract_text_from_docx,
    extract_text_from_pptx
)

from utils.chunker import chunk_text
from models.document_model import generate_text_embedding

torch.set_num_threads(4)
doc_model = SentenceTransformer("all-MiniLM-L6-v2")

app = FastAPI()

UPLOAD_DIR = "temp_files"
os.makedirs(UPLOAD_DIR, exist_ok=True)

import threading

wake_triggered = False

def wake_listener():
    global wake_triggered
    try:
        from openwakeword.model import Model
        import pyaudio
        import numpy as np

        model = Model(wakeword_models=["hey_jarvis"])

        audio = pyaudio.PyAudio()
        stream = audio.open(
            format=pyaudio.paInt16,
            channels=1,
            rate=16000,
            input=True,
            frames_per_buffer=1280
        )
        print("Live wake word listener running... (say 'hey jarvis')")
        
        while True:
            data = stream.read(1280, exception_on_overflow=False)
            audio_np = np.frombuffer(data, dtype=np.int16)
            pred = model.predict(audio_np)
            if pred.get("hey_jarvis", 0) > 0.5:
                wake_triggered = True
    except Exception as e:
        print(f"Failed to start wake listener: {e}")

@app.on_event("startup")
def start_listener():
    threading.Thread(target=wake_listener, daemon=True).start()

@app.get("/wake_status")
def get_wake_status():
    global wake_triggered
    if wake_triggered:
        wake_triggered = False
        return {"wake": True}
    return {"wake": False}

@app.get("/health")
def health_check():
    return {"status": "server running"}

@app.get("/embed_text_doc")
def embed_text_doc(text: str):

    embedding = doc_model.encode(text)

    return {"embedding": embedding.tolist()}


@app.post("/embed_image")
async def embed_image(file: UploadFile = File(...)):

    filename = f"{uuid.uuid4()}_{file.filename}"
    path = f"{UPLOAD_DIR}/{filename}"

    with open(path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)

    try:
        embedding = generate_image_embedding(path)

        embedding = embedding.astype("float16")
    finally:
        os.remove(path)

    return {"embedding": embedding.tolist()}


@app.post("/embed_text")
async def embed_text(text: str):

    embedding = generate_text_embedding_clip(text)

    embedding = embedding.astype("float16")

    return {"embedding": embedding.tolist()}


@app.post("/embed_document")
async def embed_document(file: UploadFile = File(...)):

    contents = await file.read()
    filename = file.filename.lower()

    # Save to a temp file since extractors need file paths
    temp_path = os.path.join(UPLOAD_DIR, f"{uuid.uuid4()}_{file.filename}")
    with open(temp_path, "wb") as f:
        f.write(contents)

    try:
        if filename.endswith(".pdf"):
            text = extract_text_from_pdf(temp_path)
        elif filename.endswith(".docx"):
            text = extract_text_from_docx(temp_path)
        elif filename.endswith(".pptx"):
            text = extract_text_from_pptx(temp_path)
        elif filename.endswith(".txt"):
            text = contents.decode("utf-8", errors="ignore")
        else:
            return {"chunks": [], "embeddings": []}

        chunks = chunk_text(text)

        if not chunks:
            return {"chunks": [], "embeddings": []}

        embeddings = doc_model.encode(chunks)

        return {
            "chunks": chunks,
            "embeddings": embeddings.tolist()
        }
    except Exception as e:
        print(f"Error processing document {filename}: {e}")
        return {"chunks": [], "embeddings": []}
    finally:
        if os.path.exists(temp_path):
            os.remove(temp_path)


@app.post("/embed_images_batch")
async def embed_images_batch(files: List[UploadFile] = File(...)):

    embeddings = []

    for file in files:

        path = f"{UPLOAD_DIR}/{file.filename}"

        with open(path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)

        try:
            embedding = generate_image_embedding(path)

            embedding = embedding.astype("float16")

            embeddings.append(embedding.tolist())
        except Exception as e:
            print(f"Error processing image {file.filename}: {e}")
            embeddings.append([0.0] * 512)
        finally:
            if os.path.exists(path):
                os.remove(path)

    return {"embeddings": embeddings}