#!/usr/bin/env python3
"""Apply NovaCraft's marked UIKit adapter to pinned, separately licensed GLFW 3.4."""
from pathlib import Path
import shutil,sys
root=Path(sys.argv[1]); adapter=Path(sys.argv[2])
def replace(file, old, new):
    p=root/file; s=p.read_text()
    if s.count(old)!=1: raise SystemExit(f'{file}: source changed around {old[:70]!r}')
    p.write_text(s.replace(old,new))
for f in ('nova_ios_surface.h','nova_ios_surface.m'):
    shutil.copy2(adapter/f,root/'src'/f)
for f in ('src/null_window.c','src/null_monitor.c'):
    replace(f,'#include "internal.h"','#include "internal.h"\n// Modified for NovaCraft: UIKit surface and game-thread event adapter.\n#include "nova_ios_surface.h"')
replace('src/init.c','.platformID = GLFW_ANY_PLATFORM,','.platformID = GLFW_PLATFORM_NULL, // NovaCraft UIKit backend')
replace('src/null_window.c','    window->null.opacity = 1.f;','''    window->null.opacity = 1.f;
    window->null.decorated = GLFW_FALSE;
    window->null.xpos = window->null.ypos = 0;
    if (!novaSurfaceAcquire(window, &window->null.width, &window->null.height))
        return GLFW_FALSE;''')
replace('src/null_window.c','    if (!createNativeWindow(window, wndconfig, fbconfig))','''    _GLFWctxconfig iosContext = *ctxconfig;
    iosContext.source = GLFW_EGL_CONTEXT_API;
    ctxconfig = &iosContext;
    if (!createNativeWindow(window, wndconfig, fbconfig))''')
replace('src/null_window.c','    if (window->context.destroy)\n        window->context.destroy(window);','    if (window->context.destroy)\n        window->context.destroy(window);\n    novaSurfaceRelease(window);')
for old,new in [('void _glfwPollEventsNull(void)\n{\n}', 'void _glfwPollEventsNull(void)\n{\n    novaSurfacePoll();\n}'),('void _glfwWaitEventsNull(void)\n{\n}', 'void _glfwWaitEventsNull(void)\n{\n    novaSurfaceWait(-1);\n}'),('void _glfwWaitEventsTimeoutNull(double timeout)\n{\n}', 'void _glfwWaitEventsTimeoutNull(double timeout)\n{\n    novaSurfaceWait(timeout);\n}'),('void _glfwPostEmptyEventNull(void)\n{\n}', 'void _glfwPostEmptyEventNull(void)\n{\n    novaSurfaceWake();\n}')]:
    replace('src/null_window.c',old,new)
replace('src/null_window.c','''EGLenum _glfwGetEGLPlatformNull(EGLint** attribs)
{
    return 0;
}''','''EGLenum _glfwGetEGLPlatformNull(EGLint** attribs)
{
    if (!_glfw.egl.ANGLE_platform_angle || !_glfw.egl.ANGLE_platform_angle_metal)
        return 0;
    *attribs = _glfw_calloc(3, sizeof(EGLint));
    if (!*attribs) return 0;
    (*attribs)[0] = EGL_PLATFORM_ANGLE_TYPE_ANGLE;
    (*attribs)[1] = EGL_PLATFORM_ANGLE_TYPE_METAL_ANGLE;
    (*attribs)[2] = EGL_NONE;
    return EGL_PLATFORM_ANGLE_ANGLE;
}''')
replace('src/null_window.c','''EGLNativeWindowType _glfwGetEGLNativeWindowNull(_GLFWwindow* window)
{
    return 0;
}''','''EGLNativeWindowType _glfwGetEGLNativeWindowNull(_GLFWwindow* window)
{
    return (EGLNativeWindowType) novaSurfaceLayer(window);
}''')
replace('src/null_window.c','''GLFWbool _glfwRawMouseMotionSupportedNull(void)
{
    return GLFW_TRUE;
}''','''GLFWbool _glfwRawMouseMotionSupportedNull(void)
{
    return GLFW_FALSE;
}''')
replace('src/null_window.c','''    if (width)
        *width = window->null.width;
    if (height)
        *height = window->null.height;
}

void _glfwGetWindowFrameSizeNull''','''    float scale;
    novaSurfaceMetrics(NULL, NULL, &scale);
    if (width) *width = (int) (window->null.width * scale);
    if (height) *height = (int) (window->null.height * scale);
}

void _glfwGetWindowFrameSizeNull''')
replace('src/null_window.c','''    if (xscale)
        *xscale = 1.f;
    if (yscale)
        *yscale = 1.f;''','''    float scale; novaSurfaceMetrics(NULL, NULL, &scale);
    if (xscale) *xscale = scale;
    if (yscale) *yscale = scale;''')
# iPhone owns the surface size; desktop requests cannot resize the actual view.
start='''    if (window->monitor)
        return;

    if (window->null.width != width || window->null.height != height)'''
replace('src/null_window.c',start,'''    novaSurfaceMetrics(&width, &height, NULL);
    if (window->null.width != width || window->null.height != height)''')
replace('src/null_monitor.c','    mode.width = 1920;\n    mode.height = 1080;','    novaSurfaceMetrics(&mode.width, &mode.height, NULL);')
replace('src/null_monitor.c','"Null SuperNoop 0"','"NovaCraft iOS Display"')
replace('src/null_monitor.c','        *ypos = 10;','        *ypos = 0;')
replace('src/null_monitor.c','        *height = mode.height - 10;','        *height = mode.height;')
replace('src/null_monitor.c','''    if (xscale)
        *xscale = 1.f;
    if (yscale)
        *yscale = 1.f;''','''    float scale; novaSurfaceMetrics(NULL, NULL, &scale);
    if (xscale) *xscale = scale;
    if (yscale) *yscale = scale;''')
replace('src/egl_context.c', '#include "internal.h"', '#include "internal.h"\n// NovaCraft: record successful EGL presentation.\n#include "nova_ios_surface.h"')
replace('src/egl_context.c', '''    if (window->context.egl.client)
    {
        GLFWglproc proc = (GLFWglproc)''', '''    // NovaCraft: desktop GL must resolve against the translation library first.
    // MobileGlues' Apple eglGetProcAddress -> glXGetProcAddress uses RTLD_NEXT,
    // which can expose ANGLE's GLES functions (including its ES version string).
    // KHR_get_all_proc_addresses otherwise skips loading the GL client entirely.
    // Keep GLFW's version/extension validation intact; do not spoof capabilities.
    if (window->context.client == GLFW_OPENGL_API &&
        strncmp(procname, "gl", 2) == 0)
    {
        GLFWglproc translated = (GLFWglproc)
            _glfwPlatformGetModuleSymbol(_glfw.egl.handle, procname);
        if (translated)
            return translated;
    }

    if (window->context.egl.client)
    {
        GLFWglproc proc = (GLFWglproc)''')
replace('src/egl_context.c', '    eglSwapBuffers(_glfw.egl.display, window->context.egl.surface);', '    if (eglSwapBuffers(_glfw.egl.display, window->context.egl.surface))\n        novaSurfaceFramePresented();')
p=root/'src/CMakeLists.txt'
p.write_text(p.read_text()+'''
# NovaCraft UIKit adapter; upstream GLFW remains separately licensed.
enable_language(OBJC)
target_sources(glfw PRIVATE nova_ios_surface.m)
set_source_files_properties(nova_ios_surface.m PROPERTIES COMPILE_FLAGS "-fobjc-arc")
target_link_libraries(glfw PRIVATE "-framework UIKit" "-framework Foundation" "-framework QuartzCore" "-framework CoreGraphics")
target_compile_definitions(glfw PRIVATE
    _GLFW_EGL_LIBRARY="@rpath/libmobileglues.dylib"
    _GLFW_OPENGL_LIBRARY="@rpath/libmobileglues.dylib")
''')
print('Patched GLFW 3.4: UIKit surface, ANGLE Metal display and event delivery')
