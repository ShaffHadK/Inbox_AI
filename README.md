# 🧠 Inbox AI: Reclaim Your Focus

> **An intelligent, privacy-first email assistant that categorizes, summarizes, and drafts replies in seconds.**

---

## 🌐 Live Demo
👉 **[Launch Inbox AI](https://shaffhadk.github.io/Inbox_AI/)**

*(Note: The live demo requires the backend server to be hosted publicly via Render which may take a minute to startup.)*

---

## 🧐 The Problem
Professionals spend up to **28% of their workweek** managing email. The modern inbox is a chaotic mix of critical business tasks, newsletters, and promotional spam. This "digital noise" kills focus and increases the risk of missing high-priority communication.

## 💡 The Solution
**Inbox AI** is an end-to-end intelligent pipeline that acts as a gatekeeper for your inbox.
1.  **Smart Triage:** Instantly filters emails into Business, Personal, Promotional, and Spam.
2.  **AI Summaries:** Condenses long threads into single-sentence actionable insights.
3.  **Instant Replies:** Drafts professional, context-aware replies based on short user intents.
4.  **Privacy Focused:** Your data is processed securely, with options for self-hosted AI execution.

---

## 🤖 AI Architecture & Models

We utilize a **Hybrid AI Strategy** to balance performance, cost, and accuracy.

### 1. Production Deployment (Current)
For this hackathon deployment, we utilize **Google Gemini 2.5 Flash-lite**.
* **Why:** It offers extremely low latency, massive context windows (for long threads), and multimodal capabilities, making it ideal for a responsive web dashboard.

### 2. Custom Research Model (DistilBERT)
We have also architected a fully self-hosted classification pipeline using a fine-tuned **DistilBERT** model. This demonstrates our ability to build specialized, small-footprint models for privacy-critical environments where data cannot leave the premise.

* **Model Architecture:** DistilBERT (Knowledge Distillation)
* **Training Data:** Fine-tuned on the Enron Email Dataset + Custom Promotional Corpus.
* **Hugging Face Repo:** [**View our Custom DistilBERT Model**](https://huggingface.co/Shaffhad/distilbert-email-classifier)

---

## 🛠️ Tech Stack

| Component | Technology | Description |
| :--- | :--- | :--- |
| **Frontend** | **Flutter (Web)** | A responsive, glassmorphic UI with Markdown rendering and real-time updates. |
| **Backend** | **FastAPI (Python)** | Asynchronous server handling Gmail API polling, AI processing, and Firestore syncing. |
| **Database** | **Firebase Firestore** | Real-time NoSQL database for storing email metadata and AI summaries. |
| **Auth** | **Firebase Auth** | Secure Google Sign-In with OAuth 2.0 credential management. |
| **AI Engine** | **Gemini 2.5 Flash-lite** | Handling classification, summarization, and RAG-based reply generation. |

---

## 🚀 Local Installation Guide

Follow these steps to run the full stack locally.

### Prerequisites
* Flutter SDK
* Python 3.9+
* Google Cloud Project (Gmail API enabled)
* Firebase Project

### 1. Clone the Repository
```bash
git clone [https://github.com/Shaffhadk/Inbox_AI.git](https://github.com/Shaffhadk/Inbox_AI.git)
cd Inbox_AI
```

### 2. Backend Setup
* Navigate to the backend folder and install dependencies.
```bash
cd backend
pip install -r requirements.txt
```

**Configuration Secrets:** You must create a firebase_credentials.json file in the backend/ folder containing your Firebase Admin SDK keys. Update main.py with your Gemini API Key.

**Run the Server:**
```bash
uvicorn main:app --reload --host 0.0.0.0
```

### 3. Frontend Setup
* Navigate to the frontend folder
```bash
cd frontend
flutter pub get
```
**Configuration:** Ensure frontend/lib/main.dart points to your backend URL (e.g., http://localhost:8000/api).
**Run the app:**
```bash
flutter run -d chrome
```

---

### 🗺️ Future Roadmap

1. **Hybrid Switch:** Toggle between Gemini (Cloud) and DistilBERT (Local) in settings.

2. **Calendar Agent:** Auto-detect meeting times and add to Google Calendar.

3.  **Voice Mode:** Listen to email summaries while driving.

4.  **Multi-Language:** Automatic translation and reply in native languages.

<p align="center"> Made with ❤️ by ShaffHad </p>

