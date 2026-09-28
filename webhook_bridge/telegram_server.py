from flask import Flask, request, jsonify
import requests
import os
from dotenv import load_dotenv

load_dotenv()  # Load environment variables from .env file

app = Flask(__name__)

# ==========================================
# CONFIGURATION - LOADED FROM .ENV
# ==========================================
TELEGRAM_BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN", "YOUR_TELEGRAM_BOT_TOKEN_HERE")
TELEGRAM_CHAT_ID = os.getenv("TELEGRAM_CHAT_ID", "YOUR_CHAT_ID_HERE")
# ==========================================

TELEGRAM_API_URL = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage"

@app.route('/webhook', methods=['POST'])
def webhook():
    try:
        # Get JSON data from MT5
        data = request.json
        if not data:
            return jsonify({"status": "error", "message": "No JSON data provided"}), 400

        # Construct message
        message = data.get("message", "🔔 KNARES Alert")
        
        # Add formatting if available
        if "symbol" in data:
            action = data.get("action", "INFO")
            profit = data.get("profit", "")
            
            formatted_msg = f"*{action} | {data['symbol']}*\n"
            formatted_msg += f"Message: {message}\n"
            
            if profit:
                formatted_msg += f"Profit: {profit}\n"
            
            message = formatted_msg

        # Send to Telegram
        payload = {
            "chat_id": TELEGRAM_CHAT_ID,
            "text": message,
            "parse_mode": "Markdown"
        }
        
        if TELEGRAM_BOT_TOKEN != "YOUR_TELEGRAM_BOT_TOKEN_HERE":
            response = requests.post(TELEGRAM_API_URL, json=payload)
            response.raise_for_status()
            print(f"[SUCCESS] Sent to Telegram: {message}")
        else:
            print(f"[TEST MODE - NO TOKEN] Received webhook: {message}")

        return jsonify({"status": "success"}), 200

    except Exception as e:
        print(f"[ERROR] Webhook processing failed: {e}")
        return jsonify({"status": "error", "message": str(e)}), 500

if __name__ == '__main__':
    print("Starting KNARES Telegram Webhook Bridge on port 5000...")
    print("Make sure MT5 'Allow WebRequest' is enabled for http://127.0.0.1:5000")
    app.run(host='127.0.0.1', port=5000)
