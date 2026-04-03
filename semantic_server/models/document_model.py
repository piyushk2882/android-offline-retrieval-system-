from sentence_transformers import SentenceTransformer

model = SentenceTransformer("all-MiniLM-L6-v2")

def generate_text_embedding(text_chunks):

    embeddings = model.encode(text_chunks)

    return embeddings.tolist()