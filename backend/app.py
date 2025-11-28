import os
import json
import base64
import asyncio
import tempfile
import concurrent.futures
import re
from typing import List, Optional
from enum import Enum
from datetime import datetime
from email.mime.text import MIMEText

# FastAPI & Pydantic
from fastapi import FastAPI, HTTPException, Request, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

# Google & Firebase
import google.generativeai as genai
from google.oauth2.credentials import Credentials
from googleapiclient.discovery import build
import firebase_admin
from firebase_admin import credentials, firestore


GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "").strip()
GEMINI_MODEL_NAME = os.environ.get("GEMINI_MODEL_NAME", "gemini-2.5-flash-lite").strip()
FIREBASE_CREDS_ENV = os.environ.get("FIREBASE_CREDS")  # full JSON string

_genai_configured = False
_model = None  # will hold genai.GenerativeModel once initialized

def init_gemini():
    """
    Lazy initialize Gemini model. Returns the model object or None.
    """
    global _genai_configured, _model
    if _genai_configured:
        return _model
    _genai_configured = True  # ensure we only try once
    if not GEMINI_API_KEY:
        print("[WARN] GEMINI_API_KEY not set — Gemini features will be disabled.")
        _model = None
        return None
    try:
        genai.configure(api_key=GEMINI_API_KEY)
        # Create GenerativeModel lazily
        _model = genai.GenerativeModel(GEMINI_MODEL_NAME)
        print(f"[INFO] Gemini initialized with model: {GEMINI_MODEL_NAME}")
        return _model
    except Exception as e:
        print(f"[WARN] Failed to initialize Gemini model '{GEMINI_MODEL_NAME}': {e}")
        _model = None
        return None

# --- FIREBASE Initialization (safe) ---
db = None

def init_firebase():
    global db
    if firebase_admin._apps:
        db = firestore.client()
        print("[INFO] Firebase already initialized in this process.")
        return

    FIREBASE_CREDS_ENV = os.environ.get("FIREBASE_CREDS")
    if FIREBASE_CREDS_ENV:
        try:
            # Write JSON string to a temp file
            with tempfile.NamedTemporaryFile(delete=False, mode="w", suffix=".json") as f:
                f.write(FIREBASE_CREDS_ENV)
                temp_path = f.name

            cred = credentials.Certificate(temp_path)
            firebase_admin.initialize_app(cred)
            db = firestore.client()
            print("[INFO] Firebase initialized from FIREBASE_CREDS env var.")
            return
        except Exception as e:
            print(f"[WARN] Failed to initialize Firebase from FIREBASE_CREDS: {e}")

    # Fallback: default ADC
    try:
        firebase_admin.initialize_app()
        db = firestore.client()
        print("[INFO] Firebase initialized with default credentials.")
    except Exception as e:
        print(f"[WARN] Firebase default initialization failed: {e}")
        db = None


# initialize at import 
init_firebase()

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- MODELS ---
class EmailCategory(str, Enum):
    BUSINESS = "Business"
    PERSONAL = "Personal"
    PROMOTIONAL = "Promotional"
    SPAM = "Spam"

class ReplyRequest(BaseModel):
    email_content: str
    intent: str
    sender_name: str

class SendEmailRequest(BaseModel):
    token: str
    threadId: str
    to: str
    subject: str
    body: str

class AuthToken(BaseModel):
    token: str
    

# --- HELPER FUNCTIONS ---

def clean_email_text(text: str) -> str:
    """
    Smart cleaning that preserves structure (paragraphs) while removing noise.
    """
    if not text:
        return ""
    
    # 1. Handle HTML Line Breaks (Convert to real newlines)
    text = re.sub(r'<br\s*/?>', '\n', text, flags=re.IGNORECASE)
    text = re.sub(r'</p>', '\n\n', text, flags=re.IGNORECASE)
    text = re.sub(r'</div>', '\n', text, flags=re.IGNORECASE)
    
    # 2. Remove remaining HTML Tags
    text = re.sub(r'<[^>]+>', ' ', text)
    
    # 3. Remove URLs (http://..., https://..., www...)
    text = re.sub(r'http\S+', '[Link]', text)
    text = re.sub(r'www\.\S+', '[Link]', text)
    
    # 4. Remove Image placeholders
    text = re.sub(r'\[image:.*?\]', '', text)
    
    # 5. Fix HTML entities
    text = text.replace('&nbsp;', ' ').replace('&gt;', '>').replace('&lt;', '<').replace('&amp;', '&').replace('&quot;', '"')
    
    # 6. Normalize Whitespace (The important part for paragraphs!)
    # Replace multiple horizontal spaces/tabs with a single space
    text = re.sub(r'[ \t]+', ' ', text)
    # Replace 3+ newlines with 2 newlines (to keep max 1 empty line between paragraphs)
    text = re.sub(r'\n\s*\n', '\n\n', text)
    
    return text.strip()

def classify_email_gemini(text: str) -> EmailCategory:
    try:
        # ensure model initialized
        m = _model if _model else init_gemini()
        if m is None:
            # fallback heuristic when Gemini unavailable
            if "unsubscribe" in text.lower():
                return EmailCategory.PROMOTIONAL
            return EmailCategory.BUSINESS

        prompt = f"""
        Analyze this email and classify it into exactly one category based on these strict rules:
        
        1. Business: Work-related, job applications, invoices, receipts, professional scheduling, transactional emails.
        2. Personal: Direct messages from friends/family, casual conversation.
        3. Promotional: Newsletters, marketing, sales offers, discounts.
        4. Spam: Phishing, obvious junk.

        Return ONLY the category word. Do not explain.
        
        Email Content:
        {text[:1500]}
        """
        
        safety_settings = [
            {"category": "HARM_CATEGORY_HARASSMENT", "threshold": "BLOCK_NONE"},
            {"category": "HARM_CATEGORY_HATE_SPEECH", "threshold": "BLOCK_NONE"},
            {"category": "HARM_CATEGORY_SEXUALLY_EXPLICIT", "threshold": "BLOCK_NONE"},
            {"category": "HARM_CATEGORY_DANGEROUS_CONTENT", "threshold": "BLOCK_NONE"},
        ]

        response = m.generate_content(prompt, safety_settings=safety_settings)
        
        category_text = response.text.strip().replace(".", "").replace("\n", "").replace("*", "").split(" ")[0]
        
        for cat in EmailCategory:
            if cat.value.lower() in category_text.lower(): 
                return cat
        
        if "unsubscribe" in text.lower() and "order" not in text.lower() and "invoice" not in text.lower():
             return EmailCategory.PROMOTIONAL
             
        return EmailCategory.BUSINESS 
    except Exception as e:
        print(f"Classification Error: {e}")
        return EmailCategory.PROMOTIONAL

def summarize_email_gemini(text: str) -> str:
    # ensure model initialized
    m = _model if _model else init_gemini()
    prompt = f"""
    You are an assistant that extracts a single factual summary from an email.
    Return a one-line summary (<= 20 words) that focuses on the main action or request in the email.
    Then, optionally on the next line, include 'Action:' followed by a one-line suggestion for the user's next step (<= 20 words).
    Do not add anything else.

    Email:
    {clean_email_text(text)[:3000]}
    """
    try:
        safety_settings = [
            {"category": "HARM_CATEGORY_HARASSMENT", "threshold": "BLOCK_NONE"},
            {"category": "HARM_CATEGORY_HATE_SPEECH", "threshold": "BLOCK_NONE"},
            {"category": "HARM_CATEGORY_SEXUALLY_EXPLICIT", "threshold": "BLOCK_NONE"},
            {"category": "HARM_CATEGORY_DANGEROUS_CONTENT", "threshold": "BLOCK_NONE"},
        ]
        if m is None:
            # fallback short summary
            return (clean_email_text(text)[:180] + "...") if text else "No summary available."
        response = m.generate_content(prompt, safety_settings=safety_settings)
        return response.text.strip()
    except Exception as e:
        print(f"[WARN] summarize failed: {e}")
        return (clean_email_text(text)[:180] + "...") if text else "No summary available."


def fetch_gmail_content_only(auth_token_str, msg_id):
    """
    SAFE THREADING: Creates a NEW service object for this specific thread.
    Fetches content and cleans it immediately.
    """
    try:
        creds = Credentials(token=auth_token_str)
        thread_service = build('gmail', 'v1', credentials=creds, cache_discovery=False)

        full_msg = thread_service.users().messages().get(userId='me', id=msg_id).execute()
        
        headers = full_msg['payload']['headers']
        subject = next((h['value'] for h in headers if h['name'] == 'Subject'), '(No Subject)')
        sender = next((h['value'] for h in headers if h['name'] == 'From'), 'Unknown')
        
        body = full_msg['snippet'] # Start with snippet (which is usually plain text)
        
        # Try to find the actual body content
        if 'parts' in full_msg['payload']:
            for part in full_msg['payload']['parts']:
                if part['mimeType'] == 'text/plain':
                    data = part['body'].get('data')
                    if data:
                        raw_body = base64.urlsafe_b64decode(data).decode()
                        # Clean the body immediately here!
                        body = clean_email_text(raw_body)
                        break
        
        try:
            thread_service.close()
        except Exception:
            pass

        return {
            'id': msg_id,
            'threadId': full_msg['threadId'],
            'sender': sender,
            'subject': subject,
            'snippet': full_msg['snippet'],
            'body': body, # This is now the CLEANED body
            'timestamp': int(full_msg['internalDate']),
            'processed': False,
            'category': 'Processing...',
            'summary': 'Generating AI summary...'
        }
    except Exception as e:
        print(f"Gmail Fetch Error {msg_id}: {e}")
        return None

async def process_email_ai_task(user_id: str, email_data: dict):
    """Background AI processing."""
    # Body is already cleaned by fetch_gmail_content_only
    full_text = f"Subject: {email_data['subject']}\nSender: {email_data['sender']}\nBody: {email_data['body']}"
    
    category = classify_email_gemini(full_text)
    
    summary = email_data['snippet']
    #if category == EmailCategory.BUSINESS:
    summary = summarize_email_gemini(full_text)

    # safe DB write if firestore initialized
    if db is not None:
        try:
            db.collection('users').document(user_id).collection('emails').document(email_data['id']).update({
                'category': category.value,
                'summary': summary,
                'processed': True
            })
        except Exception as e:
            print(f"[WARN] Firestore update failed for {email_data['id']}: {e}")
    else:
        print("[WARN] Firestore client not initialized; skipping DB update in process_email_ai_task.")

# --- ROUTES --- 

@app.post("/api/sync")
async def sync_emails(auth_token: AuthToken, background_tasks: BackgroundTasks):
    try:
        creds = Credentials(token=auth_token.token)
        service = build('gmail', 'v1', credentials=creds, cache_discovery=False)
        
        profile = service.users().getProfile(userId='me').execute()
        user_id = profile['emailAddress']
        
        user_ref = db.collection('users').document(user_id) if db is not None else None
        if user_ref is not None and not user_ref.get().exists:
            user_ref.set({'email': user_id, 'last_synced': datetime.now()})

        results = service.users().messages().list(userId='me', q="is:unread", maxResults=15).execute()
        messages = results.get('messages', [])

        if not messages:
            return {"status": "success", "synced": 0}

        messages_to_fetch = []
        for msg in messages:
            # If Firestore not initialized, we still fetch and return
            if db is not None:
                doc_ref = db.collection('users').document(user_id).collection('emails').document(msg['id'])
                if not doc_ref.get().exists:
                    messages_to_fetch.append(msg['id'])
            else:
                messages_to_fetch.append(msg['id'])

        if not messages_to_fetch:
            return {"status": "success", "synced": 0}

        new_emails = []
        with concurrent.futures.ThreadPoolExecutor(max_workers=10) as executor:
            futures = [executor.submit(fetch_gmail_content_only, auth_token.token, mid) for mid in messages_to_fetch]
            for future in concurrent.futures.as_completed(futures):
                result = future.result()
                if result:
                    new_emails.append(result)

        if new_emails:
            if db is not None:
                batch = db.batch()
                for email in new_emails:
                    doc_ref = db.collection('users').document(user_id).collection('emails').document(email['id'])
                    batch.set(doc_ref, email)
                    background_tasks.add_task(process_email_ai_task, user_id, email)
                try:
                    batch.commit()
                except Exception as e:
                    print(f"[WARN] Firestore batch commit failed: {e}")
            else:
                # still schedule AI processing tasks (they will skip DB writes)
                for email in new_emails:
                    background_tasks.add_task(process_email_ai_task, user_id, email)

        return {"status": "success", "synced": len(new_emails)}

    except Exception as e:
        print(f"Sync Error: {e}")
        raise HTTPException(status_code=400, detail=str(e))

@app.get("/api/emails/{user_email}")
async def get_emails(user_email: str, category: Optional[str] = None):
    try:
        if db is None:
            # If Firestore not configured, return empty list (safer than crashing)
            return []
        emails_ref = db.collection('users').document(user_email).collection('emails')
        
        if category and category != "All":
            query = emails_ref.where('category', '==', category)
        else:
            query = emails_ref
            
        docs = query.stream()
        results = [doc.to_dict() for doc in docs]
        results.sort(key=lambda x: x.get('timestamp', 0), reverse=True)
        
        return results
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/generate-reply")
async def generate_reply(request: ReplyRequest):
    try:
        if not request.email_content or not request.intent:
            raise HTTPException(status_code=400, detail="Missing content")

        print(f"Generating reply for intent: {request.intent}")

        # ensure gemini model initialized at runtime
        m = _model if _model else init_gemini()
        if m is None:
            raise HTTPException(status_code=503, detail="Gemini not configured or unavailable")

        prompt = f"""
        You are a helpful professional email assistant.
        Task: Draft a reply to an email.
        Sender Name: {request.sender_name}
        User's Intent: {request.intent}
        Original Email Context:
        {request.email_content[:4000]} 
        Guidelines:
        - Keep it professional, concise, and polite.
        - Do NOT include a subject line.
        - Do NOT include placeholders like "[Your Name]". Use "Best regards,".
        """
        
        safety_settings = [
            {"category": "HARM_CATEGORY_HARASSMENT", "threshold": "BLOCK_NONE"},
            {"category": "HARM_CATEGORY_HATE_SPEECH", "threshold": "BLOCK_NONE"},
            {"category": "HARM_CATEGORY_SEXUALLY_EXPLICIT", "threshold": "BLOCK_NONE"},
            {"category": "HARM_CATEGORY_DANGEROUS_CONTENT", "threshold": "BLOCK_NONE"},
        ]
        
        response = m.generate_content(
            prompt,
            safety_settings=safety_settings
        )

        try:
            return {"reply": response.text.strip()}
        except ValueError:
            print(f"⚠️ Gemini Blocked Response: {response.prompt_feedback}")
            return {"reply": "Error: The AI blocked this response due to safety filters. Please try rephrasing."}

    except Exception as e:
        print(f"❌ Generate Reply Error: {e}")
        raise HTTPException(status_code=500, detail=f"Server Error: {str(e)}")

@app.post("/api/send-email")
async def send_email(request: SendEmailRequest):
    try:
        creds = Credentials(token=request.token)
        service = build('gmail', 'v1', credentials=creds, cache_discovery=False)

        message = MIMEText(request.body)
        message['to'] = request.to
        message['subject'] = request.subject
        
        raw_message = base64.urlsafe_b64encode(message.as_bytes()).decode()
        
        sent_message = service.users().messages().send(
            userId="me",
            body={
                'raw': raw_message,
                'threadId': request.threadId 
            }
        ).execute()

        return {"status": "success", "id": sent_message['id']}

    except Exception as e:
        print(f"❌ Send Email Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.delete("/api/emails/{user_email}/{message_id}")
async def delete_email(user_email: str, message_id: str):
    try:
        if db is None:
            raise HTTPException(status_code=500, detail="Firestore not initialized")
        db.collection('users').document(user_email).collection('emails').document(message_id).delete()
        return {"status": "success", "message": "Email deleted from local storage"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
        
if __name__ == "__main__":
    import uvicorn
    port = int(os.environ.get("PORT", 8000))
    uvicorn.run(app, host="0.0.0.0", port=port)
