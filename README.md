# Unified AI Life Manager (UAILM)

An intelligent personal assistant that automatically extracts tasks, 
deadlines, and commitments from your emails and messages using 
**fully local AI** — no cloud APIs, no data leaves your device.

## Tech Stack
- **Frontend:** Flutter (Android/iOS/Web)
- **Backend:** FastAPI (Python)
- **AI:** Ollama + qwen2.5:3b (runs locally)
- **Database:** SQLite (dev) → PostgreSQL (prod)

## Features
- AI-powered task extraction from emails & messages
- Conversational chat interface
- Smart scheduling & prioritization
- 100% private — all AI runs on your device

## Setup

### Prerequisites
- Python 3.11+
- Flutter 3.x+
- Ollama (https://ollama.com)

### Backend Setup
```bash
cd backend
python -m venv venv
venv\Scripts\activate        # Windows
source venv/bin/activate     # Mac/Linux
pip install -r requirements.txt
cp .env.example .env
uvicorn app.main:app --reload
```

### AI Setup
```bash
ollama pull qwen2.5:3b
ollama serve
```

### Flutter Setup
```bash
cd frontend
flutter pub get
flutter run
```

## Project Structure