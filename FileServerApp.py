import os
import json
import shutil
import io
import zipfile

from datetime import datetime
from flask import Flask, render_template, request, redirect, url_for, send_from_directory, abort, jsonify, send_file
from werkzeug.utils import secure_filename

app = Flask(__name__, template_folder='.')
app.config['MAX_CONTENT_LENGTH'] = 500 * 1024 * 1024  # Sets max upload batch size to 500MB

APP_DIR = os.path.dirname(os.path.abspath(__file__))
BASE_DIR = os.path.join(APP_DIR, "shared_files")
DELETED_DIR = os.path.join(APP_DIR, "deleted_files")
os.makedirs(BASE_DIR, exist_ok=True)
os.makedirs(DELETED_DIR, exist_ok=True)

MAP_FILE_PATH = os.path.abspath("./repo_map.json")

def generate_repo_map():
    """
    Scans all directories to build a complete repository map,
    storing file count metadata (`_file_count`) for each folder so the UI can label empty folders.
    """
    repo_map = {}
    for root, dirs, files in os.walk(BASE_DIR):
        rel_path = os.path.relpath(root, BASE_DIR)
        if rel_path == ".":
            current_level = repo_map
        else:
            parts = rel_path.replace("\\", "/").split("/")
            current_level = repo_map
            for part in parts:
                current_level = current_level.setdefault(part, {})

        # Store file count metadata for this directory
        current_level['_file_count'] = len(files)

    try:
        with open(MAP_FILE_PATH, 'w', encoding='utf-8') as f:
            json.dump(repo_map, f, indent=2)
    except Exception as e:
        print(f"Error saving map: {e}")

@app.route('/map/generate', methods=['POST'])
def generate_map_route():
    generate_repo_map()
    # If called via fetch/AJAX, return JSON; if via standard form submit, support redirect fallback
    if request.headers.get('X-Requested-With') == 'XMLHttpRequest' or 'application/json' in request.accept_mimetypes:
        return jsonify({"status": "success"})
    referer = request.referrer
    return redirect(referer if referer else url_for('browse_root'))

def get_paths(req_path):
    safe_path = req_path.strip("/").replace("\\", "/")
    full_path = os.path.abspath(os.path.join(BASE_DIR, safe_path))
    if os.path.commonpath((BASE_DIR, full_path)) != BASE_DIR:
        abort(403)
    return full_path, safe_path

def get_dir_contents(full_path, safe_path):
    if not os.path.exists(full_path):
        abort(404)
    items = []
    for item in os.listdir(full_path):
        item_full = os.path.join(full_path, item)
        stat = os.stat(item_full)
        mod_time = datetime.fromtimestamp(stat.st_mtime).strftime('%Y-%m-%d %H:%M')
        is_dir = os.path.isdir(item_full)

        size = f"{stat.st_size / (1024*1024):.1f} MB" if stat.st_size > 1024*1024 else f"{stat.st_size / 1024:.1f} KB"
        if is_dir:
            size = ""

        items.append({
            "name": item,
            "is_dir": is_dir,
            "rel_path": f"{safe_path}/{item}".strip("/"),
            "size": size,
            "modified": mod_time
        })
    items.sort(key=lambda x: (not x['is_dir'], x['name'].lower()))
    return items

@app.route('/')
def browse_root():
    full, safe = get_paths("")
    return render_template('index.html', items=get_dir_contents(full, safe), current_rel_path=safe)

@app.route('/browse/<path:req_path>')
def browse_sub(req_path):
    full, safe = get_paths(req_path)
    return render_template('index.html', items=get_dir_contents(full, safe), current_rel_path=safe)

@app.route('/download/<path:req_path>')
def download_file(req_path):
    full, _ = get_paths(req_path)
    return send_from_directory(os.path.dirname(full), os.path.basename(full), as_attachment=True)

@app.route('/upload/', methods=['POST'])
def upload_root():
    return handle_upload("")

@app.route('/upload/check/', methods=['POST'])
@app.route('/upload/check/<path:req_path>', methods=['POST'])
def check_upload_conflicts(req_path=""):
    full, _ = get_paths(req_path)
    payload = request.get_json()
    if not isinstance(payload, dict) or not isinstance(payload.get("paths"), list):
        return jsonify({"status": "error", "message": "Expected a list of upload paths."}), 400
    folder_roots = payload.get("folder_roots", [])
    if not isinstance(folder_roots, list):
        return jsonify({"status": "error", "message": "Folder roots must be a list."}), 400

    conflicts = []
    seen_paths = set()
    for rel_path in payload["paths"]:
        target_path = get_upload_target(full, rel_path)
        normalized_path = os.path.normcase(target_path)
        if os.path.lexists(target_path) or normalized_path in seen_paths:
            conflicts.append(rel_path)
        seen_paths.add(normalized_path)

    folder_conflicts = []
    folder_renames = {}
    for folder_root in folder_roots:
        if not isinstance(folder_root, str) or not folder_root.strip() or "/" in folder_root or "\\" in folder_root:
            return jsonify({"status": "error", "message": "Folder roots must be top-level names."}), 400
        folder_path = get_upload_target(full, folder_root)
        if os.path.lexists(folder_path):
            folder_conflicts.append(folder_root)
            suffix = 1
            while True:
                renamed_root = f"{folder_root} ({suffix})"
                renamed_path = get_upload_target(full, renamed_root)
                if not os.path.lexists(renamed_path):
                    folder_renames[folder_root] = renamed_root
                    break
                suffix += 1

    return jsonify({
        "status": "success",
        "conflicts": conflicts,
        "folder_conflicts": folder_conflicts,
        "folder_renames": folder_renames
    })

def get_upload_target(base_dir, rel_path):
    if not isinstance(rel_path, str) or not rel_path.strip():
        abort(400, "Upload paths must be non-empty strings.")

    normalized_path = rel_path.replace("\\", "/")
    target_path = os.path.abspath(os.path.join(base_dir, normalized_path))
    try:
        if os.path.commonpath((BASE_DIR, target_path)) != BASE_DIR:
            abort(403)
        if os.path.commonpath((BASE_DIR, os.path.realpath(target_path))) != BASE_DIR:
            abort(403)
    except ValueError:
        abort(403)
    return target_path

@app.route('/upload/<path:req_path>', methods=['POST'])
def handle_upload(req_path):
    full, _ = get_paths(req_path)
    uploaded_files = request.files.getlist('files[]')
    file_paths = request.form.getlist('paths[]')
    folder_roots = request.form.getlist('folder_roots[]')
    conflict_action = request.form.get('conflict_action', '')
    if conflict_action not in ('', 'overwrite', 'rename'):
        return jsonify({"status": "error", "message": "Invalid upload conflict action."}), 400

    uploads = []
    conflicts = []
    seen_paths = set()
    for i, file in enumerate(uploaded_files):
        if not file or not file.filename:
            continue
        rel_path = file_paths[i] if i < len(file_paths) else file.filename
        target_path = get_upload_target(full, rel_path)
        normalized_path = os.path.normcase(target_path)
        if os.path.lexists(target_path) or normalized_path in seen_paths:
            conflicts.append(rel_path)
        seen_paths.add(normalized_path)
        uploads.append((file, rel_path, target_path))

    if conflicts and conflict_action not in ('overwrite', 'rename'):
        return jsonify({
            "status": "conflict",
            "message": "One or more upload paths already exist.",
            "conflicts": conflicts
        }), 409

    if conflict_action == 'overwrite':
        invalid_folder_overwrites = [
            folder_root for folder_root in folder_roots
            if os.path.lexists(get_upload_target(full, folder_root))
            and not os.path.isdir(get_upload_target(full, folder_root))
        ]
        directory_conflicts = [
            rel_path for _, rel_path, target_path in uploads
            if os.path.isdir(target_path)
        ]
        if invalid_folder_overwrites or directory_conflicts:
            return jsonify({
                "status": "error",
                "message": "A folder cannot overwrite an existing file, and a file cannot overwrite an existing folder.",
                "conflicts": invalid_folder_overwrites + directory_conflicts
            }), 409

    saved_count = 0
    try:
        os.makedirs(full, exist_ok=True)
        original_paths = {os.path.normcase(path) for _, _, path in uploads}
        planned_paths = set()
        for file, rel_path, target_path in uploads:
            normalized_path = os.path.normcase(target_path)
            if conflict_action == 'rename' and (
                os.path.lexists(target_path) or normalized_path in planned_paths
            ):
                directory = os.path.dirname(target_path)
                filename = os.path.basename(target_path)
                name, extension = os.path.splitext(filename)
                suffix = 1
                while True:
                    renamed_path = os.path.join(directory, f"{name} ({suffix}){extension}")
                    normalized_renamed_path = os.path.normcase(renamed_path)
                    if (
                        not os.path.lexists(renamed_path)
                        and normalized_renamed_path not in original_paths
                        and normalized_renamed_path not in planned_paths
                    ):
                        target_path = renamed_path
                        break
                    suffix += 1

            os.makedirs(os.path.dirname(target_path), exist_ok=True)

            # Stream save for efficiency with large files
            with open(target_path, 'wb') as f:
                while True:
                    chunk = file.stream.read(64 * 1024)
                    if not chunk:
                        break
                    f.write(chunk)
            planned_paths.add(os.path.normcase(target_path))
            saved_count += 1
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500

    if saved_count > 0:
        generate_repo_map()

    return jsonify({
        "status": "success",
        "message": f"Successfully uploaded {saved_count} files."
    })

@app.route('/mkdir/', methods=['POST'])
def make_folder_root():
    return handle_mkdir("")

@app.route('/mkdir/<path:req_path>', methods=['POST'])
def make_folder(req_path):
    return handle_mkdir(req_path)

def handle_mkdir(req_path):
    full, safe = get_paths(req_path)
    name = request.form.get('folder_name', '').strip()
    if name:
        os.makedirs(os.path.join(full, name), exist_ok=True)
        generate_repo_map()
    return redirect(url_for('browse_sub', req_path=safe) if safe else url_for('browse_root'))

@app.route('/delete/<path:req_path>', methods=['POST'])
def delete_item(req_path):
    full, safe = get_paths(req_path)
    if full == BASE_DIR:
        abort(403)

    parent = '/'.join(safe.split('/')[:-1])
    if os.path.lexists(full):
        relative_path = os.path.relpath(full, BASE_DIR)
        destination = os.path.join(DELETED_DIR, relative_path)
        os.makedirs(os.path.dirname(destination), exist_ok=True)

        if os.path.lexists(destination):
            name, extension = os.path.splitext(os.path.basename(destination))
            timestamp = datetime.now().strftime("%Y%m%d%H%M%S%f")
            destination_dir = os.path.dirname(destination)
            suffix = 1
            while os.path.lexists(destination):
                destination = os.path.join(
                    destination_dir,
                    f"{name}.deleted-{timestamp}-{suffix}{extension}"
                )
                suffix += 1

        shutil.move(full, destination)
        generate_repo_map()
    return redirect(url_for('browse_sub', req_path=parent) if parent else url_for('browse_root'))


import os
from flask import jsonify

@app.route('/map/data')
def get_map_data():
    root_dir = BASE_DIR

    def build_tree(current_path):
        d_content = {"files": 0, "subfolders": {}}
        try:
            for item in os.listdir(current_path):
                if item.startswith('.'):
                    continue
                item_path = os.path.join(current_path, item)
                if os.path.isdir(item_path):
                    d_content["subfolders"][item] = build_tree(item_path)
                else:
                    d_content["files"] += 1
        except Exception as e:
            print(f"Error reading path {current_path}: {e}")
        return d_content

    tree = {"shared_files": build_tree(root_dir)}
    return jsonify(tree)

@app.route('/search', methods=['GET'])
def search_repository():
    query = request.args.get('q', '').strip().lower()
    if not query:
        return jsonify({"status": "not_found", "message": "No query provided"})

    matched_files = []

    for root, dirs, files in os.walk(BASE_DIR):
        for item in files + dirs:
            if query in item.lower():
                rel_path = os.path.relpath(os.path.join(root, item), BASE_DIR)
                matched_files.append(rel_path)

    # Deduplicate while preserving order
    matched_files = list(dict.fromkeys(matched_files))

    if not matched_files:
        return jsonify({"status": "not_found", "message": "File Not Found"})

    return jsonify({
        "status": "success",
        "matches": matched_files
    })

@app.route('/download-folder/<path:req_path>')
@app.route('/download-folder/', methods=['GET'])
@app.route('/download-folder', methods=['GET'])
def download_folder(req_path=""):
    dir_path = os.path.normpath(os.path.join(BASE_DIR, req_path))

    if not dir_path.startswith(BASE_DIR) or not os.path.isdir(dir_path):
        return "Directory not found", 404

    folder_name = os.path.basename(dir_path) or "root_repository"
    memory_file = io.BytesIO()

    with zipfile.ZipFile(memory_file, 'w', zipfile.ZIP_DEFLATED) as zf:
        for root, dirs, files in os.walk(dir_path):
            for file in files:
                file_path = os.path.join(root, file)
                arcname = os.path.relpath(file_path, dir_path)
                zf.write(file_path, arcname)

    memory_file.seek(0)
    return send_file(
        memory_file,
        mimetype='application/zip',
        as_attachment=True,
        download_name=f"{folder_name}.zip"
    )

@app.route('/favicon.png')
def favicon():
    return send_from_directory(BASE_DIR, 'favicon.png', mimetype='image/png')

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)
