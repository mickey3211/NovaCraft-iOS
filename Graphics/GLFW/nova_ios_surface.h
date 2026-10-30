// Original NovaCraft UIKit host for the separately licensed GLFW library.
#pragma once
#define NOVA_API __attribute__((visibility("default")))
#ifdef __cplusplus
extern "C" {
#endif
// Main thread: returns a retained UIView*, consumed by the app with takeRetainedValue.
NOVA_API void* nova_glfw_create_view(void);
NOVA_API int nova_glfw_has_presented_frame(void);
void novaSurfaceFramePresented(void);
// The view must stay visible until the game closes its GLFW window.
NOVA_API void nova_glfw_request_close(void);
// Main thread: releases an unused surface, or requests game closure and returns 0.
NOVA_API int nova_glfw_dispose_surface(void);
NOVA_API void nova_glfw_send_key(int key, int scancode, int action, int mods);
NOVA_API void nova_glfw_send_character(unsigned int codepoint);
NOVA_API void nova_glfw_send_scroll(double x, double y);
#ifdef __cplusplus
}
#endif
// Internal backend hooks; window access is restricted to the game thread.
struct _GLFWwindow;
int novaSurfaceAcquire(struct _GLFWwindow* window, int* width, int* height);
void novaSurfaceRelease(struct _GLFWwindow* window);
void* novaSurfaceLayer(struct _GLFWwindow* window);
void novaSurfaceMetrics(int* width, int* height, float* scale);
void novaSurfacePoll(void);
void novaSurfaceWait(double timeout);
void novaSurfaceWake(void);
