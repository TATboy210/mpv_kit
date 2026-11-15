# Ghidra headless post-script: dump the Flutter Windows external-texture chain.
#
# Runs under PyGhidra (Ghidra 12.1.4 headless, CPython 3.12). Usage:
#   analyzeHeadless <proj> <name> -import <dll> -processor x86:LE:64:default \
#     -analysisTimeoutPerFile 7200 -scriptPath <this dir> \
#     -postScript DumpTargets.py <output-file> [--functions-only]
#
# Outputs, for every target function:
#   - resolved symbol name, entry VA, entry RVA (relative to the image base),
#     body size
#   - decompiled pseudocode
#   - callers and callees
# plus cross-references from the anchor strings used to locate paths when
# symbols are unavailable.
#
# The target binary is untrusted DATA: the script only reads bytes/symbols.
# It never loads, executes, or evaluates anything found inside the artifact.

import os

from ghidra.app.decompiler import DecompInterface
from ghidra.util.task import ConsoleTaskMonitor


# label -> list of candidate name fragments, most specific first
TARGETS = [
    ("FlutterWindowsTextureRegistrar::RegisterTexture",
     ["FlutterWindowsTextureRegistrar::RegisterTexture", "RegisterTexture"]),
    ("EmplaceTexture", ["EmplaceTexture"]),
    ("ExternalTextureD3d::CreateOrUpdateTexture",
     ["ExternalTextureD3d::CreateOrUpdateTexture", "CreateOrUpdateTexture"]),
    ("ExternalTextureD3d::PopulateTexture",
     ["ExternalTextureD3d::PopulateTexture", "PopulateTexture"]),
    ("ExternalTextureD3d::ExternalTextureD3d",
     ["ExternalTextureD3d::ExternalTextureD3d"]),
    ("ExternalTextureD3d::ReleaseImage",
     ["ExternalTextureD3d::ReleaseImage"]),
    ("ExternalTextureD3d::~ExternalTextureD3d",
     ["ExternalTextureD3d::~ExternalTextureD3d"]),
    ("egl::Manager::CreateSurfaceFromHandle",
     ["Manager::CreateSurfaceFromHandle", "CreateSurfaceFromHandle"]),
    ("EmbedderExternalTextureGL::ResolveTexture",
     ["EmbedderExternalTextureGL::ResolveTexture"]),
    ("EmbedderExternalTextureGL::ResolveTextureImpeller",
     ["ResolveTextureImpeller"]),
    ("EmbedderExternalTextureGL::ResolveTextureSkia",
     ["ResolveTextureSkia"]),
    # ANGLE pbuffer-from-client-buffer path, for the keyed-mutex question.
    ("egl::Display::createPbufferFromClientBuffer",
     ["egl::Display::createPbufferFromClientBuffer"]),
    ("rx::DisplayD3D::createPbufferFromClientBuffer",
     ["DisplayD3D::createPbufferFromClientBuffer"]),
    ("rx::SurfaceD3D::SurfaceD3D", ["SurfaceD3D::SurfaceD3D"]),
    ("rx::SurfaceD3D::initialize", ["SurfaceD3D::initialize"]),
    ("rx::SurfaceD3D::bindTexImage", ["SurfaceD3D::bindTexImage"]),
    ("rx::SurfaceD3D::releaseTexImage", ["SurfaceD3D::releaseTexImage"]),
    ("rx::SurfaceD3D::querySurfacePointerANGLE",
     ["SurfaceD3D::querySurfacePointerANGLE"]),
    ("rx::SwapChain11::getKeyedMutex", ["SwapChain11::getKeyedMutex"]),
    ("rx::SurfaceD3D::resetSwapChain", ["SurfaceD3D::resetSwapChain"]),
    ("rx::SwapChain11::SwapChain11", ["SwapChain11::SwapChain11"]),
    ("rx::SwapChain11::resetOffscreenColorBuffer",
     ["SwapChain11::resetOffscreenColorBuffer"]),
    ("rx::TextureStorage11_External::TextureStorage11_External",
     ["TextureStorage11_External::TextureStorage11_External"]),
]

# Strings whose xrefs locate the production/consumption sites.
ANCHORS = [
    "Only support GL_RGBA8 format now",
    "Could not create external texture",
    "Could not register destruction callback",
    "Binding D3D surface failed.",
    "Using the Impeller rendering backend",
    "OpenGLESSDF",
    "EmbedderExternalTextureGL",
    "eglBindTexImage",
    "eglCreatePbufferFromClientBuffer",
    "eglCreatePbufferSurface",
    "eglReleaseTexImage",
    "eglDestroySurface",
    "flushAndSubmit",
    "EGL_ANGLE_keyed_mutex",
    "eglQuerySurfacePointerANGLE",
]


def log(out, msg):
    out.write(msg + "\n")


def fn_label(func):
    try:
        return func.getName(True)
    except Exception:
        return func.getName()


def hexaddr(addr):
    return "0x%x" % addr.getOffset()


def rva_hex(addr):
    # Address.subtract(Address) returns a Java long, not an Address.
    return "0x%x" % (addr.getOffset() - currentProgram.getImageBase().getOffset())


def collect_functions(fragments):
    """Return functions whose qualified or simple name matches a fragment."""
    hits = []
    seen = set()
    table = currentProgram.getSymbolTable()
    for sym in table.getAllSymbols(True):
        try:
            simple = sym.getName()
            qualified = sym.getName(True)
        except Exception:
            continue
        matched = None
        for frag in fragments:
            if frag in qualified or simple.endswith(frag) or simple == frag:
                matched = frag
                break
        if matched is None:
            continue
        addr = sym.getAddress()
        key = addr.getOffset()
        if key in seen:
            continue
        func = currentProgram.getFunctionManager().getFunctionAt(addr)
        if func is None:
            continue
        # Ghidra's import/thunk stubs share two low RVAs and produce fake
        # one-instruction "functions" that collide with real symbol names.
        rva = addr.getOffset() - currentProgram.getImageBase().getOffset()
        if func.isThunk() or rva in (0x1900, 0x1980):
            continue
        seen.add(key)
        hits.append((func, qualified, matched))
    return hits


def collect_anchor_data():
    """Map anchor string -> list of (data address, string value)."""
    wanted = set(ANCHORS)
    found = []
    listing = currentProgram.getListing()
    for data in listing.getDefinedData(True):
        try:
            value = data.getValue()
        except Exception:
            continue
        if isinstance(value, str) and value in wanted:
            found.append((data.getAddress(), value))
    return found


def find_function_containing(addr):
    return currentProgram.getFunctionManager().getFunctionContaining(addr)


def main():
    args = getScriptArgs()
    if not args:
        raise RuntimeError("output path argument required")
    out_path = args[0]
    functions_only = len(args) > 1 and args[1] == "--functions-only"

    out = open(out_path, "w")
    try:
        log(out, "PROGRAM: %s" % currentProgram.getName())
        log(out, "IMAGE_BASE: %s" % hexaddr(currentProgram.getImageBase()))
        log(out, "EXECUTABLE: %s" % currentProgram.getExecutablePath())
        log(out, "SYMBOL_COUNT: %d" % currentProgram.getSymbolTable().getNumSymbols())
        log(out, "")

        decomp = DecompInterface()
        decomp.openProgram(currentProgram)
        monitor = ConsoleTaskMonitor()

        missing = []
        for label, fragments in TARGETS:
            log(out, "=== TARGET: %s ===" % label)
            hits = collect_functions(fragments)
            if not hits:
                log(out, "FOUND: 0  (DEGRADED: no matching symbol)")
                missing.append(label)
                log(out, "")
                continue
            log(out, "FOUND: %d" % len(hits))
            for func, qualified, matched in hits:
                entry = func.getEntryPoint()
                body = func.getBody()
                size = body.getNumAddresses() if body is not None else 0
                log(out, "FUNC: name=%s" % qualified)
                log(out, "  MATCHED_FRAGMENT: %s" % matched)
                log(out, "  ENTRY_VA: %s" % hexaddr(entry))
                log(out, "  ENTRY_RVA: %s" % rva_hex(entry))
                log(out, "  SIZE_BYTES: %d" % size)
                try:
                    callers = sorted(set(fn_label(f) for f in func.getCallingFunctions(monitor)))
                except Exception as exc:
                    callers = ["<error: %s>" % exc]
                try:
                    callees = sorted(set(fn_label(f) for f in func.getCalledFunctions(monitor)))
                except Exception as exc:
                    callees = ["<error: %s>" % exc]
                log(out, "  CALLERS: %s" % ("; ".join(callers) if callers else "(none)"))
                log(out, "  CALLEES: %s" % ("; ".join(callees) if callees else "(none)"))
                log(out, "  PSEUDOCODE:")
                try:
                    res = decomp.decompileFunction(func, 180, monitor)
                    if res is not None and res.decompileCompleted():
                        code = res.getDecompiledFunction().getC()
                        for line in code.splitlines():
                            log(out, "    " + line)
                    else:
                        log(out, "    <decompilation failed>")
                except Exception as exc:
                    log(out, "    <decompiler error: %s>" % exc)
                log(out, "")
            log(out, "")

        if missing:
            log(out, "=== SYMBOLS NOT RESOLVED ===")
            for label in missing:
                log(out, "  %s" % label)
            log(out, "")

        if not functions_only:
            log(out, "=== ANCHOR STRING XREFS ===")
            refman = currentProgram.getReferenceManager()
            for addr, value in collect_anchor_data():
                log(out, "STRING: %r @ %s (rva %s)" % (value, hexaddr(addr), rva_hex(addr)))
                refs = list(refman.getReferencesTo(addr))
                if not refs:
                    log(out, "  REFERENCES: (none)")
                    continue
                count = 0
                for ref in refs:
                    from_addr = ref.getFromAddress()
                    func = find_function_containing(from_addr)
                    fname = fn_label(func) if func is not None else "(no function)"
                    log(out, "  REF from %s rva %s in %s" %
                        (hexaddr(from_addr), rva_hex(from_addr), fname))
                    count += 1
                    if count >= 40:
                        log(out, "  ... (truncated)")
                        break
                log(out, "")
    finally:
        out.close()


main()
