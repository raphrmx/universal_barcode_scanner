// Serves lib/assets over http://localhost, as a Flutter web app serves the
// page: an origin where the camera may open and a worker may start.
const http = require('http');
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..', '..', 'lib', 'assets');
const port = Number(process.env.PORT || 8791);
const types = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.txt': 'text/plain; charset=utf-8'
};

http.createServer((request, response) => {
  const name = decodeURIComponent(new URL(request.url, 'http://localhost').pathname);
  const file = path.join(root, path.normalize(name));
  if (!file.startsWith(root + path.sep)) {
    response.writeHead(403).end();
    return;
  }
  fs.readFile(file, (error, data) => {
    if (error) {
      response.writeHead(404).end();
      return;
    }
    response.writeHead(200, {
      'Content-Type': types[path.extname(file)] || 'application/octet-stream'
    });
    response.end(data);
  });
}).listen(port, () => console.log(`Serving ${root} on http://localhost:${port}`));
