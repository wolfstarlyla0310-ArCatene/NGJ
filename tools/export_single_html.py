#!/usr/bin/env python3
"""把 Godot Web 导出目录打包成一个自包含的 HTML 文件。

用法：
    godot --headless --path . --export-release "Web" "build/web/index.html"
    python tools/export_single_html.py

默认读取 build/web，输出 build/KeepSound-single.html。
wasm / pck 使用 gzip + base64 内嵌，运行时通过 DecompressionStream 解压。
"""
from __future__ import annotations

import base64
import gzip
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent.parent
WEB = ROOT / "build" / "web"
OUT = ROOT / "build" / "KeepSound-single.html"

BOOTSTRAP = """\t\t<script>
const GODOT_THREADS_ENABLED = false;
const engine = new Engine({ executable: "index", canvasResizePolicy: 2, focusCanvas: true, args: [] });

(function () {
\tconst statusOverlay = document.getElementById('status');
\tconst statusProgress = document.getElementById('status-progress');
\tconst statusNotice = document.getElementById('status-notice');

\tlet initializing = true;
\tlet statusMode = '';

\tfunction setStatusMode(mode) {
\t\tif (statusMode === mode || !initializing) { return; }
\t\tif (mode === 'hidden') {
\t\t\tstatusOverlay.remove();
\t\t\tinitializing = false;
\t\t\treturn;
\t\t}
\t\tstatusOverlay.style.visibility = 'visible';
\t\tstatusProgress.style.display = mode === 'progress' ? 'block' : 'none';
\t\tstatusNotice.style.display = mode === 'notice' ? 'block' : 'none';
\t\tstatusMode = mode;
\t}

\tfunction setStatusNotice(text) {
\t\twhile (statusNotice.lastChild) { statusNotice.removeChild(statusNotice.lastChild); }
\t\tconst lines = text.split(String.fromCharCode(10));
\t\tfor (const line of lines) {
\t\t\tstatusNotice.appendChild(document.createTextNode(line));
\t\t\tstatusNotice.appendChild(document.createElement('br'));
\t\t}
\t}

\tfunction displayFailureNotice(err) {
\t\tconsole.error(err);
\t\tsetStatusNotice(err instanceof Error ? err.message : String(err));
\t\tsetStatusMode('notice');
\t\tinitializing = false;
\t}

\tfunction bytesFromB64(id) {
\t\tconst b64 = document.getElementById(id).textContent.replace(/\\s+/g, '');
\t\tconst bin = atob(b64);
\t\tconst bytes = new Uint8Array(bin.length);
\t\tfor (let i = 0; i < bin.length; i++) { bytes[i] = bin.charCodeAt(i); }
\t\treturn bytes;
\t}

\tasync function gunzipB64(id) {
\t\tconst bytes = bytesFromB64(id);
\t\tconst stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream('gzip'));
\t\treturn new Uint8Array(await new Response(stream).arrayBuffer());
\t}

\tfunction textFromB64(id) {
\t\treturn new TextDecoder().decode(bytesFromB64(id));
\t}

\tasync function boot() {
\t\tif (typeof DecompressionStream === 'undefined') {
\t\t\tthrow new Error('This single-file build needs a browser with DecompressionStream support (Chrome 80+/Edge 80+/Firefox 113+/Safari 16.4+).');
\t\t}
\t\tconst missing = Engine.getMissingFeatures({ threads: GODOT_THREADS_ENABLED });
\t\tif (missing.length !== 0) {
\t\t\tthrow new Error('Missing browser features:' + String.fromCharCode(10) + missing.join(String.fromCharCode(10)));
\t\t}
\t\tglobalThis.__GODOT_ASSET_URLS = {
\t\t\t'godot.audio.worklet.js': URL.createObjectURL(new Blob([textFromB64('worklet-js')], { type: 'application/javascript' })),
\t\t\t'godot.audio.position.worklet.js': URL.createObjectURL(new Blob([textFromB64('position-worklet-js')], { type: 'application/javascript' })),
\t\t};
\t\tsetStatusMode('progress');
\t\tstatusProgress.removeAttribute('value');
\t\tstatusProgress.removeAttribute('max');
\t\tconst wasmUrl = URL.createObjectURL(new Blob([await gunzipB64('wasm-gz')], { type: 'application/wasm' }));
\t\tawait engine.init(wasmUrl);
\t\tengine.copyToFS('game.pck', await gunzipB64('pck-gz'));
\t\tawait engine.start({ args: ['--main-pack', 'game.pck'] });
\t\tsetStatusMode('hidden');
\t}

\tboot().catch(displayFailureNotice);
}());
\t\t</script>
"""


def b64_gzip(path: Path) -> tuple[str, int, int]:
    raw = path.read_bytes()
    compressed = gzip.compress(raw, 9)
    return base64.b64encode(compressed).decode('ascii'), len(raw), len(compressed)


def b64(path: Path) -> str:
    return base64.b64encode(path.read_bytes()).decode('ascii')


def main() -> int:
    web = Path(sys.argv[1]) if len(sys.argv) > 1 else WEB
    out = Path(sys.argv[2]) if len(sys.argv) > 2 else OUT

    js = (web / 'index.js').read_text(encoding='utf-8', errors='replace')
    old_load = "preloader.loadPromise(`${loadPath}.wasm`, size, true)"
    if old_load not in js:
        raise SystemExit('index.js load patch point missing')
    js = js.replace(old_load, "preloader.loadPromise(loadPath, size, true)", 1)

    old_loc = "'locateFile': function (path) {\n\t\t\t\tif (!path.startsWith('godot.')) {"
    if old_loc not in js:
        raise SystemExit('index.js locateFile patch point missing')
    js = js.replace(
        old_loc,
        "'locateFile': function (path) {\n"
        "\t\t\t\tconst _override = (globalThis.__GODOT_ASSET_URLS || {})[path];\n"
        "\t\t\t\tif (_override) { return _override; }\n"
        "\t\t\t\tif (!path.startsWith('godot.')) {",
        1,
    )

    wasm_b64, wasm_len, wasm_gz = b64_gzip(web / 'index.wasm')
    pck_b64, pck_len, pck_gz = b64_gzip(web / 'index.pck')

    tpl = (web / 'index.html').read_text(encoding='utf-8')
    icon = b64(web / 'index.icon.png')
    splash = b64(web / 'index.png')
    tpl = tpl.replace('href="index.icon.png"', f'href="data:image/png;base64,{icon}"')
    tpl = tpl.replace('href="index.apple-touch-icon.png"', f'href="data:image/png;base64,{icon}"')
    tpl = tpl.replace('src="index.png"', f'src="data:image/png;base64,{splash}"')
    tpl = tpl.replace('\t\t<script src="index.js"></script>\n', '')

    start = tpl.index('\t\t<script>\nconst GODOT_CONFIG')
    end = tpl.index('\t\t</script>\n\t</body>', start)
    tpl = tpl[:start] + BOOTSTRAP + tpl[end + len('\t\t</script>\n'):]

    payload = (
        '<script type="text/plain" id="worklet-js">' + b64(web / 'index.audio.worklet.js') + '</script>\n'
        '<script type="text/plain" id="position-worklet-js">' + b64(web / 'index.audio.position.worklet.js') + '</script>\n'
        '<script type="text/plain" id="wasm-gz">' + wasm_b64 + '</script>\n'
        '<script type="text/plain" id="pck-gz">' + pck_b64 + '</script>\n'
    )
    tpl = tpl.replace('\t\t<script>\nconst GODOT_THREADS_ENABLED', payload + '\t\t<script>\nconst GODOT_THREADS_ENABLED')
    tpl = tpl.replace('</head>', '\t\t<script>\n' + js + '\n\t\t</script>\n\t</head>', 1)

    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(tpl, encoding='utf-8')
    print(f'wasm {wasm_len} -> gz {wasm_gz}')
    print(f'pck  {pck_len} -> gz {pck_gz}')
    print(f'html {out.stat().st_size} bytes -> {out}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
