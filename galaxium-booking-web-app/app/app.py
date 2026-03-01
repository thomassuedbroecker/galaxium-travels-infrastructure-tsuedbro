from flask import Flask, render_template, request, Response, jsonify
from flask_cors import CORS
import requests
import json
import os
import time

BACKEND_URL = os.getenv('BACKEND_URL')
OAUTH2_ENABLED = os.getenv('OAUTH2_ENABLED', 'false').lower() in {"1", "true", "yes", "on"}
OIDC_TOKEN_URL = os.getenv('OIDC_TOKEN_URL')
OIDC_CLIENT_ID = os.getenv('OIDC_CLIENT_ID')
OIDC_CLIENT_SECRET = os.getenv('OIDC_CLIENT_SECRET')
OIDC_SCOPE = os.getenv('OIDC_SCOPE', '').strip()

TOKEN_CACHE = {
    "access_token": None,
    "expires_at_epoch": 0,
}

app = Flask(__name__, static_folder="static", template_folder="templates")

# Enable CORS for all routes and origins
# send_wildcard True will send Access-Control-Allow-Origin: *
CORS(app, resources={r"/*": {"origins": "*"}}, send_wildcard=True)

def validate_oauth2_settings():
    if not OAUTH2_ENABLED:
        return
    missing = []
    if not OIDC_TOKEN_URL:
        missing.append("OIDC_TOKEN_URL")
    if not OIDC_CLIENT_ID:
        missing.append("OIDC_CLIENT_ID")
    if not OIDC_CLIENT_SECRET:
        missing.append("OIDC_CLIENT_SECRET")
    if missing:
        raise RuntimeError(
            f"OAUTH2_ENABLED=true but missing settings: {', '.join(missing)}"
        )

def get_access_token():
    if not OAUTH2_ENABLED:
        return None

    now = int(time.time())
    if TOKEN_CACHE["access_token"] and now < (TOKEN_CACHE["expires_at_epoch"] - 20):
        return TOKEN_CACHE["access_token"]

    data = {
        "grant_type": "client_credentials",
        "client_id": OIDC_CLIENT_ID,
        "client_secret": OIDC_CLIENT_SECRET,
    }
    if OIDC_SCOPE:
        data["scope"] = OIDC_SCOPE

    response = requests.post(OIDC_TOKEN_URL, data=data, timeout=10)
    response.raise_for_status()
    token_payload = response.json()
    token = token_payload.get("access_token")
    if not token:
        raise RuntimeError("Token endpoint did not return an access_token")

    expires_in = int(token_payload.get("expires_in", 60))
    TOKEN_CACHE["access_token"] = token
    TOKEN_CACHE["expires_at_epoch"] = now + expires_in
    return token

validate_oauth2_settings()

# Helper to proxy to backend with JSON headers
def proxy_request(method, path, params=None, json_body=None):
    url = f"{BACKEND_URL}{path}"
    print(f"\n\n***Log: {url}\n\n")
    headers = {"Content-Type": "application/json"}
    try:
        token = get_access_token()
        if token:
            headers["Authorization"] = f"Bearer {token}"
        resp = requests.request(
            method=method,
            url=url,
            params=params,
            json=json_body,
            headers=headers,
            timeout=10,
        )
        return Response(resp.content, status=resp.status_code, content_type="application/json")
    except requests.RequestException as e:
        payload = {"error": "backend_unreachable", "detail": str(e)}
        print(f"\n\n***Log: {url}\n\n")
        return Response(json.dumps(payload), status=502, content_type="application/json")
    except Exception as e:
        payload = {"error": "auth_error", "detail": str(e)}
        return Response(json.dumps(payload), status=502, content_type="application/json")

# --- Public UI routes ---
@app.route("/")
def index():
    return render_template("index.html", backend_url=BACKEND_URL)

# --- API routes used by the frontend (proxying to OpenAPI backend) ---

@app.route("/api/flights", methods=["GET"])
def api_get_flights():
    return proxy_request("GET", "/flights")

@app.route("/api/register", methods=["POST"])
def api_register():
    body = request.get_json(force=True)
    print(f"\n\n***Log register: {body}")
    return proxy_request("POST", "/register", json_body=body)

@app.route("/api/get_user", methods=["GET"])
def api_get_user():
    name = request.args.get("name")
    email = request.args.get("email")
    params = {"name": name, "email": email}
    return proxy_request("GET", "/user_id", params=params)

@app.route("/api/book", methods=["POST"])
def api_book():
    body = request.get_json(force=True)
    return proxy_request("POST", "/book", json_body=body)

@app.route("/api/bookings/<int:user_id>", methods=["GET"])
def api_get_bookings(user_id):
    return proxy_request("GET", f"/bookings/{user_id}")

@app.route("/api/cancel/<int:booking_id>", methods=["POST"])
def api_cancel(booking_id):
    return proxy_request("POST", f"/cancel/{booking_id}")

# Simple health endpoint
@app.route("/api/health")
def health():
    return jsonify({"status": "ok", "proxy_to": BACKEND_URL})
    
if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8083, debug=True)
