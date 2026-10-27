// Copyright (c) 2026 mickey3211. Original NovaCraft Zero proof-of-concept.
// Links official OpenJDK Mobile Zero VM library under the OpenJDK license.
// THIS IS NOT MINECRAFT. It tests whether unsigned iOS IPA re-signed with
// personal Apple ID can execute a Java 21-classfile using an AOT-linked Zero VM.

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#include <jni.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern void loadfunctions(void);

static NSString *NovaDocumentsLogPath(void) {
    return [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)
            .firstObject stringByAppendingPathComponent:@"NovaZeroProbe.log"];
}

@interface NovaZeroViewController : UIViewController
@property(nonatomic, strong) UITextView *console;
@property(nonatomic, strong) UIButton *testButton;
@property(nonatomic, strong) UIButton *shareButton;
@property(nonatomic, assign) BOOL testStarted;
- (void)appendLine:(NSString *)line;
- (void)runZeroTest;
- (void)shareLog;
@end

@interface NovaZeroAppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end

@implementation NovaZeroAppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)opts {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.rootViewController = [[UINavigationController alloc]
                                     initWithRootViewController:[NovaZeroViewController new]];
    [self.window makeKeyAndVisible];
    return YES;
}
@end

@implementation NovaZeroViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"NovaCraft Zero";
    self.view.backgroundColor = [UIColor colorWithRed:0.035 green:0.065 blue:0.12 alpha:1];
    UIView *container = [UIView new];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:container];
    [NSLayoutConstraint activateConstraints:@[
        [container.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:14],
        [container.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-18],
        [container.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:18],
        [container.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-18]
    ]];

    UILabel *heading = [UILabel new];
    heading.text = @"Test JVM bez JIT";
    heading.font = [UIFont systemFontOfSize:27 weight:UIFontWeightBold];
    heading.textColor = [UIColor systemCyanColor];
    heading.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:heading];

    UILabel *intro = [UILabel new];
    intro.text = @"Oficjalne OpenJDK Mobile Zero. Ta aplikacja testuje tylko prostą klasę Java — to nie jest Minecraft i nie modyfikuje głównego NovaCraft.";
    intro.numberOfLines = 0;
    intro.font = [UIFont systemFontOfSize:14];
    intro.textColor = [UIColor lightGrayColor];
    intro.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:intro];

    self.testButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.testButton setTitle:@"Uruchom test JVM Zero" forState:UIControlStateNormal];
    [self.testButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    self.testButton.backgroundColor = [UIColor systemCyanColor];
    self.testButton.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
    self.testButton.layer.cornerRadius = 13;
    self.testButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.testButton addTarget:self action:@selector(runZeroTest) forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:self.testButton];

    self.shareButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.shareButton setTitle:@"Udostępnij raport testu" forState:UIControlStateNormal];
    self.shareButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.shareButton addTarget:self action:@selector(shareLog) forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:self.shareButton];

    self.console = [UITextView new];
    self.console.backgroundColor = [UIColor colorWithWhite:0.09 alpha:1];
    self.console.textColor = [UIColor colorWithRed:0.5 green:0.92 blue:1 alpha:1];
    self.console.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    self.console.editable = NO;
    self.console.layer.cornerRadius = 12;
    self.console.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:self.console];

    [NSLayoutConstraint activateConstraints:@[
        [heading.topAnchor constraintEqualToAnchor:container.topAnchor],
        [heading.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [heading.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [intro.topAnchor constraintEqualToAnchor:heading.bottomAnchor constant:12],
        [intro.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [intro.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [self.testButton.topAnchor constraintEqualToAnchor:intro.bottomAnchor constant:20],
        [self.testButton.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [self.testButton.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [self.testButton.heightAnchor constraintEqualToConstant:54],
        [self.shareButton.topAnchor constraintEqualToAnchor:self.testButton.bottomAnchor constant:10],
        [self.shareButton.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],
        [self.shareButton.heightAnchor constraintEqualToConstant:36],
        [self.console.topAnchor constraintEqualToAnchor:self.shareButton.bottomAnchor constant:10],
        [self.console.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [self.console.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [self.console.bottomAnchor constraintEqualToAnchor:container.bottomAnchor]
    ]];

    [self appendLine:@"NovaCraft ZERO — oddzielny test OpenJDK Mobile"];
    [self appendLine:@"JDK: oficjalny snapshot OpenJDK Mobile (nie Java 21 runtime)"];
    [self appendLine:@"Java class file: target 21 / major 65"];
    [self appendLine:@"Jeżeli iOS zamknie aplikację, prześlij raport .ips."];
    [self appendLine:@"Naciśnij test, aby rozpocząć."];
}

- (void)appendLine:(NSString *)line {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self appendLine:line]; });
        return;
    }
    NSString *entry = [NSString stringWithFormat:@"%@\n", line];
    self.console.text = [self.console.text stringByAppendingString:entry];
    [self.console scrollRangeToVisible:NSMakeRange(self.console.text.length, 0)];
    FILE *f = fopen(NovaDocumentsLogPath().fileSystemRepresentation, "a");
    if (f) {
        fputs(entry.UTF8String ?: "", f);
        fflush(f);
        fclose(f);
    }
}

- (void)runZeroTest {
    if (self.testStarted) return;
    self.testStarted = YES;
    self.testButton.enabled = NO;
    [self appendLine:@"ZERO_START: initializing static native Java VM"];
    NSThread *thread = [[NSThread alloc] initWithTarget:self
                                              selector:@selector(executeJNI)
                                                object:nil];
    thread.name = @"NovaCraft-Zero-JNI";
    thread.stackSize = 16 * 1024 * 1024;
    [thread start];
}

- (void)executeJNI {
    @autoreleasepool {
        NSString *root = [NSBundle mainBundle].resourcePath;
        NSString *jar = [root stringByAppendingPathComponent:@"NovaZeroSmoke.jar"];
        NSString *modules = [root stringByAppendingPathComponent:@"lib/lib/modules"];
        if (![[NSFileManager defaultManager] fileExistsAtPath:jar] ||
            ![[NSFileManager defaultManager] fileExistsAtPath:modules]) {
            [self appendLine:@"ZERO_FAILED: jar or java.base modules missing from IPA"];
            return;
        }

        // Upstream sample explicitly initializes the global native-function
        // map before JNI_CreateJavaVM in its statically linked Zero library.
        [self appendLine:@"ZERO_STEP: loadfunctions()"];
        loadfunctions();

        NSString *cp = [@"-Djava.class.path=" stringByAppendingString:jar];
        // The official OpenJDK Mobile static Zero sample does NOT override
        // java.home. Its mobile runtime locates the bundled modules itself;
        // overriding java.home can incorrectly look in app/lib/modules
        // instead of the officially documented app/lib/lib/modules.
        const char *items[] = {cp.UTF8String, "-Xms16m", "-Xmx128m"};
        JavaVMOption options[3] = {0};
        for (int i = 0; i < 3; i++) options[i].optionString = (char *)items[i];

        JavaVMInitArgs args = {0};
        args.version = JNI_VERSION_1_8;
        args.nOptions = 3;
        args.options = options;
        args.ignoreUnrecognized = JNI_FALSE;

        JavaVM *vm = NULL;
        JNIEnv *env = NULL;
        [self appendLine:@"ZERO_STEP: JNI_CreateJavaVM started"];
        jint result = JNI_CreateJavaVM(&vm, (void **)&env, &args);
        [self appendLine:[NSString stringWithFormat:@"ZERO_STEP: JNI_CreateJavaVM returned %d", (int)result]];
        if (result != JNI_OK || env == NULL) {
            [self appendLine:@"ZERO_FAILED: no usable JavaVM"];
            return;
        }

        jclass cls = (*env)->FindClass(env, "dev/novacraft/zero/NovaZeroSmoke");
        if (cls == NULL || (*env)->ExceptionCheck(env)) {
            (*env)->ExceptionDescribe(env);
            (*env)->ExceptionClear(env);
            [self appendLine:@"ZERO_FAILED: class loading"];
            return;
        }
        jmethodID method = (*env)->GetStaticMethodID(env, cls, "probe", "()Ljava/lang/String;");
        if (method == NULL || (*env)->ExceptionCheck(env)) {
            (*env)->ExceptionDescribe(env);
            (*env)->ExceptionClear(env);
            [self appendLine:@"ZERO_FAILED: probe() method missing"];
            return;
        }
        jstring response = (jstring)(*env)->CallStaticObjectMethod(env, cls, method);
        if ((*env)->ExceptionCheck(env) || response == NULL) {
            (*env)->ExceptionDescribe(env);
            (*env)->ExceptionClear(env);
            [self appendLine:@"ZERO_FAILED: Java method threw an exception"];
            return;
        }
        const char *chars = (*env)->GetStringUTFChars(env, response, NULL);
        if (!chars) {
            [self appendLine:@"ZERO_FAILED: Java UTF conversion"];
            return;
        }
        NSString *message = [NSString stringWithUTF8String:chars] ?: @"<invalid-UTF8>";
        (*env)->ReleaseStringUTFChars(env, response, chars);
        (*env)->DeleteLocalRef(env, response);
        (*env)->DeleteLocalRef(env, cls);
        [self appendLine:message];
        [self appendLine:@"ZERO_JVM_PROBE_OK: JNI class executed on physical iOS device"];
        [self appendLine:@"To nie oznacza jeszcze uruchomienia Minecrafta."];
        // JVM destroy on iOS can block forever; terminate with the app instead.
    }
}

- (void)shareLog {
    NSURL *url = [NSURL fileURLWithPath:NovaDocumentsLogPath()];
    if (![[NSFileManager defaultManager] fileExistsAtPath:url.path]) return;
    UIActivityViewController *sheet = [[UIActivityViewController alloc]
                                      initWithActivityItems:@[url] applicationActivities:nil];
    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = self.shareButton;
        sheet.popoverPresentationController.sourceRect = self.shareButton.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([NovaZeroAppDelegate class]));
    }
}
