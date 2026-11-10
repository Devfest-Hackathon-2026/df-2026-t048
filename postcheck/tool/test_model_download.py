"""Native URLSession integration tests, using only a synthetic loopback fixture."""
import hashlib
import http.server
import json
from pathlib import Path
import subprocess
import tempfile
import threading
import time

root = Path(__file__).resolve().parents[1]
fixture = bytes(range(256)) * 4096
counts = {}

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        counts[self.path] = counts.get(self.path, 0) + 1
        if self.path == '/counts':
            data = json.dumps(counts).encode()
        elif self.path == '/missing':
            self.send_error(503)
            return
        elif self.path == '/retry' and counts[self.path] == 1:
            data = bytes([fixture[0] ^ 1]) + fixture[1:]
        else:
            data = fixture
        self.send_response(200)
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Content-Type', 'application/octet-stream')
        self.end_headers()
        try:
            for offset in range(0, len(data), 4096):
                self.wfile.write(data[offset:offset + 4096])
                if self.path == '/slow':
                    self.wfile.flush()
                    time.sleep(0.015)
        except (BrokenPipeError, ConnectionResetError):
            pass

server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
try:
    with tempfile.TemporaryDirectory(prefix='postcheck-model-native-') as folder:
        executable = str(Path(folder) / 'native-test')
        subprocess.run(['swiftc', '-swift-version', '5', '-parse-as-library',
                        str(root / 'ios/Runner/PostCheckModelStore.swift'),
                        str(root / 'tool/model_download_native_test.swift'), '-o', executable], check=True)
        subprocess.run([executable, f'http://127.0.0.1:{server.server_port}',
                        hashlib.sha256(fixture).hexdigest(), folder], check=True, timeout=45)
finally:
    server.shutdown()
