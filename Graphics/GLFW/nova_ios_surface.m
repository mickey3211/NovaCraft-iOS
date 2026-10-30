// Copyright (c) 2026 mickey3211. Original NovaCraft surface and event transport.
// Links to GLFW under its own zlib license; imports no launcher application code.
#import <UIKit/UIKit.h>
#import <QuartzCore/CAMetalLayer.h>
#include "internal.h"
#include "nova_ios_surface.h"
#include <pthread.h>
#include <time.h>

// UIKit produces events. The Java/GLFW thread alone consumes them and invokes
// callbacks. Never call a Java callback from a UIKit touch/layout handler.
typedef enum { Move, Button, Key, Character, Scroll, Resize, Focus, Close } EventKind;
typedef struct { EventKind kind; double x, y; int a, b, c, d; } NovaEvent;
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t changed = PTHREAD_COND_INITIALIZER;
static NovaEvent events[1024];
static unsigned int first, count;
static BOOL overflow;
static BOOL wakePending;
static BOOL closing;
static CAMetalLayer* surface;
static _GLFWwindow* owner;
static int surfaceWidth, surfaceHeight;
static float surfaceScale = 1;

static void enqueue(NovaEvent event) {
    pthread_mutex_lock(&lock);
    if (event.kind == Close) closing = YES;
    // Coalesce only consecutive pointer/resize updates; preserve ordering of
    // presses/releases. Overflow causes a focus reset on the consumer thread.
    if (count && (event.kind == Move || event.kind == Resize) &&
        events[(first + count - 1) % 1024].kind == event.kind) {
        events[(first + count - 1) % 1024] = event;
    } else if (count < 1024) {
        events[(first + count++) % 1024] = event;
    } else {
        overflow = YES;
    }
    pthread_cond_signal(&changed);
    pthread_mutex_unlock(&lock);
}

@interface NovaGLFWView : UIView
@property(nonatomic, weak) UITouch* primaryTouch;
@end
@implementation NovaGLFWView
+ (Class)layerClass { return CAMetalLayer.class; }
- (BOOL)canBecomeFirstResponder { return YES; }
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat scale = self.window.screen.scale ?: UIScreen.mainScreen.scale;
    CAMetalLayer* layer = (CAMetalLayer*)self.layer;
    layer.contentsScale = scale;
    layer.drawableSize = CGSizeMake(self.bounds.size.width * scale, self.bounds.size.height * scale);
    pthread_mutex_lock(&lock);
    surfaceWidth = (int)self.bounds.size.width;
    surfaceHeight = (int)self.bounds.size.height;
    surfaceScale = (float)scale;
    pthread_mutex_unlock(&lock);
    enqueue((NovaEvent){.kind=Resize});
}
- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) [self becomeFirstResponder];
    enqueue((NovaEvent){.kind=Focus, .a=self.window != nil});
}
- (void)touchesBegan:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    if (self.primaryTouch) return;
    self.primaryTouch = touches.anyObject;
    CGPoint p = [self.primaryTouch locationInView:self];
    enqueue((NovaEvent){.kind=Move, .x=p.x, .y=p.y});
    enqueue((NovaEvent){.kind=Button, .a=GLFW_MOUSE_BUTTON_LEFT, .b=GLFW_PRESS});
}
- (void)touchesMoved:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    if (![touches containsObject:self.primaryTouch]) return;
    CGPoint p = [self.primaryTouch locationInView:self];
    enqueue((NovaEvent){.kind=Move, .x=p.x, .y=p.y});
}
- (void)touchesEnded:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    if (![touches containsObject:self.primaryTouch]) return;
    enqueue((NovaEvent){.kind=Button, .a=GLFW_MOUSE_BUTTON_LEFT, .b=GLFW_RELEASE});
    self.primaryTouch = nil;
}
- (void)touchesCancelled:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    [self touchesEnded:touches withEvent:event];
}
@end

void* nova_glfw_create_view(void) {
    if (!NSThread.isMainThread) return NULL;
    pthread_mutex_lock(&lock);
    if (surface || owner) { pthread_mutex_unlock(&lock); return NULL; }
    NovaGLFWView* view = [[NovaGLFWView alloc] initWithFrame:CGRectZero];
    view.multipleTouchEnabled = YES;
    view.opaque = YES;
    surface = (CAMetalLayer*)view.layer;
    first = count = 0; overflow = wakePending = closing = NO;
    pthread_mutex_unlock(&lock);
    return (__bridge_retained void*)view;
}
void nova_glfw_request_close(void) { enqueue((NovaEvent){.kind=Close}); }
int nova_glfw_dispose_surface(void) {
    if (!NSThread.isMainThread) return 0;
    pthread_mutex_lock(&lock);
    BOOL unused = owner == NULL;
    if (unused) { surface = nil; first = count = 0; }
    pthread_mutex_unlock(&lock);
    if (!unused) nova_glfw_request_close();
    return unused;
}
static BOOL alive(_GLFWwindow* window) {
    pthread_mutex_lock(&lock); BOOL result = owner == window; pthread_mutex_unlock(&lock);
    return result;
}
void nova_glfw_send_key(int key, int scancode, int action, int mods) {
    enqueue((NovaEvent){.kind=Key, .a=key, .b=scancode, .c=action, .d=mods});
}
void nova_glfw_send_character(unsigned int codepoint) {
    if (codepoint <= 0x10ffff && !(codepoint >= 0xd800 && codepoint <= 0xdfff))
        enqueue((NovaEvent){.kind=Character, .a=(int)codepoint});
}
void nova_glfw_send_scroll(double x, double y) { enqueue((NovaEvent){.kind=Scroll, .x=x, .y=y}); }
void novaSurfaceMetrics(int* width, int* height, float* scale) {
    pthread_mutex_lock(&lock);
    if (width) *width = surfaceWidth;
    if (height) *height = surfaceHeight;
    if (scale) *scale = surfaceScale;
    pthread_mutex_unlock(&lock);
}
int novaSurfaceAcquire(_GLFWwindow* window, int* width, int* height) {
    pthread_mutex_lock(&lock);
    BOOL valid = surface && !owner && surfaceWidth > 0 && surfaceHeight > 0;
    if (valid) { owner = window; *width = surfaceWidth; *height = surfaceHeight; }
    pthread_mutex_unlock(&lock);
    if (!valid) _glfwInputError(GLFW_PLATFORM_ERROR, "NovaCraft: a visible UIKit surface is required; only one game window is supported");
    return valid;
}
void* novaSurfaceLayer(_GLFWwindow* window) {
    pthread_mutex_lock(&lock);
    void* layer = window == owner ? (__bridge void*)surface : NULL;
    pthread_mutex_unlock(&lock);
    return layer;
}
void novaSurfaceRelease(_GLFWwindow* window) {
    pthread_mutex_lock(&lock);
    if (owner == window) { owner = NULL; surface = nil; first = count = 0; }
    pthread_mutex_unlock(&lock);
}
void novaSurfaceWake(void) {
    pthread_mutex_lock(&lock); wakePending = YES;
    pthread_cond_signal(&changed); pthread_mutex_unlock(&lock);
}
void novaSurfaceWait(double timeout) {
    pthread_mutex_lock(&lock);
    if (!count && !overflow && !wakePending) {
        if (timeout < 0) pthread_cond_wait(&changed, &lock);
        else {
            struct timespec deadline;
            clock_gettime(CLOCK_REALTIME, &deadline);
            long long nanos = (long long)(timeout * 1e9) + deadline.tv_nsec;
            deadline.tv_sec += nanos / 1000000000;
            deadline.tv_nsec = nanos % 1000000000;
            pthread_cond_timedwait(&changed, &lock, &deadline);
        }
    }
    wakePending = NO;
    pthread_mutex_unlock(&lock);
    novaSurfacePoll();
}
void novaSurfacePoll(void) {
    // A detached batch permits callbacks to post events without deadlocking.
    NovaEvent batch[1024]; unsigned int n; BOOL reset, close; _GLFWwindow* window;
    pthread_mutex_lock(&lock);
    n = count; reset = overflow; close = closing; overflow = NO; window = owner;
    for (unsigned int i=0; i<n; ++i) batch[i] = events[(first+i)%1024];
    first = count = 0;
    pthread_mutex_unlock(&lock);
    if (!window) return;
    if (close) { _glfwInputWindowCloseRequest(window); return; }
    if (reset) { _glfwInputWindowFocus(window, GLFW_FALSE); return; }
    for (unsigned int i=0; i<n; ++i) {
        // A callback may destroy the window; never reuse it afterwards.
        if (!alive(window)) break;
        NovaEvent e = batch[i];
        switch (e.kind) {
            case Move:
                _glfw.null.xcursor = window->null.xpos + e.x;
                _glfw.null.ycursor = window->null.ypos + e.y;
                _glfwInputCursorPos(window, e.x, e.y); break;
            case Button: _glfwInputMouseClick(window, e.a, e.b, e.c); break;
            case Key: _glfwInputKey(window, e.a, e.b, e.c, e.d); break;
            case Character: _glfwInputChar(window, (unsigned int)e.a, 0, GLFW_TRUE); break;
            case Scroll: _glfwInputScroll(window, e.x, e.y); break;
            case Focus: _glfwInputWindowFocus(window, e.a); break;
            case Close: _glfwInputWindowCloseRequest(window); break;
            case Resize: {
                int w,h; float scale; novaSurfaceMetrics(&w,&h,&scale);
                window->null.width=w; window->null.height=h;
                _glfwInputWindowSize(window,w,h);
                if (alive(window)) _glfwInputFramebufferSize(window, (int)(w*scale), (int)(h*scale));
                if (alive(window)) _glfwInputWindowContentScale(window, scale, scale);
                break;
            }
        }
    }
}
