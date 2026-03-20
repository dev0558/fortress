import json
import os
import functools
from datetime import datetime, timedelta, timezone

from flask import Flask, request, jsonify
import jwt
import psycopg2
import psycopg2.extras

app = Flask(__name__)

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
JWT_SECRET = os.environ.get("JWT_SECRET", "change-me-in-production")
JWT_ALGORITHM = "HS256"
JWT_EXPIRY_HOURS = int(os.environ.get("JWT_EXPIRY_HOURS", "1"))

DB_HOST = os.environ.get("POSTGRES_HOST", "postgres")
DB_PORT = os.environ.get("POSTGRES_PORT", "5432")
DB_NAME = os.environ.get("POSTGRES_DB", "fortress")
DB_USER = os.environ.get("POSTGRES_APP_USER", "app_user")
DB_PASS = os.environ.get("POSTGRES_APP_PASSWORD", "change-me")

# Demo users (username -> {password, role})
DEMO_USERS = {
    "admin": {"password": "admin", "role": "admin"},
    "analyst": {"password": "analyst", "role": "analyst"},
    "viewer": {"password": "viewer", "role": "readonly"},
}

# ---------------------------------------------------------------------------
# RBAC policy loader
# ---------------------------------------------------------------------------
RBAC_POLICY = {}


def load_rbac_policy():
    """Load RBAC roles from the mounted policy file."""
    global RBAC_POLICY
    policy_path = os.environ.get("RBAC_POLICY_PATH", "/app/policies/rbac.json")
    try:
        with open(policy_path, "r") as fh:
            data = json.load(fh)
        RBAC_POLICY = {role["name"]: role["permissions"] for role in data.get("roles", [])}
        app.logger.info("RBAC policy loaded: %s", list(RBAC_POLICY.keys()))
    except FileNotFoundError:
        app.logger.warning("RBAC policy file not found at %s, using empty policy", policy_path)
    except (json.JSONDecodeError, KeyError) as exc:
        app.logger.error("Failed to parse RBAC policy: %s", exc)


# ---------------------------------------------------------------------------
# Database helpers
# ---------------------------------------------------------------------------
def get_db_connection():
    """Return a new database connection."""
    return psycopg2.connect(
        host=DB_HOST,
        port=DB_PORT,
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASS,
    )


# ---------------------------------------------------------------------------
# Auth helpers
# ---------------------------------------------------------------------------
def require_auth(action, resource):
    """Decorator that enforces JWT authentication and RBAC authorisation.

    The token must be passed as ``Authorization: Bearer <token>``.  The
    decoded token must contain a ``role`` claim whose permissions (loaded
    from *rbac.json*) include an entry matching the requested *action* on
    *resource*.
    """

    def decorator(fn):
        @functools.wraps(fn)
        def wrapper(*args, **kwargs):
            auth_header = request.headers.get("Authorization", "")
            if not auth_header.startswith("Bearer "):
                return jsonify({"error": "Missing or invalid Authorization header"}), 401

            token = auth_header.split(" ", 1)[1]
            try:
                payload = jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
            except jwt.ExpiredSignatureError:
                return jsonify({"error": "Token has expired"}), 401
            except jwt.InvalidTokenError:
                return jsonify({"error": "Invalid token"}), 401

            role = payload.get("role", "")
            permissions = RBAC_POLICY.get(role, [])

            authorised = any(
                p.get("action") == action and p.get("resource") == resource
                for p in permissions
            )
            if not authorised:
                return jsonify({"error": "Forbidden"}), 403

            # Attach decoded claims to the request context
            request.auth = payload
            return fn(*args, **kwargs)

        return wrapper

    return decorator


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------
@app.route("/health", methods=["GET"])
def health():
    """Unauthenticated health-check endpoint."""
    return jsonify({"status": "healthy", "timestamp": datetime.now(timezone.utc).isoformat()})


@app.route("/api/auth/login", methods=["POST"])
def login():
    """Authenticate with username/password and receive a JWT."""
    body = request.get_json(silent=True) or {}
    username = body.get("username", "")
    password = body.get("password", "")

    user = DEMO_USERS.get(username)
    if user is None or user["password"] != password:
        return jsonify({"error": "Invalid credentials"}), 401

    now = datetime.now(timezone.utc)
    payload = {
        "sub": username,
        "role": user["role"],
        "iat": now,
        "exp": now + timedelta(hours=JWT_EXPIRY_HOURS),
    }
    token = jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)
    return jsonify({"token": token, "role": user["role"], "expires_in": JWT_EXPIRY_HOURS * 3600})


@app.route("/api/users", methods=["GET"])
@require_auth("read", "users")
def list_users():
    """Return the list of application users from the database."""
    try:
        conn = get_db_connection()
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute("SELECT id, username, role, created_at FROM users ORDER BY id")
            rows = cur.fetchall()
        conn.close()
        return jsonify({"users": rows, "count": len(rows)}), 200
    except psycopg2.Error as exc:
        app.logger.error("Database error: %s", exc)
        return jsonify({"error": "Database unavailable"}), 503


@app.route("/api/notes", methods=["GET"])
@require_auth("read", "notes")
def list_notes():
    """Return all notes."""
    try:
        conn = get_db_connection()
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute(
                "SELECT id, user_id, title, body, created_at FROM notes ORDER BY created_at DESC"
            )
            rows = cur.fetchall()
        conn.close()
        return jsonify({"notes": rows, "count": len(rows)}), 200
    except psycopg2.Error as exc:
        app.logger.error("Database error: %s", exc)
        return jsonify({"error": "Database unavailable"}), 503


@app.route("/api/notes", methods=["POST"])
@require_auth("write", "notes")
def create_note():
    """Create a new note."""
    body = request.get_json(silent=True) or {}
    title = body.get("title", "").strip()
    content = body.get("body", "").strip()

    if not title:
        return jsonify({"error": "title is required"}), 400

    try:
        conn = get_db_connection()
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute(
                "INSERT INTO notes (user_id, title, body) VALUES (%s, %s, %s) RETURNING id, user_id, title, body, created_at",
                (request.auth.get("sub"), title, content),
            )
            note = cur.fetchone()
            conn.commit()
        conn.close()
        return jsonify({"note": note}), 201
    except psycopg2.Error as exc:
        app.logger.error("Database error: %s", exc)
        return jsonify({"error": "Database unavailable"}), 503


@app.route("/api/rbac/check", methods=["POST"])
@require_auth(action="read", resource="status")
def rbac_check():
    """Live RBAC check endpoint used by the dashboard tester.

    Body: { "check_role": "analyst", "check_action": "read", "check_resource": "notes" }
    Returns: { "allowed": true/false, "role": ..., "action": ..., "resource": ... }
    """
    body = request.get_json(silent=True) or {}
    check_role = body.get("check_role", "")
    check_action = body.get("check_action", "")
    check_resource = body.get("check_resource", "")

    permissions = RBAC_POLICY.get(check_role, [])
    allowed = any(
        p.get("action") == check_action and p.get("resource") == check_resource
        for p in permissions
    )

    return jsonify({
        "allowed": allowed,
        "role": check_role,
        "action": check_action,
        "resource": check_resource,
    })


@app.route("/api/status", methods=["GET"])
@require_auth("read", "status")
def system_status():
    """Return system status overview."""
    db_ok = False
    try:
        conn = get_db_connection()
        with conn.cursor() as cur:
            cur.execute("SELECT 1")
        conn.close()
        db_ok = True
    except psycopg2.Error:
        pass

    return jsonify({
        "database": "connected" if db_ok else "unreachable",
        "rbac_roles_loaded": list(RBAC_POLICY.keys()),
        "timestamp": datetime.now(timezone.utc).isoformat(),
    })


# ---------------------------------------------------------------------------
# Startup
# ---------------------------------------------------------------------------
load_rbac_policy()

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
