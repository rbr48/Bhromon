import os
import uuid
from flask import Flask, request, jsonify
from werkzeug.utils import secure_filename

app = Flask(__name__)
UPLOAD_FOLDER = '/var/www/bhromon/uploads'
API_KEY = "bhromon_secure_upload_key_2026"

app.config['UPLOAD_FOLDER'] = UPLOAD_FOLDER
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

@app.after_request
def add_cors_headers(response):
    response.headers['Access-Control-Allow-Origin'] = '*'
    response.headers['Access-Control-Allow-Methods'] = 'GET, POST, PUT, DELETE, OPTIONS'
    response.headers['Access-Control-Allow-Headers'] = 'Content-Type, X-Upload-Key, Authorization'
    return response

@app.route('/upload', methods=['POST', 'OPTIONS'])
def upload_file():
    if request.method == 'OPTIONS':
        return jsonify({"status": "ok"}), 200
        
    # Check API key
    key = request.headers.get('X-Upload-Key') or request.form.get('key')
    if key != API_KEY:
        return jsonify({"error": "Unauthorized"}), 401
        
    if 'file' not in request.files:
        return jsonify({"error": "No file part"}), 400
        
    file = request.files['file']
    if file.filename == '':
        return jsonify({"error": "No selected file"}), 400
        
    # Get custom path (e.g. 'explorer_avatars/userId.jpg')
    custom_path = request.form.get('path', '')
    
    if custom_path:
        # Prevent directory traversal
        parts = [secure_filename(p) for p in custom_path.split('/') if p]
        if not parts:
            return jsonify({"error": "Invalid path"}), 400
        filename = os.path.join(*parts)
        dest_path = os.path.join(app.config['UPLOAD_FOLDER'], filename)
        os.makedirs(os.path.dirname(dest_path), exist_ok=True)
    else:
        # Default filename
        ext = os.path.splitext(file.filename)[1]
        filename = f"{uuid.uuid4().hex}{ext}"
        dest_path = os.path.join(app.config['UPLOAD_FOLDER'], filename)

    try:
        file.save(dest_path)
        # Return the public URL
        url_path = filename.replace('\\', '/')
        public_url = f"https://bhromon.bpep.info/uploads/{url_path}"
        print(f"File uploaded successfully: {dest_path} -> {public_url}")
        return jsonify({
            "status": "success",
            "url": public_url
        })
    except Exception as e:
        print(f"Error saving file: {e}")
        return jsonify({"error": str(e)}), 500

@app.route('/delete', methods=['DELETE', 'OPTIONS'])
def delete_file():
    if request.method == 'OPTIONS':
        return jsonify({"status": "ok"}), 200
        
    # Check API key
    key = request.headers.get('X-Upload-Key') or (request.json.get('key') if request.json else None)
    if key != API_KEY:
        return jsonify({"error": "Unauthorized"}), 401
        
    custom_path = (request.json.get('path', '') if request.json else '') or request.args.get('path', '')
    if not custom_path:
        return jsonify({"error": "No path specified"}), 400
        
    # Prevent directory traversal
    parts = [secure_filename(p) for p in custom_path.split('/') if p]
    if not parts:
        return jsonify({"error": "Invalid path"}), 400
    filename = os.path.join(*parts)
    dest_path = os.path.join(app.config['UPLOAD_FOLDER'], filename)
    
    if os.path.exists(dest_path):
        try:
            os.remove(dest_path)
            print(f"File deleted successfully: {dest_path}")
            return jsonify({"status": "success", "message": "File deleted successfully"})
        except Exception as e:
            print(f"Error deleting file {dest_path}: {e}")
            return jsonify({"error": str(e)}), 500
    else:
        print(f"File not found: {dest_path}")
        return jsonify({"error": "File not found"}), 404

if __name__ == '__main__':
    # Listen on localhost port 8087
    app.run(host='127.0.0.1', port=8087)
