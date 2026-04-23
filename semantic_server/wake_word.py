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

print("Listening for 'hey jarvis'...")

while True:
    audio_data = stream.read(1280, exception_on_overflow=False)
    audio_np = np.frombuffer(audio_data, dtype=np.int16)

    prediction = model.predict(audio_np)

    if prediction.get("hey_jarvis", 0) > 0.5:
        print("Wake word detected!")
