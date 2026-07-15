import tempfile

from fastapi import FastAPI, File, Form, UploadFile
from qwen_asr import Qwen3ASRModel

MODEL_ID = "JacobLinCool/TEA-ASR-1.1-mini"

model = Qwen3ASRModel.from_pretrained(MODEL_ID, device_map="cuda:0", dtype="bfloat16")

app = FastAPI()


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/transcribe")
async def transcribe(file: UploadFile = File(...), language: str = Form("Chinese")):
    with tempfile.NamedTemporaryFile(suffix=".wav") as tmp:
        tmp.write(await file.read())
        tmp.flush()
        result = model.transcribe(audio=tmp.name, language=language)[0]
    return {"text": result.text}


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8000)
